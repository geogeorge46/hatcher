package com.hatcher.app.notification

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.hatcher.app.MainActivity
import com.hatcher.app.alarm.AlarmActivity
import com.hatcher.app.alarm.SnoozeReceiver

/**
 * NotificationHelper manages all notification channels and builds notifications
 * for the Hatcher application.
 *
 * Channel strategy:
 * - CHANNEL_ALARM: High importance, ALARM audio stream attribute.
 *   Can bypass Do Not Disturb (DND) when ACCESS_NOTIFICATION_POLICY has been granted.
 * - CHANNEL_NORMAL: Default importance for informational updates (candling, hatch, lockdown).
 * - CHANNEL_SERVICE: Low importance for system resilience notifications (boot reschedule).
 */
object NotificationHelper {

    const val CHANNEL_ALARM = "hatcher_alarm_channel_v2"
    const val CHANNEL_NORMAL = "hatcher_normal_channel"
    const val CHANNEL_SERVICE = "hatcher_service_channel"

    private const val NOTIF_ID_CANDLING = 2001
    private const val NOTIF_ID_HATCH = 2002
    private const val NOTIF_ID_LOCKDOWN = 2003
    private const val NOTIF_ID_RESCHEDULE = 2004

    /**
     * Creates all notification channels. Safe to call idempotently.
     */
    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // 1. Alarm Channel
        val alarmChannel = NotificationChannel(
            CHANNEL_ALARM,
            "Incubator Rotation Alarms",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "High priority alarms for egg rotation schedule"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 500, 250, 500, 250, 1000)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC

