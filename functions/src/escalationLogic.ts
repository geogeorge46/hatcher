/**
 * escalationLogic.ts — Pure, side-effect-free escalation state machine.
 *
 * ZERO Firebase imports or network calls live here so that the entire
 * escalation timeline, lockdown gating, rate limits, gateway offline checks,
 * and anti-flood window can be deterministically unit-tested.
 */

export type SlotKey = 'morning' | 'noon' | 'evening';

export type StepActionType =
  | 'fcm_push'
  | 'telegram_prompt'
  | 'telegram_urgent'
  | 'call'
  | 'sms_others';

export interface EscalationStepConfig {
  offsetMinutes: number;
  actions: StepActionType[];
  /** Index into callOrder when actions includes 'call' (0 = #1, 1 = #2, ...) */
  callIndex?: number;
}

export interface EscalationConfig {
  enabled: boolean;
  steps: EscalationStepConfig[];
  /** Ordered names to call, e.g. ['George', 'Dolly', 'Leo']. Geo omitted by default. */
  callOrder: string[];
  /** Stop escalating and mark slot 'missed' after this many minutes from due time. */
  stopAfterMinutes: number;
}

export interface FamilyMember {
  uid: string;
  name: string;
  phone?: string;
  fcmToken?: string;
  telegramUserId?: number;
}

export interface GatewayState {
  uid: string;
  phone?: string;
  lastSeenMs: number | null;
  simReady: boolean;
  offlineWarningSentForLastSeenMs?: number | null;
}

export interface EscalationDocState {
  firedSteps: number[];
  calledNames: string[];
  smsSentNames: string[];
  telegramCount: number;
  status: 'active' | 'done' | 'missed';
}

export interface SlotContext {
  dateStr: string; // 'yyyy-MM-dd' in Asia/Kolkata
  slotKey: SlotKey;
  dueTimeStr: string; // 'HH:mm' in Asia/Kolkata
  /**
   * Whether the rotation doc exists for this slot.
   * null/undefined means the check failed -> FAIL LOUD (treat as NOT done).
   */
  rotationExists: boolean | null | undefined;
}

export interface BatchContext {
  id: string;
  placedDate: string; // 'yyyy-MM-dd' in Asia/Kolkata
  stopRemindersFromDay: number; // 0 = never stop
}

export interface TickInput {
  nowMs: number;
  batch: BatchContext | null;
  slots: Record<SlotKey, string>;
  /** Map of `${dateStr}_${slotKey}` -> rotationExists boolean (or null if check failed). */
  rotationStatusByKey: Record<string, boolean | null | undefined>;
  /** Existing escalation docs keyed by `${dateStr}_${slotKey}`. */
  escalationStateByKey: Record<string, EscalationDocState | undefined>;
  config: EscalationConfig;
  users: FamilyMember[];
  gateway: GatewayState | null;
}

export type PlannedCommand =
  | {
      kind: 'fcm_push';
      dateStr: string;
      slotKey: SlotKey;
      symbol: string;
      text: string;
    }
  | {
      kind: 'telegram';
      dateStr: string;
      slotKey: SlotKey;
      variant: 'prompt' | 'urgent' | 'gateway_offline_skip';
      symbol: string;
      text: string;
      includeRotateButton: boolean;
    }
  | {
      kind: 'gateway_command';
      commandType: 'call' | 'sms';
      dateStr: string;
      slotKey: SlotKey;
      targetUid: string;
      targetName: string;
      phone: string;
      text: string;
    }
  | {
      kind: 'mark_missed';
      dateStr: string;
      slotKey: SlotKey;
    };

export interface StepPlan {
  dateStr: string;
  slotKey: SlotKey;
  stepOffsetMinutes: number;
  commands: PlannedCommand[];
  newlyCalledNames: string[];
  newlySmsNames: string[];
  telegramCountIncrement: number;
  markMissed: boolean;
  skippedReasons: string[];
}

export interface TickOutput {
  isLockdown: boolean;
  incubationDay: number | null;
  gatewayOnline: boolean;
  shouldSendGatewayOfflineWarning: boolean;
  plans: StepPlan[];
}

// ---------------------------------------------------------------------------
// Constants & Defaults
// ---------------------------------------------------------------------------

export const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;
export const GATEWAY_OFFLINE_THRESHOLD_MS = 3 * 60 * 1000; // 3 minutes
export const STALE_STEP_MAX_DELAY_MINUTES = 10;
export const MAX_TELEGRAM_PER_SLOT = 3;

export const SLOT_SYMBOLS: Record<SlotKey, string> = {
  morning: '|',
  noon: '∆',
  evening: '•',
};

