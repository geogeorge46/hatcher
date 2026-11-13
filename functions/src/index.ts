import * as admin from 'firebase-admin';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onRequest, onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { defineSecret } from 'firebase-functions/params';
import {
  DEFAULT_ESCALATION_CONFIG,
  EscalationConfig,
  EscalationDocState,
  evaluateEscalationTick,
  FamilyMember,
  GatewayState,
  IST_OFFSET_MS,
  SlotKey,
  toIstParts,
} from './escalationLogic';
import {
  answerCallbackQuery,
  editMessageAsDone,
  sendGroupEscalationMessage,
  sendGroupTextMessage,
  sendRegistrationButtons,
} from './telegram';
import {
  sendCancelSlotToAll,
  sendEscalationPushToAll,
  sendWakeGatewayPush,
} from './fcm';
import { logAudit } from './audit';

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

const REGION = 'asia-south1';
const telegramBotToken = defineSecret('TELEGRAM_BOT_TOKEN');
const telegramWebhookSecret = defineSecret('TELEGRAM_WEBHOOK_SECRET');

function formatIstTime(date: Date): string {
  const ist = new Date(date.getTime() + IST_OFFSET_MS);
  let hours = ist.getUTCHours();
  const minutes = String(ist.getUTCMinutes()).padStart(2, '0');
  const ampm = hours >= 12 ? 'PM' : 'AM';
  hours = hours % 12 || 12;
  return `${hours}:${minutes} ${ampm}`;
}