            // Set alarm audio attributes
            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_ALARM)
                .build()
            val defaultAlarmUri = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_ALARM)
                ?: android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_RINGTONE)
            setSound(defaultAlarmUri, audioAttributes)

            // Bypass DND
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                setBypassDnd(true)
            }
        }
        notificationManager.createNotificationChannel(alarmChannel)

        // 2. Normal Reminders Channel
        val normalChannel = NotificationChannel(
            CHANNEL_NORMAL,
            "Incubation Reminders",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Candling, hatch day, and humidity reminders"
            enableVibration(true)
        }
        notificationManager.createNotificationChannel(normalChannel)

        // 3. Service Status Channel
        val serviceChannel = NotificationChannel(
            CHANNEL_SERVICE,
            "Service & Recovery",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Boot recovery and background status"
        }
        notificationManager.createNotificationChannel(serviceChannel)
    }

    fun getSlotSymbol(slotKey: String): String {
        return when (slotKey.lowercase()) {
            "morning" -> "|"
            "noon" -> "∆"
            "evening" -> "•"
            else -> "🥚"
        }
    }

    fun getSlotMalayalamName(slotKey: String): String {
        return when (slotKey.lowercase()) {
            "morning" -> "രാവിലെ"
            "noon" -> "ഉച്ചക്ക്"
            "evening" -> "വൈകുന്നേരം"
            else -> slotKey
        }
    }

    /**
     * Builds the persistent, high-priority full-screen alarm notification.
     */
    fun buildAlarmNotification(
        context: Context,
        slotKey: String,
        date: String,
        doneBy: String,
        snoozeMinutes: Int
    ): Notification {
        createChannels(context)

        val symbol = getSlotSymbol(slotKey)
        val malayalamSlot = getSlotMalayalamName(slotKey)
        val title = "മുട്ട തിരിക്കാൻ സമയമായി! ($malayalamSlot $symbol)"
        val message = "ഇപ്പോൾ $symbol വെക്കണം. തിരിച്ച് കഴിഞ്ഞാൽ രേഖപ്പെടുത്തൂ."

        // Full Screen Intent to AlarmActivity
        val fullScreenIntent = Intent(context, AlarmActivity::class.java).apply {
            putExtra("slotKey", slotKey)
            putExtra("date", date)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            context,
            slotKey.hashCode(),
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // "Rotated ✔" Action -> RotateActionReceiver
        val rotatedIntent = Intent(context, RotateActionReceiver::class.java).apply {
            putExtra("slotKey", slotKey)
            putExtra("date", date)
        }
        val rotatedPendingIntent = PendingIntent.getBroadcast(
            context,
            (slotKey + date + "rotated").hashCode(),
            rotatedIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // "Snooze" Action -> SnoozeReceiver
        val snoozeIntent = Intent(context, SnoozeReceiver::class.java).apply {
            putExtra("slotKey", slotKey)
            putExtra("date", date)
            putExtra("snoozeMinutes", snoozeMinutes)
        }
        val snoozePendingIntent = PendingIntent.getBroadcast(
            context,
            (slotKey + date + "snooze").hashCode(),
            snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ALARM)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setContentIntent(fullScreenPendingIntent)
            .addAction(
                android.R.drawable.checkbox_on_background,
                "തിരിച്ചു ✔ / Rotated",
                rotatedPendingIntent
            )
            .addAction(
                android.R.drawable.ic_popup_reminder,
                "സ്നൂസ് / Snooze $snoozeMinutes min",
                snoozePendingIntent
            )

        return builder.build()
    }

    /**
     * Builds a Heads-Up notification for when the phone is actively in use.
     */
    fun buildHeadsUpNotification(
        context: Context,
        slotKey: String,
        date: String,
        snoozeMinutes: Int
    ): Notification {
        createChannels(context)

        val symbol = getSlotSymbol(slotKey)
        val malayalamSlot = getSlotMalayalamName(slotKey)
        val title = "മുട്ട തിരിക്കാൻ സമയമായി! ($malayalamSlot $symbol)"
        val message = "ഇപ്പോൾ $symbol വെക്കണം."

        val openIntent = Intent(context, MainActivity::class.java)
        val openPendingIntent = PendingIntent.getActivity(
            context,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val rotatedIntent = Intent(context, RotateActionReceiver::class.java).apply {
            putExtra("slotKey", slotKey)
            putExtra("date", date)
        }
        val rotatedPendingIntent = PendingIntent.getBroadcast(
            context,
            (slotKey + date + "heads_rotated").hashCode(),
            rotatedIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val snoozeIntent = Intent(context, SnoozeReceiver::class.java).apply {
            putExtra("slotKey", slotKey)
            putExtra("date", date)
            putExtra("snoozeMinutes", snoozeMinutes)
        }
        val snoozePendingIntent = PendingIntent.getBroadcast(
            context,
            (slotKey + date + "heads_snooze").hashCode(),
            snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(context, CHANNEL_ALARM)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(openPendingIntent)
            .addAction(
                android.R.drawable.checkbox_on_background,
                "തിരിച്ചു ✔",
                rotatedPendingIntent
            )
            .addAction(
                android.R.drawable.ic_popup_reminder,
                "സ്നൂസ് ($snoozeMinutes min)",
                snoozePendingIntent
            )
            .build()
    }

    fun showCandlingNotification(context: Context, day: Int) {
        createChannels(context)
        val title = "ദിവസം $day: ക്യാൻഡ്ലിംഗ് ചെയ്യൂ 🥚🔦"
        val message = "ഇരുട്ടുള്ള മുറിയിൽ വെളിച്ചം ഉപയോഗിച്ച് മുട്ടകൾ പരിശോധിക്കാനുള്ള ദിവസമാണ്."

        val openIntent = Intent(context, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            context,
            NOTIF_ID_CANDLING,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notif = NotificationCompat.Builder(context, CHANNEL_NORMAL)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        NotificationManagerCompat.from(context).notify(NOTIF_ID_CANDLING, notif)
    }

    fun showHatchNotification(context: Context) {
        createChannels(context)
        val title = "ഇന്ന് മുട്ടകൾ വിരിയും! 🐣"
        val message = "21 ദിവസത്തെ ഇൻക്യുബേഷൻ പൂർത്തിയായി. കുഞ്ഞുങ്ങൾ പുറത്തു വരുന്നത് നിരീക്ഷിക്കൂ!"

        val openIntent = Intent(context, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            context,
            NOTIF_ID_HATCH,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notif = NotificationCompat.Builder(context, CHANNEL_NORMAL)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        NotificationManagerCompat.from(context).notify(NOTIF_ID_HATCH, notif)
    }

    fun showLockdownNotification(context: Context, day: Int) {
        createChannels(context)
        val title = "ലോക്ക്ഡൗൺ ആരംഭിച്ചു (ദിവസം $day) 🔒"
        val message = "ഇന്ന് മുതൽ മുട്ടകൾ തിരിക്കരുത്! ഇൻക്യുബേറ്ററിലെ ആർദ്രത (Humidity) ഉയർത്തുക 💧."

        val openIntent = Intent(context, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            context,
            NOTIF_ID_LOCKDOWN,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notif = NotificationCompat.Builder(context, CHANNEL_NORMAL)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        NotificationManagerCompat.from(context).notify(NOTIF_ID_LOCKDOWN, notif)
    }

    fun showRescheduledNotification(context: Context) {
        createChannels(context)
        val title = "Hatcher Alarms Active"
        val message = "Egg rotation alarms successfully restored after phone restart."

        val notif = NotificationCompat.Builder(context, CHANNEL_SERVICE)
            .setSmallIcon(android.R.drawable.ic_menu_agenda)
            .setContentTitle(title)
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setAutoCancel(true)
            .build()

        NotificationManagerCompat.from(context).notify(NOTIF_ID_RESCHEDULE, notif)
    }
}
