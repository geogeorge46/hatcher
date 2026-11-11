# Hatcher – Egg Incubator Rotation Monitor

> **Malayalam-first** family app for 4 phones. Reminds your family to rotate
> eggs 3 times a day for 21 days. Native Android alarms that survive Doze,
> silent mode, and reboots. Firebase-synced, no server costs.

---

## Table of Contents
1. [Firebase Setup](#1-firebase-setup)
2. [Flutter & Android SDK Setup](#2-flutter--android-sdk-setup)
3. [Build the APK](#3-build-the-apk)
4. [Install on 4 Phones](#4-install-on-4-phones)
5. [Grant Permissions (per phone)](#5-grant-permissions-per-phone)
6. [How to Use](#6-how-to-use)
7. [Permission Reference](#7-permission-reference)
8. [Manual Test Checklist](#8-manual-test-checklist)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Firebase Setup

### 1.1 Create Project
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Click **Add project** → name it `Hatcher` → disable Google Analytics (optional) → Create
3. Wait for provisioning

### 1.2 Add Android App
1. In your project, click **Android** icon (Add app)
2. Android package name: `com.hatcher.app`
3. App nickname: `Hatcher`
4. Click **Register app**
5. **Download `google-services.json`** → copy it to `android/app/google-services.json`
6. Click through the remaining steps (the SDK is already in `build.gradle`)

### 1.3 Enable Anonymous Authentication
1. In Firebase Console → **Authentication** → **Sign-in method**
2. Click **Anonymous** → Enable → Save

### 1.4 Enable Cloud Firestore
1. Firebase Console → **Firestore Database** → **Create database**
2. Choose **Production mode** (we deploy rules separately)
3. Location: **asia-south1** (Mumbai — closest to Kerala)
4. Click **Enable**

### 1.5 Deploy Firestore Security Rules
```bash
# Install Firebase CLI (once)
npm install -g firebase-tools
firebase login
firebase init firestore   # select your project, accept defaults
# Copy the rules file
copy firestore.rules .
firebase deploy --only firestore:rules
```

### 1.6 Enable FCM (Cloud Messaging)
1. Firebase Console → **Cloud Messaging** → already enabled by default
2. No server key needed for Phase 1 (sending comes in Phase 2)

### 1.7 Firestore Indexes (create these manually in Console)
- Collection `rotations`, fields: `date` ASC, `slot` ASC → enable
- Collection `rotations`, fields: `batchId` ASC, `date` DESC → enable

---

## 2. Flutter & Android SDK Setup

### 2.1 Install Flutter (Windows)
```powershell
# Option A — winget
winget install Google.Flutter

# Option B — manual
# 1. Download from https://docs.flutter.dev/get-started/install/windows
# 2. Extract to C:\flutter
# 3. Add C:\flutter\bin to your User PATH
# 4. Restart terminal

flutter --version   # should show 3.x
flutter doctor      # fix any issues shown
```

### 2.2 Android SDK
Flutter installs a bundled SDK. If you need to install it manually:
```powershell
# Android Studio includes the SDK
# Or use sdkmanager:
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"
```

### 2.3 Java / JDK
Flutter requires JDK 17+:
```powershell
winget install Microsoft.OpenJDK.17
# Or download from https://adoptium.net
```

### 2.4 Verify Setup
```powershell
flutter doctor -v
# Should show: Flutter ✓, Android toolchain ✓, Android Studio ✓ (or VS Code)
```

---

## 3. Build the APK

```powershell
cd C:\Users\ASUS\Downloads\Hatcher

# First-time setup
flutter pub get

# Generate localization files (required before build)
flutter gen-l10n

# Analyze for errors
flutter analyze

# Build release APK (unsigned — fine for sideloading)
flutter build apk --release

# APK location:
# build\app\outputs\flutter-apk\app-release.apk
```

> **Note:** `google-services.json` must be in `android/app/` before building.
> Without it, the build will fail with a Firebase configuration error.

### Download Noto Sans Malayalam Font
Before building, download the font files:
1. Go to https://fonts.google.com/noto/specimen/Noto+Sans+Malayalam
2. Download the font family
3. Copy these files to `fonts/NotoSansMalayalam/`:
   - `NotoSansMalayalam-Regular.ttf`
   - `NotoSansMalayalam-Bold.ttf`

### Add Alarm Sound
1. Find a CC0 bell/rooster sound (e.g., from https://freesound.org, search "rooster CC0")
2. Convert to OGG format: https://cloudconvert.com/mp3-to-ogg
3. Save as `assets/sounds/alarm_sound.ogg`
4. Create the directory: `assets/sounds/`

---

## 4. Install on 4 Phones

### 4.1 Enable Developer Options & USB Debugging
On each phone:
1. Settings → About phone → tap **Build number** 7 times
2. Settings → Developer options → enable **USB debugging**

### 4.2 Install via ADB
```powershell
# Connect phone via USB, accept "Allow USB debugging" on phone

# Install APK
adb install build\app\outputs\flutter-apk\app-release.apk

# If multiple devices connected:
adb devices                    # find device ID
adb -s <device-id> install app-release.apk
```

### 4.3 Install via File Transfer (no USB cable needed)
1. Copy `app-release.apk` to phone via WhatsApp, Google Drive, or USB
2. On phone: Settings → Security → **Allow installation from unknown sources**
   (or allow for Files / WhatsApp specifically)
3. Open the APK file → Install

### 4.4 Enable "Unknown Sources" per Phone
| Phone brand | Path |
|-------------|------|
| Samsung | Settings → Biometrics & security → Install unknown apps |
| Xiaomi/Redmi | Settings → Privacy → Special app access → Install unknown apps |
| OnePlus | Settings → Security → Install from unknown sources |
| Realme/Oppo | Settings → Additional settings → Install apps from external sources |

---

## 5. Grant Permissions (per phone)

**Open the app → Settings → Setup Checklist** to see all permissions with direct links.
Or grant manually:

### 5.1 POST_NOTIFICATIONS (Android 13+)
- The app will request this on first launch
- Or: Settings → Apps → Hatcher → Notifications → Allow

### 5.2 Schedule Exact Alarms (Android 12+)
- Settings → Apps → Special app access → **Alarms & reminders** → Hatcher → Allow
- **Why critical:** Without this, `AlarmManager.setAlarmClock()` cannot guarantee exact timing

### 5.3 Full-Screen Intent (Android 14+, sideloaded apps)
- Settings → Apps → Special app access → **Display over other apps** (or search "full screen")
- Or: Settings → Notifications → Hatcher → Allow full screen
- **Why critical:** Without this, the alarm screen won't show over the lock screen

### 5.4 Do Not Disturb Access
- Settings → Apps → Special app access → **Do Not Disturb** → Hatcher → Allow
- **Why critical:** Without this, the alarm channel cannot bypass DND/Silent mode

### 5.5 Battery Unrestricted
- Settings → Apps → Hatcher → Battery → **Unrestricted**
  (not "Optimized" or "Restricted")
- **Why critical:** Android kills background services on optimized battery mode

### 5.6 Autostart (Xiaomi/Redmi/MIUI)
- Security app → Manage apps → Hatcher → **Autostart** → Enable
- Or: Settings → Apps → Hatcher → Other permissions → Start in background → Allow

### 5.7 Autostart (Oppo/Realme/ColorOS)
- Phone Manager → Privacy Permissions → Startup manager → Hatcher → Allow

### 5.8 Autostart (Vivo/OriginOS)
- iManager → App Manager → Hatcher → Allow auto-launch

---

## 6. How to Use

### First Launch
1. Pick language (Malayalam/English)
2. Pick your name from the list (George, Dolly, Leo, Geo)

### Starting an Incubation Batch
1. Home → tap **New Batch** (➕ button)
2. Set the date you placed the eggs (defaults to today)
3. Enter egg count
4. Tap **Start Batch**

### Daily Use
- Home screen shows the 3 rotation slots with their status
- Tap **"തിരിച്ചു ✔"** / **"Rotated ✔"** when you rotate the eggs
- All 4 phones update instantly
- If you rotated by mistake, tap **Undo** within 10 minutes

### Alarms
- 3 alarms per day: 8:30 AM, 1:30 PM, 8:30 PM
- If your screen is ON and unlocked: a banner appears at the top (small beep)
- If your screen is OFF or LOCKED: full-screen alarm (overrides lock screen)
- **Silent/Vibrate/DND mode:** alarm still plays (uses system Alarm audio stream)
- Tap "Rotated ✔" from any alarm/notification to log without opening the app
- Tap "Snooze" to be reminded again in 10 minutes

### Day 18 (Lockdown)
- From day 18 (default), egg rotation should STOP
- Alarms stop automatically
- A banner shows "ഇന്ന് മുതൽ തിരിക്കേണ്ട" / "No rotation needed from today"
- Raise humidity in the incubator now!
- You can still log a rotation manually if needed (shows a "Log anyway?" confirmation)

### Candling Days
- Day 7 and Day 14: a notification reminds you to candle the eggs
- Candle the eggs by holding them up to a flashlight in a dark room

---

## 7. Permission Reference

| Permission | Why needed |
|------------|-----------|
| `POST_NOTIFICATIONS` | Show alarm notifications and rotation reminders |
| `SCHEDULE_EXACT_ALARM` | Fire alarms at exact times (8:30 AM, 1:30 PM, 8:30 PM) |
| `USE_FULL_SCREEN_INTENT` | Show alarm over the lock screen |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_ALARM` | Keep alarm service running |
| `WAKE_LOCK` | Wake the phone's screen for the alarm |
| `RECEIVE_BOOT_COMPLETED` | Reschedule alarms after phone restarts |
| `ACCESS_NOTIFICATION_POLICY` | Ring through Do Not Disturb / Silent mode |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Prevent Android from killing the alarm service |
| `VIBRATE` | Vibrate with the alarm |
| `INTERNET` + `ACCESS_NETWORK_STATE` | Sync with Firebase |

---

## 8. Manual Test Checklist

Run this checklist after installing on all 4 phones:

### Basic Functionality
- [ ] Language picker shows Malayalam and English
- [ ] Name picker shows all 4 names; selection is remembered
- [ ] New Batch: creates batch, shows Day 1 / 21 on home screen
- [ ] "Rotated ✔" button logs rotation on current phone
- [ ] Other 3 phones update within 5 seconds (Firestore live sync)
- [ ] History screen shows the rotation with correct name and time
- [ ] Undo works within 10 minutes; shows confirmation dialog

### Alarm Scenarios
- [ ] **Phone in use (screen on, unlocked):** At alarm time, heads-up banner appears at top; small beep only; no full-screen takeover
- [ ] **Phone locked / screen off:** At alarm time, screen turns on, full AlarmActivity appears over lock screen; loud alarm sound
- [ ] **Silent mode / Vibrate:** Alarm still plays through Alarm audio stream
- [ ] **DND (Do Not Disturb):** Alarm plays (requires DND permission granted)
- [ ] **Snooze:** Tap Snooze; alarm repeats in 10 minutes
- [ ] **Rotated from notification:** Tap "Rotated ✔" in the notification shade without opening the app; logs correctly
- [ ] **Repeat alarm:** If not done, alarm repeats every 10 minutes; stops when logged

### Reliability
- [ ] **Reboot:** Turn phone off and on; alarms still fire at correct times after reboot
- [ ] **Airplane mode:** Rotation logged while offline; syncs to Firestore when internet returns
- [ ] **Two phones tap "Rotated" simultaneously:** Only ONE rotation logged (first-tap-wins); second phone sees "already done" silently

### Day Transitions
- [ ] **Day 17:** 3 alarms scheduled normally; home shows day 17/21
- [ ] **Day 18:** No morning/noon/evening alarms; lockdown banner shows; "Log anyway?" appears if button tapped
- [ ] **Day 18 notification:** At midnight (or when day changes), one-time "raise humidity" notification fires
- [ ] **Day 7 / 14:** Candling notification appears on that morning
- [ ] **Day 21:** Hatch day notification fires; "Rotated" button still visible and functional

### Edge Cases
- [ ] **Multiple active batches:** App prevents second batch from being created while one is active
- [ ] **End batch:** "End Batch" button works; home shows "No active batch" afterwards
- [ ] **History filter:** Filtering by batch shows only that batch's rotations
- [ ] **Settings change (slot times):** Changing slot time updates home cards and reschedules alarms
- [ ] **Language switch:** Changing language in Settings updates the entire app immediately

---

## 9. Troubleshooting

| Problem | Fix |
|---------|-----|
| Alarm doesn't fire after reboot | Grant Autostart permission (Xiaomi/MIUI apps often block this) |
| Alarm fires but no sound | Grant DND Access; check Battery → set to Unrestricted |
| Alarm doesn't show over lock screen | Grant Full-Screen Intent permission (Android 14+) |
| Other phones don't update | Check internet connection; Firestore offline cache shows last-known state |
| "No active batch" on fresh install | Go to New Batch and create one |
| Build fails: "google-services.json not found" | Download from Firebase Console and place in `android/app/` |
| `flutter analyze` shows errors | Run `flutter pub get` first; ensure Dart SDK ≥ 3.3 |
| Alarms stop firing after a few days | Phone battery optimization is killing the app; set Battery to Unrestricted |
| App crashes on startup | Check logcat: `adb logcat -s Flutter` |

---

## 10. Phase 2 Setup (Escalation: Telegram, Push, Calls & SMS)

See [functions/DEPLOY.md](functions/DEPLOY.md) for full instructions on:
- Upgrading to the Firebase **Blaze** plan + setting a monthly budget alert
- Storing `TELEGRAM_BOT_TOKEN` and `TELEGRAM_WEBHOOK_SECRET` in Firebase Secret Manager
- Deploying `escalationTick`, `telegramWebhook`, `onRotationCreated`, and `sendTelegramTest`
- Running `setWebhook` and `/register` in your Telegram group

### Phase 2 Manual Test Checklist
- [ ] **Telegram Rotated button:** Wait +10 min (or test `/register`), tap `"Rotated ✔"` in Telegram → message edits to `"✔ Done by <Name>, <Time>"`, local alarms/notifications cancel on all 4 phones, and pending gateway commands mark `"cancelled"`.
- [ ] **Done from App stops escalation:** Mark a slot done in the Flutter app at +15 min → verify `+20m`, `+30m`, `+45m` escalations never fire and pending commands cancel.
- [ ] **Gateway Calls & SMS:** Let a slot pass +20/+30 min (or use **Settings → Gateway Mode → Test Call / Test SMS**) → Geo's phone dials George/Dolly via selected SIM, hangs up after 40s if unanswered, and sends SMS at +30m.
- [ ] **Gateway Offline Warning:** Stop Gateway mode or turn off Wi-Fi/data on Geo's phone for >3 minutes → Home screen shows red `"Gateway offline"` chip, Telegram group receives `"Geo's gateway phone is offline – calls/SMS will not work"`, and missed call steps skip cleanly with a Telegram notice.
- [ ] **Day 18+ Lockdown:** Set batch day to 18+ → verify zero escalations fire and no calls/SMS/Telegram alerts are sent.
- [ ] **Concurrent Done:** Tap `"Rotated ✔"` in Telegram and on a phone simultaneously → only 1 `rotations/{date_slot}` document exists (first tap wins).
- [ ] **Invalid Phone Validation:** Enter `9876543210` (missing `+91`) in **Settings → Phone Numbers** → clear E.164 validation error shown without crashing.

---

*Built with Flutter + Firebase + Riverpod + Cloud Functions (2nd gen).*