// ---------------------------------------------------------------------------
// 1. Scheduled Escalation Tick (every 1 minute, Asia/Kolkata)
// ---------------------------------------------------------------------------
export const escalationTick = onSchedule(
  {
    region: REGION,
    schedule: 'every 1 minutes',
    timeZone: 'Asia/Kolkata',
    secrets: [telegramBotToken],
  },
  async () => {
    const nowMs = Date.now();
    const { dateStr: todayIst } = toIstParts(nowMs);

    // Load active batch
    const batchSnap = await db
      .collection('batches')
      .where('status', '==', 'active')
      .limit(1)
      .get();

    if (batchSnap.empty) return;
    const batchDoc = batchSnap.docs[0];
    const batchData = batchDoc.data();

    // Load settings/main & settings/escalation & settings/telegram
    const [mainSettingsSnap, escSettingsSnap, tgSettingsSnap, gwSnap, usersSnap] =
      await Promise.all([
        db.collection('settings').doc('main').get(),
        db.collection('settings').doc('escalation').get(),
        db.collection('settings').doc('telegram').get(),
        db.collection('gateway').doc('status').get(),
        db.collection('users').get(),
      ]);

    const mainData = mainSettingsSnap.data() ?? {};
    const slots: Record<SlotKey, string> = {
      morning: mainData.slots?.morning ?? '08:30',
      noon: mainData.slots?.noon ?? '13:30',
      evening: mainData.slots?.evening ?? '20:30',
    };
    const stopRemindersFromDay: number =
      typeof mainData.stopRemindersFromDay === 'number'
        ? mainData.stopRemindersFromDay
        : 18;

    const escData = escSettingsSnap.data();
    const config: EscalationConfig = escData
      ? {
          enabled: escData.enabled ?? true,
          steps: Array.isArray(escData.steps) && escData.steps.length > 0
            ? escData.steps
            : DEFAULT_ESCALATION_CONFIG.steps,
          callOrder:
            Array.isArray(escData.callOrder) && escData.callOrder.length > 0
              ? escData.callOrder
              : DEFAULT_ESCALATION_CONFIG.callOrder,
          stopAfterMinutes:
            typeof escData.stopAfterMinutes === 'number'
              ? escData.stopAfterMinutes
              : 60,
        }
      : DEFAULT_ESCALATION_CONFIG;

    const users: FamilyMember[] = usersSnap.docs.map((d) => {
      const data = d.data();
      return {
        uid: d.id,
        name: data.name ?? 'Unknown',
        phone: data.phone,
        fcmToken: data.fcmToken,
        telegramUserId: data.telegramUserId,
      };
    });

    let gateway: GatewayState | null = null;
    if (gwSnap.exists) {
      const g = gwSnap.data()!;
      const gwUser = users.find((u) => u.uid === g.uid);
      const lastSeenMs = g.lastSeen?.toMillis ? g.lastSeen.toMillis() : null;
      gateway = {
        uid: g.uid,
        phone: gwUser?.phone,
        lastSeenMs,
        simReady: g.simReady === true,
        offlineWarningSentForLastSeenMs: g.offlineWarningSentForLastSeenMs ?? null,
      };
    }

    // Check rotation docs & escalation docs for today (fail loud if rotation read throws)
    const slotKeys: SlotKey[] = ['morning', 'noon', 'evening'];
    const rotationStatusByKey: Record<string, boolean | null> = {};
    const escalationStateByKey: Record<string, EscalationDocState | undefined> = {};

    await Promise.all(
      slotKeys.map(async (slotKey) => {
        const docKey = `${todayIst}_${slotKey}`;
        try {
          const rotSnap = await db.collection('rotations').doc(docKey).get();
          rotationStatusByKey[docKey] = rotSnap.exists;
        } catch {
          // FAIL LOUD: check failed -> treat as null (not done)
          rotationStatusByKey[docKey] = null;
        }
        const escSnap = await db.collection('escalations').doc(docKey).get();
        if (escSnap.exists) {
          const d = escSnap.data()!;
          escalationStateByKey[docKey] = {
            firedSteps: Array.isArray(d.firedSteps) ? d.firedSteps : [],
            calledNames: Array.isArray(d.calledNames) ? d.calledNames : [],
            smsSentNames: Array.isArray(d.smsSentNames) ? d.smsSentNames : [],
            telegramCount: typeof d.telegramCount === 'number' ? d.telegramCount : 0,
            status: d.status ?? 'active',
          };
        }
      })
    );

    const output = evaluateEscalationTick({
      nowMs,
      batch: {
        id: batchDoc.id,
        placedDate: batchData.placedDate,
        stopRemindersFromDay,
      },
      slots,
      rotationStatusByKey,
      escalationStateByKey,
      config,
      users,
      gateway,
      mutedDate: (mainData.mutedDate ?? batchData.mutedDate ?? null) as string | null,
      mutedUntilDate: (mainData.mutedUntilDate ?? mainData.mutedDate ?? batchData.mutedDate ?? null) as string | null,
    });

    const botToken = telegramBotToken.value();
    const tgChatId: string | undefined = tgSettingsSnap.data()?.chatId;

    // One-time gateway offline Telegram warning (> 3 min offline)
    if (output.shouldSendGatewayOfflineWarning && tgChatId && gateway?.lastSeenMs) {
      try {
        await sendGroupTextMessage({
          botToken,
          chatId: tgChatId,
          text: "⚠️ Geo's gateway phone is offline – calls/SMS will not work.",
        });
        await db.collection('gateway').doc('status').set(
          { offlineWarningSentForLastSeenMs: gateway.lastSeenMs },
          { merge: true }
        );
        await logAudit(db, {
          date: todayIst,
          slotKey: 'system',
          channel: 'telegram',
          targetName: 'Family Group',
          result: 'gateway_offline_warning_sent',
        });
      } catch (err) {
        console.error('Failed to send gateway offline warning', err);
      }
    }

    // Execute planned steps atomically using Firestore transactions
    const allFcmTokens = users
      .map((u) => u.fcmToken)
      .filter((t): t is string => Boolean(t));
    const gwFcmToken = gateway
      ? users.find((u) => u.uid === gateway!.uid)?.fcmToken
      : undefined;

    for (const plan of output.plans) {
      const docKey = `${plan.dateStr}_${plan.slotKey}`;
      const escRef = db.collection('escalations').doc(docKey);

      // Claim this step offset inside a transaction so concurrent invocations never double-fire
      const claimed = await db.runTransaction(async (tx) => {
        const snap = await tx.get(escRef);
        const data = snap.exists ? snap.data()! : {};
        const firedSteps: number[] = Array.isArray(data.firedSteps)
          ? data.firedSteps
          : [];
        const status: string = data.status ?? 'active';

        if (status === 'done' || status === 'missed') return false;
        if (!plan.markMissed && firedSteps.includes(plan.stepOffsetMinutes)) {
          return false;
        }

        const nextFired = plan.markMissed
          ? firedSteps
          : Array.from(new Set([...firedSteps, plan.stepOffsetMinutes]));

        const prevCalled: string[] = Array.isArray(data.calledNames)
          ? data.calledNames
          : [];
        const prevSms: string[] = Array.isArray(data.smsSentNames)
          ? data.smsSentNames
          : [];
        const prevTg: number =
          typeof data.telegramCount === 'number' ? data.telegramCount : 0;

        tx.set(
          escRef,
          {
            date: plan.dateStr,
            slot: plan.slotKey,
            batchId: batchDoc.id,
            firedSteps: nextFired,
            calledNames: Array.from(
              new Set([...prevCalled, ...plan.newlyCalledNames])
            ),
            smsSentNames: Array.from(
              new Set([...prevSms, ...plan.newlySmsNames])
            ),
            telegramCount: prevTg + plan.telegramCountIncrement,
            status: plan.markMissed ? 'missed' : 'active',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        return true;
      });

      if (!claimed) continue;

      for (const reason of plan.skippedReasons) {
        await logAudit(db, {
          date: plan.dateStr,
          slotKey: plan.slotKey,
          channel: 'system',
          targetName: 'Escalation',
          result: 'skipped',
          details: reason,
        });
      }

      for (const cmd of plan.commands) {
        if (cmd.kind === 'fcm_push') {
          try {
            const res = await sendEscalationPushToAll({
              messaging,
              tokens: allFcmTokens,
              dateStr: cmd.dateStr,
              slotKey: cmd.slotKey,
              text: cmd.text,
            });
            await logAudit(db, {
              date: cmd.dateStr,
              slotKey: cmd.slotKey,
              channel: 'fcm',
              targetName: 'All Phones',
              result: `sent (${res.successCount} ok, ${res.failureCount} failed)`,
            });
          } catch (err: any) {
            await logAudit(db, {
              date: cmd.dateStr,
              slotKey: cmd.slotKey,
              channel: 'fcm',
              targetName: 'All Phones',
              result: 'failed',
              details: err?.message,
            });
          }
        } else if (cmd.kind === 'telegram') {
          if (!tgChatId) {
            await logAudit(db, {
              date: cmd.dateStr,
              slotKey: cmd.slotKey,
              channel: 'telegram',
              targetName: 'Family Group',
              result: 'skipped',
              details: 'No Telegram chatId configured',
            });
            continue;
          }
          try {
            const msgRef = await sendGroupEscalationMessage({
              botToken,
              chatId: tgChatId,
              dateStr: cmd.dateStr,
              slotKey: cmd.slotKey,
              text: cmd.text,
              includeRotateButton: cmd.includeRotateButton,
            });
            await escRef.set(
              {
                telegramMessageIds: admin.firestore.FieldValue.arrayUnion(msgRef),
              },
              { merge: true }
            );
            await logAudit(db, {
              date: cmd.dateStr,
              slotKey: cmd.slotKey,
              channel: 'telegram',
              targetName: 'Family Group',
              result: `sent (${cmd.variant})`,
            });
          } catch (err: any) {
            await logAudit(db, {
              date: cmd.dateStr,
              slotKey: cmd.slotKey,
              channel: 'telegram',
              targetName: 'Family Group',
              result: 'failed',
              details: err?.message,
            });
          }
        } else if (cmd.kind === 'gateway_command') {
          const cmdRef = await db.collection('commands').add({
            type: cmd.commandType,
            targetUid: cmd.targetUid,
            targetName: cmd.targetName,
            phone: cmd.phone,
            text: cmd.text,
            date: cmd.dateStr,
            slotKey: cmd.slotKey,
            status: 'pending',
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: admin.firestore.Timestamp.fromMillis(nowMs + 10 * 60_000),
          });
          if (gwFcmToken) {
            await sendWakeGatewayPush({
              messaging,
              gatewayToken: gwFcmToken,
              commandId: cmdRef.id,
              dateStr: cmd.dateStr,
              slotKey: cmd.slotKey,
            }).catch((e) => console.warn('Wake gateway FCM failed:', e));
          }
          await logAudit(db, {
            date: cmd.dateStr,
            slotKey: cmd.slotKey,
            channel: cmd.commandType,
            targetName: cmd.targetName,
            result: 'queued',
            details: `Command ${cmdRef.id}`,
          });
        } else if (cmd.kind === 'mark_missed') {
          await logAudit(db, {
            date: cmd.dateStr,
            slotKey: cmd.slotKey,
            channel: 'system',
            targetName: 'Slot',
            result: 'missed',
            details: `Stopped escalating after +${config.stopAfterMinutes} min`,
          });
        }
      }
    }
  }
);

// ---------------------------------------------------------------------------
// 2. Telegram Webhook (HTTPS, secret-token verified)
// ---------------------------------------------------------------------------
export const telegramWebhook = onRequest(
  {
    region: REGION,
    secrets: [telegramBotToken, telegramWebhookSecret],
  },
  async (req, res) => {
    const secretHeader = req.get('x-telegram-bot-api-secret-token');
    if (!secretHeader || secretHeader !== telegramWebhookSecret.value()) {
      res.status(403).send('Forbidden');
      return;
    }

    const botToken = telegramBotToken.value();
    const update = req.body ?? {};

    try {
      // A. Handle /register command in group chat
      if (update.message && typeof update.message.text === 'string') {
        const text: string = update.message.text.trim();
        const chatId = String(update.message.chat?.id ?? '');
        if (text.startsWith('/register') && chatId) {
          await db.collection('settings').doc('telegram').set(
            {
              chatId,
              lastRegisteredAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
          await sendRegistrationButtons({ botToken, chatId });
          await logAudit(db, {
            date: toIstParts(Date.now()).dateStr,
            slotKey: 'system',
            channel: 'telegram',
            targetName: 'Group',
            result: 'registered',
            details: `chatId=${chatId}`,
          });
        }
        res.status(200).send('OK');
        return;
      }

      // B. Handle inline button callback_query
      if (update.callback_query) {
        const cq = update.callback_query;
        const cqId: string = cq.id;
        const fromId: number | undefined = cq.from?.id;
        const chatId = String(cq.message?.chat?.id ?? '');
        const messageId: number | undefined = cq.message?.message_id;
        const data: string = cq.data ?? '';

        const tgSnap = await db.collection('settings').doc('telegram').get();
        const configuredChatId = tgSnap.data()?.chatId;
        if (!configuredChatId || chatId !== String(configuredChatId)) {
          await answerCallbackQuery({
            botToken,
            callbackQueryId: cqId,
            text: 'Unregistered chat ignored.',
          });
          res.status(200).send('OK');
          return;
        }

        // B1. Link Telegram account ("I'm George / Dolly / Leo / Geo")
        if (data.startsWith('link:') && fromId) {
          const targetName = data.slice('link:'.length);
          const userSnap = await db
            .collection('users')
            .where('name', '==', targetName)
            .limit(1)
            .get();

          if (userSnap.empty) {
            await answerCallbackQuery({
              botToken,
              callbackQueryId: cqId,
              text: `${targetName} hasn't opened the Hatcher app yet.`,
              showAlert: true,
            });
            res.status(200).send('OK');
            return;
          }

          const userDoc = userSnap.docs[0];
          await userDoc.ref.set({ telegramUserId: fromId }, { merge: true });
          await db.collection('settings').doc('telegram').set(
            { [`registeredUsers.${targetName}`]: fromId },
            { merge: true }
          );
          await answerCallbackQuery({
            botToken,
            callbackQueryId: cqId,
            text: `Linked Telegram account as ${targetName} ✔`,
          });
          res.status(200).send('OK');
          return;
        }

        // B2. "Rotated ✔" button
        if (data.startsWith('rotate:') && fromId) {
          const parts = data.split(':');
          if (parts.length !== 3) {
            res.status(200).send('OK');
            return;
          }
          const [, dateStr, slotKey] = parts;

          // Verify sender's Telegram user ID is registered on users/{uid}
          const senderSnap = await db
            .collection('users')
            .where('telegramUserId', '==', fromId)
            .limit(1)
            .get();

          if (senderSnap.empty) {
            await answerCallbackQuery({
              botToken,
              callbackQueryId: cqId,
              text: 'Your Telegram is not linked! Tap your name in /register first.',
              showAlert: true,
            });
            res.status(200).send('OK');
            return;
          }

          const senderDoc = senderSnap.docs[0];
          const doneBy: string = senderDoc.data().name ?? 'Family';
          const doneByUid: string = senderDoc.id;

          const activeBatchSnap = await db
            .collection('batches')
            .where('status', '==', 'active')
            .limit(1)
            .get();
          const batchId = activeBatchSnap.empty ? '' : activeBatchSnap.docs[0].id;

          const rotRef = db.collection('rotations').doc(`${dateStr}_${slotKey}`);
          const created = await db.runTransaction(async (tx) => {
            const snap = await tx.get(rotRef);
            if (snap.exists) return false;
            tx.set(rotRef, {
              date: dateStr,
              slot: slotKey,
              doneBy,
              doneByUid,
              doneAt: admin.firestore.FieldValue.serverTimestamp(),
              batchId,
              source: 'telegram',
            });
            return true;
          });

          if (!created) {
            await answerCallbackQuery({
              botToken,
              callbackQueryId: cqId,
              text: 'Already marked done!',
            });
          } else {
            await answerCallbackQuery({
              botToken,
              callbackQueryId: cqId,
              text: `Marked done by ${doneBy} ✔`,
            });
            if (messageId) {
              await editMessageAsDone({
                botToken,
                chatId,
                messageId,
                doneBy,
                formattedTime: formatIstTime(new Date()),
              }).catch(() => {});
            }
          }
        }
      }

      res.status(200).send('OK');
    } catch (err) {
      console.error('telegramWebhook error', err);
      res.status(200).send('OK'); // Acknowledge to prevent Telegram retry storm
    }
  }
);

// ---------------------------------------------------------------------------
// 3. Cancel-Everywhere Trigger when Rotation Doc is Created
// ---------------------------------------------------------------------------
export const onRotationCreated = onDocumentCreated(
  {
    region: REGION,
    document: 'rotations/{docId}',
    secrets: [telegramBotToken],
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const docId = event.params.docId;
    const dateStr: string = data.date;
    const slotKey: string = data.slot;
    const doneBy: string = data.doneBy ?? 'Family';
    const doneAtDate = data.doneAt?.toDate ? data.doneAt.toDate() : new Date();
    const formattedTime = formatIstTime(doneAtDate);

    // 1. Send FCM cancel_slot data message to all 4 phones
    const usersSnap = await db.collection('users').get();
    const tokens = usersSnap.docs
      .map((d) => d.data().fcmToken)
      .filter((t): t is string => Boolean(t));

    await sendCancelSlotToAll({
      messaging,
      tokens,
      dateStr,
      slotKey,
      doneBy,
    }).catch((e) => console.error('sendCancelSlotToAll error:', e));

    // 2. Cancel all pending gateway commands for this slot
    const pendingCmdsSnap = await db
      .collection('commands')
      .where('date', '==', dateStr)
      .where('slotKey', '==', slotKey)
      .where('status', '==', 'pending')
      .get();

    const batch = db.batch();
    for (const cmdDoc of pendingCmdsSnap.docs) {
      batch.update(cmdDoc.ref, {
        status: 'cancelled',
        reason: `Completed by ${doneBy}`,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    if (!pendingCmdsSnap.empty) {
      await batch.commit();
    }

    // 3. Mark escalation doc done & edit any open Telegram messages
    const escRef = db.collection('escalations').doc(docId);
    const escSnap = await escRef.get();
    if (escSnap.exists) {
      const escData = escSnap.data()!;
      await escRef.set(
        {
          status: 'done',
          doneBy,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      const tgRefs = Array.isArray(escData.telegramMessageIds)
        ? escData.telegramMessageIds
        : [];
      const botToken = telegramBotToken.value();
      for (const ref of tgRefs) {
        if (ref?.chatId && ref?.messageId) {
          await editMessageAsDone({
            botToken,
            chatId: String(ref.chatId),
            messageId: Number(ref.messageId),
            doneBy,
            formattedTime,
          }).catch(() => {});
        }
      }
    }

    await logAudit(db, {
      date: dateStr,
      slotKey,
      channel: 'system',
      targetName: doneBy,
      result: 'cancelled_all_escalations',
      details: `Cancelled ${pendingCmdsSnap.size} pending command(s)`,
    });
  }
);

// ---------------------------------------------------------------------------
// 4. Callable: Send Telegram Test Message (from Settings > Telegram)
// ---------------------------------------------------------------------------
export const sendTelegramTest = onCall(
  {
    region: REGION,
    secrets: [telegramBotToken],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }

    const tgSnap = await db.collection('settings').doc('telegram').get();
    const chatId = tgSnap.data()?.chatId;
    if (!chatId) {
      throw new HttpsError(
        'failed-precondition',
        'No Telegram group chatId configured. Send /register in your group first.'
      );
    }

    await sendGroupTextMessage({
      botToken: telegramBotToken.value(),
      chatId: String(chatId),
      text: '🧪 Hatcher test message — Telegram alerts are connected!',
    });

    return { ok: true };
  }
);
