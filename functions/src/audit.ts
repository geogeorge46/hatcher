import * as admin from 'firebase-admin';

export type AuditChannel = 'fcm' | 'telegram' | 'call' | 'sms' | 'system';

export interface AuditEntryInput {
  date: string;
  slotKey: string;
  channel: AuditChannel;
  targetName: string;
  result: string;
  details?: string;
}

const THIRTY_DAYS_MS = 30 * 24 * 60 * 60 * 1000;

/**
 * Writes an audit trail record to `auditLogs/{logId}` with a 30-day TTL.
 */
export async function logAudit(
  db: admin.firestore.Firestore,
  entry: AuditEntryInput
): Promise<void> {
  const nowMs = Date.now();
  await db.collection('auditLogs').add({
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    createdAtMs: nowMs,
    expiresAt: admin.firestore.Timestamp.fromMillis(nowMs + THIRTY_DAYS_MS),
    date: entry.date,
    slotKey: entry.slotKey,
    channel: entry.channel,
    targetName: entry.targetName,
    result: entry.result,
    details: entry.details ?? '',
  });
}