export const DEFAULT_ESCALATION_CONFIG: EscalationConfig = {
  enabled: true,
  callOrder: ['George', 'Dolly', 'Leo'],
  stopAfterMinutes: 60,
  steps: [
    { offsetMinutes: 10, actions: ['fcm_push', 'telegram_prompt'] },
    { offsetMinutes: 20, actions: ['call'], callIndex: 0 },
    { offsetMinutes: 30, actions: ['call', 'sms_others'], callIndex: 1 },
    { offsetMinutes: 45, actions: ['call', 'telegram_urgent'], callIndex: 2 },
  ],
};

// ---------------------------------------------------------------------------
// IST Date / Time Helpers (pure UTC offset math — host-timezone independent)
// ---------------------------------------------------------------------------

/** Returns 'yyyy-MM-dd' and 'HH:mm' in Asia/Kolkata for an epoch timestamp. */
export function toIstParts(epochMs: number): {
  dateStr: string;
  hours: number;
  minutes: number;
} {
  const ist = new Date(epochMs + IST_OFFSET_MS);
  const year = ist.getUTCFullYear();
  const month = String(ist.getUTCMonth() + 1).padStart(2, '0');
  const day = String(ist.getUTCDate()).padStart(2, '0');
  return {
    dateStr: `${year}-${month}-${day}`,
    hours: ist.getUTCHours(),
    minutes: ist.getUTCMinutes(),
  };
}

/** Parses 'yyyy-MM-dd' + 'HH:mm' in Asia/Kolkata into UTC epoch milliseconds. */
export function istDateTimeToMs(dateStr: string, timeStr: string): number {
  const [y, m, d] = dateStr.split('-').map(Number);
  const [hh, mm] = timeStr.split(':').map(Number);
  const utcAtIstWallClock = Date.UTC(y, m - 1, d, hh, mm, 0, 0);
  return utcAtIstWallClock - IST_OFFSET_MS;
}

/** Computes 1-based incubation day in IST. Day 1 = placedDate. */
export function computeIstIncubationDay(
  placedDateStr: string,
  nowMs: number
): number {
  const { dateStr: todayIst } = toIstParts(nowMs);
  const placedMs = istDateTimeToMs(placedDateStr, '00:00');
  const todayMs = istDateTimeToMs(todayIst, '00:00');
  const diffDays = Math.round((todayMs - placedMs) / (24 * 60 * 60 * 1000));
  return Math.max(1, diffDays + 1);
}

/** Formats Malayalam reminder text with the slot's symbol. */
export function buildSlotReminderText(slotKey: SlotKey): string {
  const symbol = SLOT_SYMBOLS[slotKey];
  return `മുട്ട തിരിക്കാൻ സമയമായി – ഇപ്പോൾ ${symbol} വെക്കണം`;
}

/** Checks if gateway heartbeat is fresh (<= 3 minutes old). */
export function isGatewayOnline(
  gateway: GatewayState | null,
  nowMs: number
): boolean {
  if (!gateway || gateway.lastSeenMs == null) return false;
  return nowMs - gateway.lastSeenMs <= GATEWAY_OFFLINE_THRESHOLD_MS;
}

// ---------------------------------------------------------------------------
// Core Pure Tick Evaluation
// ---------------------------------------------------------------------------

/**
 * Evaluates all slots for today (IST) at [input.nowMs] and returns a deterministic
 * plan of commands and state transitions to execute.
 */
