package com.hatcher.app.alarm

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * SnoozeReceiver handles "Snooze" actions pressed from the notification shade
 * without requiring the full app or activity to open.
 */
class SnoozeReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SnoozeReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val slotKey = intent.getStringExtra("slotKey") ?: "unknown"
        val date = intent.getStringExtra("date") ?: ""
        val snoozeMinutes = intent.getIntExtra("snoozeMinutes", 10)

        Log.i(TAG, "Snoozing alarm for $slotKey ($date) for $snoozeMinutes minutes")

        // 1. Tell AlarmService to stop ringing right now
        val stopIntent = Intent(AlarmService.ACTION_STOP_ALARM).apply {
            setPackage(context.packageName)
        }
        context.sendBroadcast(stopIntent)

        // 2. Dismiss notifications immediately
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(AlarmService.FOREGROUND_NOTIFICATION_ID)
        notificationManager.cancel(AlarmService.FOREGROUND_NOTIFICATION_ID + 1)

        // 3. Schedule the snoozed alarm trigger
        val triggerAtMillis = System.currentTimeMillis() + (snoozeMinutes * 60_000L)
        val requestCode = (slotKey + "_snooze").hashCode()

        try {
            AlarmScheduler.scheduleAlarm(
                context = context,
                triggerAtMillis = triggerAtMillis,
                slotKey = slotKey,
                date = date,
                type = "rotation",
                requestCode = requestCode
            )
            Log.i(TAG, "Snooze alarm scheduled successfully for $triggerAtMillis")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule snoozed alarm", e)
        }
    }
}
