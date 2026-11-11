# Hatcher Phase 2 — Cloud Functions Deployment & Telegram Setup Guide

## 1. Prerequisites
1. **Firebase Blaze Plan** (Pay-as-you-go):
   - In Firebase Console → bottom-left **Upgrade** → link a billing account.
   - Set a **Budget Alert** (Billing → Budgets & alerts → e.g. ₹100 / $2/month at 50%, 90%, 100%).
   - For 4 phones + 1-minute scheduler, Cloud Functions + Firestore + Secret Manager stay near/within the free tier.
2. **Firebase CLI**:
   ```powershell
   npm install -g firebase-tools
   firebase login
   firebase use hatcher-78950
   ```

## 2. Create Telegram Bot
1. Open Telegram and message `@BotFather`.
2. Send `/newbot`, choose a name (`Hatcher Family`) and username (`hatcher_family_bot`).
3. Copy the **Bot Token** (looks like `123456789:ABCDefGhIJK...`).
4. Disable Group Privacy so the bot sees `/register` in your family group:
   - In `@BotFather`, send `/setprivacy` → select your bot → **Disable**.
5. Create a Telegram group with George, Dolly, Leo, and Geo, and add the bot to the group.

## 3. Store Secrets in Firebase Secret Manager
Generate a random webhook secret (any 32+ alphanumeric string, e.g. `hatcher_wh_sec_9482a7f...`) and save both secrets:

```powershell
cd C:\Users\ASUS\Downloads\Hatcher\functions

firebase functions:secrets:set TELEGRAM_BOT_TOKEN
# Paste your BotFather token when prompted

firebase functions:secrets:set TELEGRAM_WEBHOOK_SECRET
# Paste your random secret string when prompted
```

## 4. Build, Test & Deploy Cloud Functions + Rules
```powershell
cd C:\Users\ASUS\Downloads\Hatcher\functions
npm install
npm test
npm run build

cd ..
firebase deploy --only functions,firestore:rules
```
Note the deployed URL printed for `telegramWebhook`, e.g.:
`https://asia-south1-hatcher-78950.cloudfunctions.net/telegramWebhook`

## 5. Register Telegram Webhook (`setWebhook`)
Run this once in PowerShell (replace `<BOT_TOKEN>`, `<WEBHOOK_URL>`, and `<WEBHOOK_SECRET>`):

```powershell
$BOT_TOKEN = "<BOT_TOKEN>"
$WEBHOOK_URL = "https://asia-south1-hatcher-78950.cloudfunctions.net/telegramWebhook"
$SECRET = "<WEBHOOK_SECRET>"

Invoke-RestMethod -Method Post `
  -Uri "https://api.telegram.org/bot$BOT_TOKEN/setWebhook" `
  -ContentType "application/json" `
  -Body (@{ url = $WEBHOOK_URL; secret_token = $SECRET } | ConvertTo-Json)
```
Expected response: `{"ok":true,"result":true,"description":"Webhook was set"}`.

## 6. Link the Family Group & 4 Users
1. In your Telegram family group, send `/register`.
2. The bot replies with 4 buttons: **I'm George**, **I'm Dolly**, **I'm Leo**, **I'm Geo**.
3. Make sure each person has opened Hatcher on their phone at least once (so `users/{uid}` exists), then each person taps **their own name button** in the Telegram group.
4. Open **Settings → Telegram Bot** in the Hatcher app and tap **Send Test Message** to verify!