export function evaluateEscalationTick(input: TickInput): TickOutput {
  const gatewayOnline = isGatewayOnline(input.gateway, input.nowMs);

  // Check if we should emit the one-time gateway offline Telegram warning.
  // Triggered when gateway has been registered (lastSeenMs != null), is now offline (> 3 min),
  // and we haven't already warned for this exact lastSeenMs.
  const shouldSendGatewayOfflineWarning =
    input.config.enabled &&
    input.batch != null &&
    !gatewayOnline &&
    input.gateway != null &&
    input.gateway.lastSeenMs != null &&
    input.gateway.offlineWarningSentForLastSeenMs !== input.gateway.lastSeenMs;

  if (!input.batch || !input.config.enabled) {
    return {
      isLockdown: false,
      incubationDay: null,
      gatewayOnline,
      shouldSendGatewayOfflineWarning: false,
      plans: [],
    };
  }

  const incubationDay = computeIstIncubationDay(
    input.batch.placedDate,
    input.nowMs
  );
  const stopDay = input.batch.stopRemindersFromDay;
  const isLockdown = stopDay > 0 && incubationDay >= stopDay;

  // Lockdown or post-hatch (day > 21): no escalation!
  if (isLockdown || incubationDay > 21) {
    return {
      isLockdown,
      incubationDay,
      gatewayOnline,
      shouldSendGatewayOfflineWarning: false,
      plans: [],
    };
  }

  const { dateStr: todayDateStr } = toIstParts(input.nowMs);
  const slotKeys: SlotKey[] = ['morning', 'noon', 'evening'];
  const plans: StepPlan[] = [];

  for (const slotKey of slotKeys) {
    const dueTimeStr = input.slots[slotKey];
    if (!dueTimeStr) continue;

    const docKey = `${todayDateStr}_${slotKey}`;
    const rotationExists = input.rotationStatusByKey[docKey];

    // If explicitly confirmed done, skip escalation completely.
    // Note: if rotationExists is null/undefined (check failed), FAIL LOUD -> escalate!
    if (rotationExists === true) {
      continue;
    }

    const existingState: EscalationDocState = input.escalationStateByKey[
      docKey
    ] ?? {
      firedSteps: [],
      calledNames: [],
      smsSentNames: [],
      telegramCount: 0,
      status: 'active',
    };

    if (existingState.status === 'done' || existingState.status === 'missed') {
      continue;
    }

    const dueMs = istDateTimeToMs(todayDateStr, dueTimeStr);
    const elapsedMinutes = Math.floor((input.nowMs - dueMs) / 60_000);

    // Not due yet
    if (elapsedMinutes < 0) continue;

    // 1. Check stop-after cutoff (e.g. +60 min -> mark missed)
    if (elapsedMinutes >= input.config.stopAfterMinutes) {
      plans.push({
        dateStr: todayDateStr,
        slotKey,
        stepOffsetMinutes: input.config.stopAfterMinutes,
        commands: [
          {
            kind: 'mark_missed',
            dateStr: todayDateStr,
            slotKey,
          },
        ],
        newlyCalledNames: [],
        newlySmsNames: [],
        telegramCountIncrement: 0,
        markMissed: true,
        skippedReasons: [],
      });
      continue;
    }

    // 2. Evaluate configured ladder steps in ascending offset order
    const sortedSteps = [...input.config.steps].sort(
      (a, b) => a.offsetMinutes - b.offsetMinutes
    );

    let runningTelegramCount = existingState.telegramCount;
    const runningCalled = new Set(existingState.calledNames);
    const runningSms = new Set(existingState.smsSentNames);

    for (const step of sortedSteps) {
      if (elapsedMinutes < step.offsetMinutes) continue;
      if (existingState.firedSteps.includes(step.offsetMinutes)) continue;

      // Anti-flood protection: never fire a step more than 10 minutes past its offset.
      if (elapsedMinutes - step.offsetMinutes > STALE_STEP_MAX_DELAY_MINUTES) {
        plans.push({
          dateStr: todayDateStr,
          slotKey,
          stepOffsetMinutes: step.offsetMinutes,
          commands: [],
          newlyCalledNames: [],
          newlySmsNames: [],
          telegramCountIncrement: 0,
          markMissed: false,
          skippedReasons: [
            `Stale step +${step.offsetMinutes}m skipped (elapsed ${elapsedMinutes}m > +${STALE_STEP_MAX_DELAY_MINUTES}m tolerance)`,
          ],
        });
        continue;
      }

      const plan = buildStepPlan({
        step,
        dateStr: todayDateStr,
        slotKey,
        config: input.config,
        users: input.users,
        gateway: input.gateway,
        gatewayOnline,
        runningTelegramCount,
        runningCalled,
        runningSms,
      });

      runningTelegramCount += plan.telegramCountIncrement;
      plan.newlyCalledNames.forEach((n) => runningCalled.add(n));
      plan.newlySmsNames.forEach((n) => runningSms.add(n));

      plans.push(plan);
    }
  }

  return {
    isLockdown,
    incubationDay,
    gatewayOnline,
    shouldSendGatewayOfflineWarning,
    plans,
  };
}

