import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  DEFAULT_ESCALATION_CONFIG,
  EscalationDocState,
  evaluateEscalationTick,
  FamilyMember,
  GatewayState,
  istDateTimeToMs,
  TickInput,
} from '../src/escalationLogic';

const DATE = '2026-11-10';
const SLOTS = {
  morning: '08:30',
  noon: '13:30',
  evening: '20:30',
};

const USERS: FamilyMember[] = [
  { uid: 'u-george', name: 'George', phone: '+919000000001' },
  { uid: 'u-dolly', name: 'Dolly', phone: '+919000000002' },
  { uid: 'u-leo', name: 'Leo', phone: '+919000000003' },
  { uid: 'u-geo', name: 'Geo', phone: '+919000000004' },
];

function onlineGateway(nowMs: number): GatewayState {
  return {
    uid: 'u-geo',
    phone: '+919000000004',
    lastSeenMs: nowMs - 30_000, // 30 seconds ago
    simReady: true,
    offlineWarningSentForLastSeenMs: null,
  };
}

function baseInput(nowMs: number, overrides?: Partial<TickInput>): TickInput {
  return {
    nowMs,
    batch: {
      id: 'batch-1',
      placedDate: '2026-11-10', // Day 1
      stopRemindersFromDay: 18,
    },
    slots: SLOTS,
    rotationStatusByKey: {},
    escalationStateByKey: {},
    config: DEFAULT_ESCALATION_CONFIG,
    users: USERS,
    gateway: onlineGateway(nowMs),
    ...overrides,
  };
}

