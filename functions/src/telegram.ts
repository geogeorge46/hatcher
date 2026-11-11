import { SlotKey, SLOT_SYMBOLS } from './escalationLogic';

const TELEGRAM_API_BASE = 'https://api.telegram.org';

export interface TelegramMessageRef {
  chatId: string;
  messageId: number;
}

async function callTelegramApi(
  botToken: string,
  method: string,
  body: Record<string, unknown>
): Promise<any> {
  const res = await fetch(`${TELEGRAM_API_BASE}/bot${botToken}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const json = (await res.json()) as { ok: boolean; result?: any; description?: string };
  if (!json.ok) {
    throw new Error(`Telegram ${method} failed: ${json.description ?? res.statusText}`);
  }
  return json.result;
}

/**
 * Sends a rotation prompt or urgent alert to the family group, optionally with
 * an inline "Rotated ✔" button carrying callback_data `rotate:<date>:<slotKey>`.
 */
export async function sendGroupEscalationMessage(params: {
  botToken: string;
  chatId: string;
  dateStr: string;
  slotKey: SlotKey;
  text: string;
  includeRotateButton: boolean;
}): Promise<TelegramMessageRef> {
  const { botToken, chatId, dateStr, slotKey, text, includeRotateButton } = params;
  const payload: Record<string, unknown> = {
    chat_id: chatId,
    text,
  };

  if (includeRotateButton) {
    payload.reply_markup = {
      inline_keyboard: [
        [
          {
            text: `തിരിച്ചു ✔ / Rotated (${SLOT_SYMBOLS[slotKey]})`,
            callback_data: `rotate:${dateStr}:${slotKey}`,
          },
        ],
      ],
    };
  }

  const result = await callTelegramApi(botToken, 'sendMessage', payload);
  return {
    chatId: String(chatId),
    messageId: result.message_id as number,
  };
}

/**
 * Sends a plain text message to the Telegram group (e.g., gateway offline warning or test).
 */
export async function sendGroupTextMessage(params: {
  botToken: string;
  chatId: string;
  text: string;
}): Promise<number> {
  const result = await callTelegramApi(params.botToken, 'sendMessage', {
    chat_id: params.chatId,
    text: params.text,
  });
  return result.message_id as number;
}

/**
 * Sends the identity-linking prompt after /register so each family member
 * taps their own name once.
 */
export async function sendRegistrationButtons(params: {
  botToken: string;
  chatId: string;
}): Promise<void> {
  await callTelegramApi(params.botToken, 'sendMessage', {
    chat_id: params.chatId,
    text:
      '✅ Hatcher group registered!\n' +
      'Each family member should tap their own name below once to link their Telegram account:',
    reply_markup: {
      inline_keyboard: [
        [
          { text: "I'm George", callback_data: 'link:George' },
          { text: "I'm Dolly", callback_data: 'link:Dolly' },
        ],
        [
          { text: "I'm Leo", callback_data: 'link:Leo' },
          { text: "I'm Geo", callback_data: 'link:Geo' },
        ],
      ],
    },
  });
}

/**
 * Edits an existing escalation message in Telegram once the slot is done,
 * removing the inline button so no one taps it again.
 */
export async function editMessageAsDone(params: {
  botToken: string;
  chatId: string;
  messageId: number;
  doneBy: string;
  formattedTime: string;
}): Promise<void> {
  const { botToken, chatId, messageId, doneBy, formattedTime } = params;
  await callTelegramApi(botToken, 'editMessageText', {
    chat_id: chatId,
    message_id: messageId,
    text: `✔ Done by ${doneBy}, ${formattedTime}`,
    reply_markup: { inline_keyboard: [] },
  });
}

/**
 * Answers a Telegram callback query so the loading spinner clears on the user's button.
 */
export async function answerCallbackQuery(params: {
  botToken: string;
  callbackQueryId: string;
  text: string;
  showAlert?: boolean;
}): Promise<void> {
  await callTelegramApi(params.botToken, 'answerCallbackQuery', {
    callback_query_id: params.callbackQueryId,
    text: params.text,
    show_alert: params.showAlert ?? false,
  });
}
