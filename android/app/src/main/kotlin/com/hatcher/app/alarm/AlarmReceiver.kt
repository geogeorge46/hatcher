package com.hatcher.app.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.hatcher.app.MainActivity
import com.hatcher.app.notification.NotificationHelper

/**
 * AlarmReceiver — receives alarm intents from AlarmManager.
 *
 * This BroadcastReceiver is the first code that runs when an alarm fires.
 * It must complete quickly (Android allows ~10 seconds for a BroadcastReceiver
 * before it's considered unresponsive), so we immediately hand off work to
 * AlarmService for anything that takes longer.
 *
 * Intent extras expected:
 *   slotKey     — "morning" | "noon" | "evening" | "candling" | "hatch" | "lockdown"
 *   date        — "yyyy-MM-dd"
 *   type        — "rotation" | "candling" | "hatch" | "lockdown"
 *   requestCode — Int, the original PendingIntent request code (for scheduleNext)
 *
 * Also handles: BOOT_COMPLETED and MY_PACKAGE_REPLACED to reschedule alarms
 * after a device reboot or app update (declared in AndroidManifest.xml).
 */
class AlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "AlarmReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        // ----------------------------------------------------------------
        // Handle system broadcasts (reboot / app update)
        // ----------------------------------------------------------------
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON", // Xiaomi custom boot action
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                // Reschedule all alarms from persisted settings.
                // This is essential because AlarmManager does NOT survive a device
                // reboot — all registered alarms are lost on power cycle.
                val settings = AlarmScheduler.loadSettings(context)
                if (settings != null) {
                    Log.i(TAG, "Rescheduling alarms after boot/update")
                    AlarmScheduler.scheduleAll(context, settings)
                } else {
                    Log.w(TAG, "No saved alarm settings found after boot")
                }
                return
            }
        }

        // ----------------------------------------------------------------
        // Parse alarm intent extras
        // ----------------------------------------------------------------
        val slotKey = intent.getStringExtra("slotKey") ?: run {
            Log.e(TAG, "Missing slotKey in alarm intent — cannot proceed")
            return
        }
        val date = intent.getStringExtra("date") ?: run {
            Log.e(TAG, "Missing date in alarm intent — cannot proceed")
            return
        }
        val type = intent.getStringExtra("type") ?: "rotation"

        Log.i(TAG, "Alarm fired: type=$type slotKey=$slotKey date=$date")

        // ----------------------------------------------------------------
        // "Fail loud" principle: wrap everything in try/catch.
        // Even if scheduling the next alarm or the slot-done check fails,
        // we still attempt to ring the alarm or show the notification.
        // A missed alarm is worse than an occasional duplicate.
        // ----------------------------------------------------------------
        try {
            handleAlarm(context, intent, slotKey, date, type)
        } catch (e: Exception) {
            Log.e(TAG, "Unhandled error in AlarmReceiver — attempting fallback notification", e)
            // Last resort: show at least a notification so the user knows
            showFallbackNotification(context, slotKey, date, e.message ?: "Unknown error")
        }
    }

    private fun handleAlarm(
        context: Context,
        intent: Intent,
        slotKey: String,
        date: String,
        type: String
    ) {
        // ----------------------------------------------------------------
        // Non-rotation types: show notification and return immediately.
        // These don't need the full alarm ring flow — they're informational.
        // ----------------------------------------------------------------
        when (type) {
            "candling" -> {
                val settings = AlarmScheduler.loadSettings(context)
                val day = settings?.let {
                    AlarmScheduler.dayNumber(it.placedDate, date)
                } ?: 0
                NotificationHelper.showCandlingNotification(context, day)
                return
            }
            "hatch" -> {
                NotificationHelper.showHatchNotification(context)
                return
            }
            "lockdown" -> {
                val settings = AlarmScheduler.loadSettings(context)
                val day = settings?.let {
                    AlarmScheduler.dayNumber(it.placedDate, date)
                } ?: 0
                NotificationHelper.showLockdownNotification(context, day)
                return
            }
        }

        // ----------------------------------------------------------------
        // Rotation alarm flow
        // ----------------------------------------------------------------

        // Step 1: Schedule the NEXT occurrence of this slot (rolling schedule).
        // We do this FIRST, before any checks, so we don't miss the next alarm
        // even if the rest of this handler fails.
        try {
            val settings = AlarmScheduler.loadSettings(context)
            if (settings != null) {
                AlarmScheduler.scheduleNext(context, slotKey, date, settings)
            } else {
                Log.w(TAG, "No saved settings — cannot schedule next alarm")
            }
        } catch (e: Exception) {
            // scheduleNext failure must not block the alarm ring
            Log.e(TAG, "Failed to schedule next alarm", e)
        }

        // Step 2: Check if today is muted (e.g. owner in a function/event)
        // or already marked done in SharedPreferences — skip ringing entirely.
        val prefs = context.getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        val mutedUntil = prefs.getString("muted_until_date", null) ?: prefs.getString("muted_date", null)
        if (!mutedUntil.isNullOrBlank() && date <= mutedUntil) {
            Log.i(TAG, "Date ($date) is muted until $mutedUntil — skipping alarm ring for $slotKey")
            return
        }

        val doneKey = "done_${date}_${slotKey}"
        if (prefs.getBoolean(doneKey, false)) {
            Log.i(TAG, "Slot already done locally — skipping alarm ring for $slotKey $date")
            return
        }

        // Step 3: Start AlarmService as a foreground service.
        // We MUST use startForegroundService() on API 26+ (minSdk = 26 so always).
        // AlarmService must call startForeground() within 5 seconds of starting
        // or Android will ANR and kill it.
        try {
            val serviceIntent = Intent(context, AlarmService::class.java).apply {
                putExtra("slotKey", slotKey)
                putExtra("date", date)
                putExtra("type", type)
                // Default repeat interval: 10 minutes (user can override in app settings)
                putExtra("repeatMinutes", 10)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent) // API < 26 (won't happen given minSdk 26)
            }
            Log.i(TAG, "AlarmService started for $slotKey $date")
        } catch (e: Exception) {
            // Fail loud: if the service won't start (e.g., background start limit
            // exceeded), show a notification so the user is at least notified.
            Log.e(TAG, "Failed to start AlarmService — showing fallback notification", e)
            showFallbackNotification(context, slotKey, date, "Service start failed")
        }
    }

    /**
     * Shows a simple notification as a last-resort fallback if AlarmService
     * cannot be started. This ensures the user is always notified even in
     * extreme battery/resource-constrained situations.
     */
    private fun showFallbackNotification(context: Context, slotKey: String, date: String, reason: String) {
        try {
            // Build a simple heads-up notification without the service flow
            val notification = NotificationHelper.buildHeadsUpNotification(
                context = context,
                slotKey = slotKey,
                date = date,
                snoozeMinutes = 10
            )
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as android.app.NotificationManager
            manager.notify(slotKey.hashCode(), notification)
        } catch (e2: Exception) {
            Log.e(TAG, "Even fallback notification failed: ${e2.message}")
        }
    }
}
