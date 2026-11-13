package com.hatcher.app.fcm

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.hatcher.app.MainActivity
import com.hatcher.app.alarm.AlarmService
import com.hatcher.app.gateway.GatewayService
import com.hatcher.app.notification.NotificationHelper

/**
 * HatcherFirebaseMessagingService handles high-priority FCM data messages in the
 * background — even when the Flutter engine is completely terminated.
 *
 * Supported data actions:
 * - "cancel_slot": marks slot done locally, stops ringing AlarmService, and
 *   dismisses alarm notifications when another phone or Telegram marks a slot done.
 * - "wake_gateway": wakes Geo's phone from Doze and ensures GatewayService is active
 *   to process a pending call/SMS command immediately.
 * - "escalate_notice": displays an urgent reminder notification if not handled by OS.
 */
class HatcherFirebaseMessagingService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "Hatcher.FCMService"
        private const val NOTIF_ID_ESCALATE = 3001
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.i(TAG, "FCM token refreshed")

        val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putString("fcm_token", token).apply()

        val uid = FirebaseAuth.getInstance().currentUser?.uid
            ?: prefs.getString("user_uid", null)
        if (!uid.isNullOrBlank()) {
            FirebaseFirestore.getInstance()
                .collection("users")
                .document(uid)
                .set(mapOf("fcmToken" to token), SetOptions.merge())
                .addOnFailureListener { e ->
                    Log.w(TAG, "Failed to update refreshed FCM token: ${e.message}")
                }
        }
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        val data = remoteMessage.data
        val action = data["action"] ?: return
        Log.i(TAG, "FCM data message received: action=$action data=$data")

        when (action) {
            "cancel_slot" -> handleCancelSlot(data)
            "wake_gateway" -> handleWakeGateway()
            "escalate_notice" -> handleEscalateNotice(data)
        }
    }

    private fun handleCancelSlot(data: Map<String, String>) {
        val date = data["date"] ?: return
        val slotKey = data["slotKey"] ?: return
        val doneBy = data["doneBy"] ?: "Family"

        Log.i(TAG, "Cancelling local alarms/notifications for $date $slotKey (done by $doneBy)")

        // 1. Update local SharedPreferences mirror so AlarmService stays silent
        val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putBoolean("done_${date}_${slotKey}", true).apply()

        // 2. Broadcast to stop AlarmService if currently ringing
        val stopIntent = Intent(AlarmService.ACTION_ROTATION_DONE).apply {
            setPackage(packageName)
            putExtra("slotKey", slotKey)
            putExtra("date", date)
        }
        sendBroadcast(stopIntent)

        // 3. Cancel active alarm notifications
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(AlarmService.FOREGROUND_NOTIFICATION_ID)
        nm.cancel(AlarmService.FOREGROUND_NOTIFICATION_ID + 1)
    }

    private fun handleWakeGateway() {
        val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        val isGatewayEnabled = prefs.getBoolean("gateway_enabled", false)
        if (!isGatewayEnabled) {
            Log.d(TAG, "Received wake_gateway, but gateway mode is disabled on this phone")
            return
        }

        Log.i(TAG, "Waking GatewayService from FCM high-priority ping")
        val serviceIntent = Intent(this, GatewayService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start GatewayService from FCM", e)
        }
    }

    private fun handleEscalateNotice(data: Map<String, String>) {
        val date = data["date"] ?: return
        val slotKey = data["slotKey"] ?: return
        val symbol = data["symbol"] ?: NotificationHelper.getSlotSymbol(slotKey)
        val text = data["text"] ?: "മുട്ട തിരിക്കാൻ സമയമായി – ഇപ്പോൾ $symbol വെക്കണം"

        // Do not show if slot is already marked done locally or muted
        val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        val mutedUntil = prefs.getString("muted_until_date", null) ?: prefs.getString("muted_date", null)
        if (!mutedUntil.isNullOrBlank() && date <= mutedUntil) {
            Log.i(TAG, "Push escalation notice muted for $date (muted until $mutedUntil)")
            return
        }
        if (prefs.getBoolean("done_${date}_${slotKey}", false)) {
            return
        }

        NotificationHelper.createChannels(this)
        val notif = NotificationCompat.Builder(this, NotificationHelper.CHANNEL_ALARM)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Hatcher ($symbol) — Escalation")
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .build()

        try {
            NotificationManagerCompat.from(this).notify(NOTIF_ID_ESCALATE, notif)
        } catch (se: SecurityException) {
            Log.w(TAG, "Missing POST_NOTIFICATIONS permission", se)
        }
    }
}
