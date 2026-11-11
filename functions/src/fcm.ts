import * as admin from 'firebase-admin';
import { SlotKey, SLOT_SYMBOLS } from './escalationLogic';

/**
 * Sends a high-priority FCM escalation push (notification + data) to all registered phones.
 */
export async function sendEscalationPushToAll(params: {
  messaging: admin.messaging.Messaging;
  tokens: string[];
  dateStr: string;
  slotKey: SlotKey;
  text: string;
}): Promise<{ successCount: number; failureCount: number }> {
  const uniqueTokens = Array.from(new Set(params.tokens.filter(Boolean)));
  if (uniqueTokens.length === 0) {
    return { successCount: 0, failureCount: 0 };
  }

  const symbol = SLOT_SYMBOLS[params.slotKey];
  const response = await params.messaging.sendEachForMulticast({
    tokens: uniqueTokens,
    android: {
      priority: 'high',
      notification: {
        channelId: 'hatcher_alarm_channel_v2',
        priority: 'max',
      },
    },
    notification: {
      title: `Hatcher (${symbol})`,
      body: params.text,
    },
    data: {
      action: 'escalate_notice',
      date: params.dateStr,
      slotKey: params.slotKey,
      symbol,
      text: params.text,
    },
  });

  return {
    successCount: response.successCount,
    failureCount: response.failureCount,
  };
}

/**
 * Sends a high-priority data-only FCM message to all phones telling them to
 * cancel any local alarms / notifications for this slot (app may be closed).
 */
export async function sendCancelSlotToAll(params: {
  messaging: admin.messaging.Messaging;
  tokens: string[];
  dateStr: string;
  slotKey: string;
  doneBy: string;
}): Promise<{ successCount: number; failureCount: number }> {
  const uniqueTokens = Array.from(new Set(params.tokens.filter(Boolean)));
  if (uniqueTokens.length === 0) {
    return { successCount: 0, failureCount: 0 };
  }

  const response = await params.messaging.sendEachForMulticast({
    tokens: uniqueTokens,
    android: {
      priority: 'high',
    },
    data: {
      action: 'cancel_slot',
      date: params.dateStr,
      slotKey: params.slotKey,
      doneBy: params.doneBy,
    },
  });

  return {
    successCount: response.successCount,
    failureCount: response.failureCount,
  };
}

/**
 * Wakes the gateway phone from Doze when a new command doc is queued.
 */
export async function sendWakeGatewayPush(params: {
  messaging: admin.messaging.Messaging;
  gatewayToken: string;
  commandId: string;
  dateStr: string;
  slotKey: SlotKey;
}): Promise<void> {
  if (!params.gatewayToken) return;
  await params.messaging.send({
    token: params.gatewayToken,
    android: {
      priority: 'high',
    },
    data: {
      action: 'wake_gateway',
      commandId: params.commandId,
      date: params.dateStr,
      slotKey: params.slotKey,
    },
  });
}