function buildStepPlan(params: {
  step: EscalationStepConfig;
  dateStr: string;
  slotKey: SlotKey;
  config: EscalationConfig;
  users: FamilyMember[];
  gateway: GatewayState | null;
  gatewayOnline: boolean;
  runningTelegramCount: number;
  runningCalled: Set<string>;
  runningSms: Set<string>;
}): StepPlan {
  const {
    step,
    dateStr,
    slotKey,
    config,
    users,
    gateway,
    gatewayOnline,
    runningCalled,
    runningSms,
  } = params;
  let tgCount = params.runningTelegramCount;

  const commands: PlannedCommand[] = [];
  const newlyCalledNames: string[] = [];
  const newlySmsNames: string[] = [];
  const skippedReasons: string[] = [];
  let tgIncrement = 0;
  let gatewayOfflineNotifiedInStep = false;

  const symbol = SLOT_SYMBOLS[slotKey];
  const promptText = buildSlotReminderText(slotKey);

  for (const action of step.actions) {
    switch (action) {
      case 'fcm_push': {
        commands.push({
          kind: 'fcm_push',
          dateStr,
          slotKey,
          symbol,
          text: promptText,
        });
        break;
      }

      case 'telegram_prompt': {
        if (tgCount < MAX_TELEGRAM_PER_SLOT) {
          commands.push({
            kind: 'telegram',
            dateStr,
            slotKey,
            variant: 'prompt',
            symbol,
            text: promptText,
            includeRotateButton: true,
          });
          tgCount++;
          tgIncrement++;
        } else {
          skippedReasons.push('Telegram rate limit (3/slot) reached');
        }
        break;
      }

      case 'telegram_urgent': {
        if (tgCount < MAX_TELEGRAM_PER_SLOT) {
          commands.push({
            kind: 'telegram',
            dateStr,
            slotKey,
            variant: 'urgent',
            symbol,
            text: `🚨 മുട്ട ഇതുവരെ തിരിച്ചിട്ടില്ല! (${symbol})`,
            includeRotateButton: true,
          });
          tgCount++;
          tgIncrement++;
        } else {
          skippedReasons.push('Telegram rate limit (3/slot) reached');
        }
        break;
      }

      case 'call': {
        const idx = step.callIndex ?? 0;
        const targetName = config.callOrder[idx];
        if (!targetName) {
          skippedReasons.push(`No target configured at callOrder[${idx}]`);
          break;
        }
        if (runningCalled.has(targetName)) {
          skippedReasons.push(`Call rate limit: ${targetName} already called for slot`);
          break;
        }

        const user = users.find((u) => u.name === targetName);
        if (!user || !user.phone) {
          skippedReasons.push(`No phone number for ${targetName}`);
          break;
        }

        // Gateway self-call guard
        if (
          gateway &&
          (user.uid === gateway.uid ||
            (gateway.phone && user.phone === gateway.phone))
        ) {
          skippedReasons.push(`Skipped self-call to gateway (${targetName})`);
          break;
        }

        if (!gatewayOnline) {
          skippedReasons.push(`Gateway offline — skipped call to ${targetName}`);
          if (!gatewayOfflineNotifiedInStep && tgCount < MAX_TELEGRAM_PER_SLOT) {
            commands.push({
              kind: 'telegram',
              dateStr,
              slotKey,
              variant: 'gateway_offline_skip',
              symbol,
              text: `⚠️ Calls not possible, gateway offline (${targetName} not called)`,
              includeRotateButton: true,
            });
            tgCount++;
            tgIncrement++;
            gatewayOfflineNotifiedInStep = true;
          }
          break;
        }

        commands.push({
          kind: 'gateway_command',
          commandType: 'call',
          dateStr,
          slotKey,
          targetUid: user.uid,
          targetName: user.name,
          phone: user.phone,
          text: promptText,
        });
        newlyCalledNames.push(user.name);
        break;
      }

      case 'sms_others': {
        if (!gatewayOnline) {
          skippedReasons.push('Gateway offline — skipped SMS (SMS requires gateway SIM)');
          if (!gatewayOfflineNotifiedInStep && tgCount < MAX_TELEGRAM_PER_SLOT) {
            commands.push({
              kind: 'telegram',
              dateStr,
              slotKey,
              variant: 'gateway_offline_skip',
              symbol,
              text: '⚠️ Calls/SMS not possible, gateway offline',
              includeRotateButton: true,
            });
            tgCount++;
            tgIncrement++;
            gatewayOfflineNotifiedInStep = true;
          }
          break;
        }

        for (const user of users) {
          if (!user.phone) continue;
          // Skip gateway's own number for SMS too unless needed; prompt says "sends SMS to all others"
          if (
            gateway &&
            (user.uid === gateway.uid ||
              (gateway.phone && user.phone === gateway.phone))
          ) {
            continue;
          }
          if (runningSms.has(user.name)) {
            skippedReasons.push(`SMS rate limit: ${user.name} already texted`);
            continue;
          }
          commands.push({
            kind: 'gateway_command',
            commandType: 'sms',
            dateStr,
            slotKey,
            targetUid: user.uid,
            targetName: user.name,
            phone: user.phone,
            text: `Hatcher: ${promptText}`,
          });
          newlySmsNames.push(user.name);
        }
        break;
      }
    }
  }

  return {
    dateStr,
    slotKey,
    stepOffsetMinutes: step.offsetMinutes,
    commands,
    newlyCalledNames,
    newlySmsNames,
    telegramCountIncrement: tgIncrement,
    markMissed: false,
    skippedReasons,
  };
}