describe('escalationLogic timeline simulations', () => {
  it('1. Done at +5 min: no escalation steps ever fire', () => {
    const tPlus5 = istDateTimeToMs(DATE, '08:35');
    const out1 = evaluateEscalationTick(
      baseInput(tPlus5, {
        rotationStatusByKey: { [`${DATE}_morning`]: true },
      })
    );
    assert.equal(out1.plans.length, 0);

    const tPlus15 = istDateTimeToMs(DATE, '08:45');
    const out2 = evaluateEscalationTick(
      baseInput(tPlus15, {
        rotationStatusByKey: { [`${DATE}_morning`]: true },
      })
    );
    assert.equal(out2.plans.length, 0);
  });

  it('2. Done at +25 min: +10 and +20 fire beforehand, +30 and +45 never fire after done', () => {
    // At +10 (08:40) -> FCM + Telegram
    const t10 = istDateTimeToMs(DATE, '08:40');
    const out10 = evaluateEscalationTick(baseInput(t10));
    assert.equal(out10.plans.length, 1);
    assert.equal(out10.plans[0].stepOffsetMinutes, 10);
    assert.deepEqual(
      out10.plans[0].commands.map((c) => c.kind),
      ['fcm_push', 'telegram']
    );

    // At +20 (08:50), with step 10 recorded -> Call George
    const t20 = istDateTimeToMs(DATE, '08:50');
    const stateAt20: EscalationDocState = {
      firedSteps: [10],
      calledNames: [],
      smsSentNames: [],
      telegramCount: 1,
      status: 'active',
    };
    const out20 = evaluateEscalationTick(
      baseInput(t20, {
        escalationStateByKey: { [`${DATE}_morning`]: stateAt20 },
      })
    );
    assert.equal(out20.plans.length, 1);
    assert.equal(out20.plans[0].stepOffsetMinutes, 20);
    assert.equal(out20.plans[0].commands[0].kind, 'gateway_command');
    if (out20.plans[0].commands[0].kind === 'gateway_command') {
      assert.equal(out20.plans[0].commands[0].commandType, 'call');
      assert.equal(out20.plans[0].commands[0].targetName, 'George');
    }

    // Done at +25 -> at +30 (09:00), rotationExists = true -> nothing fires
    const t30 = istDateTimeToMs(DATE, '09:00');
    const out30 = evaluateEscalationTick(
      baseInput(t30, {
        rotationStatusByKey: { [`${DATE}_morning`]: true },
        escalationStateByKey: {
          [`${DATE}_morning`]: {
            firedSteps: [10, 20],
            calledNames: ['George'],
            smsSentNames: [],
            telegramCount: 1,
            status: 'active',
          },
        },
      })
    );
    assert.equal(out30.plans.length, 0);
  });

  it('3. Never done: full timeline (+10, +20, +30, +45, +60 missed)', () => {
    const state: EscalationDocState = {
      firedSteps: [],
      calledNames: [],
      smsSentNames: [],
      telegramCount: 0,
      status: 'active',
    };

    // +10 min (08:40)
    let out = evaluateEscalationTick(
      baseInput(istDateTimeToMs(DATE, '08:40'), {
        escalationStateByKey: { [`${DATE}_morning`]: state },
      })
    );
    assert.equal(out.plans[0].stepOffsetMinutes, 10);
    state.firedSteps.push(10);
    state.telegramCount += out.plans[0].telegramCountIncrement;

    // +20 min (08:50) -> call George
    out = evaluateEscalationTick(
      baseInput(istDateTimeToMs(DATE, '08:50'), {
        escalationStateByKey: { [`${DATE}_morning`]: state },
      })
    );
    assert.equal(out.plans[0].stepOffsetMinutes, 20);
    assert.deepEqual(out.plans[0].newlyCalledNames, ['George']);
    state.firedSteps.push(20);
    state.calledNames.push('George');

    // +30 min (09:00) -> call Dolly + SMS George, Dolly, Leo (not Geo)
    out = evaluateEscalationTick(
      baseInput(istDateTimeToMs(DATE, '09:00'), {
        escalationStateByKey: { [`${DATE}_morning`]: state },
      })
    );
    assert.equal(out.plans[0].stepOffsetMinutes, 30);
    assert.deepEqual(out.plans[0].newlyCalledNames, ['Dolly']);
    assert.deepEqual(out.plans[0].newlySmsNames, ['George', 'Dolly', 'Leo']);
    state.firedSteps.push(30);
    state.calledNames.push('Dolly');
    state.smsSentNames.push('George', 'Dolly', 'Leo');

    // +45 min (09:15) -> call Leo + urgent Telegram
    out = evaluateEscalationTick(
      baseInput(istDateTimeToMs(DATE, '09:15'), {
        escalationStateByKey: { [`${DATE}_morning`]: state },
      })
    );
    assert.equal(out.plans[0].stepOffsetMinutes, 45);
    assert.deepEqual(out.plans[0].newlyCalledNames, ['Leo']);
    const urgentTg = out.plans[0].commands.find((c) => c.kind === 'telegram');
    assert.ok(urgentTg && urgentTg.kind === 'telegram');
    assert.match(urgentTg.text, /മുട്ട ഇതുവരെ തിരിച്ചിട്ടില്ല/);
    state.firedSteps.push(45);

    // +60 min (09:30) -> mark missed
    out = evaluateEscalationTick(
      baseInput(istDateTimeToMs(DATE, '09:30'), {
        escalationStateByKey: { [`${DATE}_morning`]: state },
      })
    );
    assert.equal(out.plans.length, 1);
    assert.equal(out.plans[0].markMissed, true);
    assert.equal(out.plans[0].commands[0].kind, 'mark_missed');
  });

  it('4. Lockdown day (Day 18+): produces no escalation', () => {
    const tPlus20 = istDateTimeToMs('2026-11-27', '08:50'); // Placed Nov 10 -> Nov 27 is Day 18
    const out = evaluateEscalationTick(baseInput(tPlus20));
    assert.equal(out.incubationDay, 18);
    assert.equal(out.isLockdown, true);
    assert.equal(out.plans.length, 0);
  });

  it('5. Gateway offline: skips call/SMS, warns on Telegram, keeps FCM push', () => {
    const tPlus30 = istDateTimeToMs(DATE, '09:00');
    const offlineGw: GatewayState = {
      uid: 'u-geo',
      phone: '+919000000004',
      lastSeenMs: tPlus30 - 5 * 60_000, // 5 minutes ago (> 3m threshold)
      simReady: true,
      offlineWarningSentForLastSeenMs: null,
    };

    const out = evaluateEscalationTick(
      baseInput(tPlus30, {
        gateway: offlineGw,
        escalationStateByKey: {
          [`${DATE}_morning`]: {
            firedSteps: [10, 20],
            calledNames: ['George'],
            smsSentNames: [],
            telegramCount: 1,
            status: 'active',
          },
        },
      })
    );

    assert.equal(out.gatewayOnline, false);
    assert.equal(out.shouldSendGatewayOfflineWarning, true);
    assert.equal(out.plans.length, 1);
    // No gateway_command created
    const gwCmds = out.plans[0].commands.filter(
      (c) => c.kind === 'gateway_command'
    );
    assert.equal(gwCmds.length, 0);
    // Telegram offline-skip message emitted
    const tgSkip = out.plans[0].commands.find(
      (c) => c.kind === 'telegram' && c.variant === 'gateway_offline_skip'
    );
    assert.ok(tgSkip);
  });

  it('6. Duplicate ticks: idempotent, never double-calls when firedSteps includes step', () => {
    const t21 = istDateTimeToMs(DATE, '08:51');
    const out = evaluateEscalationTick(
      baseInput(t21, {
        escalationStateByKey: {
          [`${DATE}_morning`]: {
            firedSteps: [10, 20],
            calledNames: ['George'],
            smsSentNames: [],
            telegramCount: 1,
            status: 'active',
          },
        },
      })
    );
    assert.equal(out.plans.length, 0);
  });

  it('7. Anti-flood: skips step older than 10 minutes after scheduled offset', () => {
    // At +25 (08:55), step 10 is 15 minutes late (> 10m tolerance) -> skipped; step 20 fires
    const t25 = istDateTimeToMs(DATE, '08:55');
    const out = evaluateEscalationTick(baseInput(t25));
    const step10 = out.plans.find((p) => p.stepOffsetMinutes === 10);
    const step20 = out.plans.find((p) => p.stepOffsetMinutes === 20);
    assert.ok(step10);
    assert.equal(step10.commands.length, 0);
    assert.ok(step10.skippedReasons[0].includes('Stale step'));
    assert.ok(step20);
    assert.equal(step20.commands.length, 1);
  });

  it('8. Gateway self-call guard: never calls gateway own phone/UID', () => {
    const t20 = istDateTimeToMs(DATE, '08:50');
    const out = evaluateEscalationTick(
      baseInput(t20, {
        escalationStateByKey: {
          [`${DATE}_morning`]: {
            firedSteps: [10],
            calledNames: [],
            smsSentNames: [],
            telegramCount: 1,
            status: 'active',
          },
        },
        config: {
          ...DEFAULT_ESCALATION_CONFIG,
          callOrder: ['Geo', 'George', 'Dolly'],
        },
      })
    );
    assert.equal(out.plans[0].commands.length, 0);
    assert.ok(
      out.plans[0].skippedReasons.some((r) => r.includes('self-call'))
    );
  });

  it('9. Fail loud: if rotation check failed (null), escalate anyway', () => {
    const t10 = istDateTimeToMs(DATE, '08:40');
    const out = evaluateEscalationTick(
      baseInput(t10, {
        rotationStatusByKey: { [`${DATE}_morning`]: null },
      })
    );
    assert.equal(out.plans.length, 1);
    assert.equal(out.plans[0].commands.length, 2);
  });

  it('10. Mute today: if mutedDate equals today (e.g. user in a function), no escalations fire', () => {
    const t20 = istDateTimeToMs(DATE, '08:50');
    const out = evaluateEscalationTick(
      baseInput(t20, {
        mutedDate: DATE,
      })
    );
    assert.equal(out.plans.length, 0);
  });

  it('11. Mute multi-day: if mutedUntilDate covers today, no escalations fire', () => {
    const t20 = istDateTimeToMs(DATE, '08:50');
    const out = evaluateEscalationTick(
      baseInput(t20, {
        mutedUntilDate: '2026-11-20', // future date
      })
    );
    assert.equal(out.plans.length, 0);
  });
});
