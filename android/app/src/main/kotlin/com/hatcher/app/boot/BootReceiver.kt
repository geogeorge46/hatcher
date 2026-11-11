package com.hatcher.app.boot

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.hatcher.app.MainActivity
import com.hatcher.app.alarm.AlarmScheduler
import com.hatcher.app.gateway.GatewayService
import com.hatcher.app.notification.NotificationHelper

/**
 * BootReceiver reschedules all alarms after:
 * - Device reboot (BOOT_COMPLETED / QUICKBOOT_POWERON)
 * - App update/reinstall (MY_PACKAGE_REPLACED)
 * - Time or timezone change (TIME_SET, TIMEZONE_CHANGED)
 *
 * Without this, AlarmManager alarms are wiped on reboot.
 * Registered in AndroidManifest.xml with exported="true" so the system
 * can deliver broadcast intents to it.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "Hatcher.BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action !in listOf(
                Intent.ACTION_BOOT_COMPLETED,
                "android.intent.action.QUICKBOOT_POWERON",
                Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_TIMEZONE_CHANGED
            )
        ) {
            Log.d(TAG, "Ignoring unrelated action: $action")
            return
        }

        Log.i(TAG, "Received action=$action — attempting to reschedule alarms")

        // 1. Load saved alarm settings using AlarmScheduler's canonical loader
        val alarmSettings = AlarmScheduler.loadSettings(context)
        if (alarmSettings == null) {
            Log.i(TAG, "No saved alarm settings found — skipping reschedule")
            return
        }

        // 2. Reschedule all alarms via AlarmScheduler
        try {
            AlarmScheduler.scheduleAll(context, alarmSettings)
            Log.i(TAG, "Alarms successfully rescheduled after action=$action")
        } catch (e: Exception) {
            Log.e(TAG, "AlarmScheduler.scheduleAll() threw: ${e.message}", e)
            return
        }

        // 3. Show a status notification so the user knows alarms are active
        try {
            NotificationHelper.showRescheduledNotification(context)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to post reschedule status notification: ${e.message}")
        }

        // 4. Restart GatewayService if Gateway mode is enabled on this phone
        val hatcherPrefs = context.getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        if (hatcherPrefs.getBoolean("gateway_enabled", false)) {
            try {
                val gwIntent = Intent(context, GatewayService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(gwIntent)
                } else {
                    context.startService(gwIntent)
                }
                Log.i(TAG, "Restarted GatewayService after $action")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to restart GatewayService after boot: ${e.message}")
            }
        }
    }
}
