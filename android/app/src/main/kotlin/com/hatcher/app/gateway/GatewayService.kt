package com.hatcher.app.gateway

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.SetOptions
import com.hatcher.app.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import java.util.Date

/**
 * GatewayService — Foreground service running on Geo's phone when "Gateway mode"
 * is enabled.
 *
 * Responsibilities:
 * 1. Sends a heartbeat to `gateway/status` every 60 seconds (battery, charging,
 *    Wi-Fi, SIM readiness, lastSeen).
 * 2. Listens to Firestore `commands` where `status == "pending"` in real time.
 * 3. Claims each command atomically via Firestore transaction (`pending -> claimed`)
 *    so duplicate deliveries never double-call/double-SMS.
 * 4. Re-checks `rotations/{date}_{slotKey}` before dialing or texting — if already
 *    done, marks command `cancelled`.
 * 5. Executes phone calls via TelecomManager (supporting dual-SIM selection) with a
 *    40-second ring timeout + `TelecomManager.endCall()` (`ANSWER_PHONE_CALLS`)
 *    to avoid leaving calls ringing endlessly or hitting voicemail loops.
 * 6. Executes SMS via SmsManager for the configured SIM subscription.
 * 7. Never calls its own phone number / UID (self-call guard).
 */
class GatewayService : Service() {

    companion object {
        private const val TAG = "Hatcher.GatewayService"
        private const val CHANNEL_ID = "hatcher_gateway_channel"
        private const val FOREGROUND_ID = 401
        private const val HEARTBEAT_INTERVAL_MS = 60_000L
        private const val CALL_RING_TIMEOUT_MS = 40_000L
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val db by lazy { FirebaseFirestore.getInstance() }
    private var commandsListener: ListenerRegistration? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val heartbeatRunnable = object : Runnable {
        override fun run() {
            scope.launch { writeHeartbeat() }
            mainHandler.postDelayed(this, HEARTBEAT_INTERVAL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("gateway_enabled", false)) {
            Log.i(TAG, "Gateway mode is disabled — stopping GatewayService")
            stopSelf()
            return START_NOT_STICKY
        }

        val notif = buildForegroundNotification()
        ServiceCompat.startForeground(
            this,
            FOREGROUND_ID,
            notif,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            } else {
                0
            }
        )

        startHeartbeat()
        startCommandListener()
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        mainHandler.removeCallbacks(heartbeatRunnable)
        commandsListener?.remove()
        commandsListener = null
        scope.cancel()
    }

    // -------------------------------------------------------------------------
    // Heartbeat
    // -------------------------------------------------------------------------

    private fun startHeartbeat() {
        mainHandler.removeCallbacks(heartbeatRunnable)
        mainHandler.post(heartbeatRunnable)
    }

    private suspend fun writeHeartbeat() {
        try {
            val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
            val uid = FirebaseAuth.getInstance().currentUser?.uid
                ?: prefs.getString("user_uid", null)
                ?: return

            val (battery, charging) = readBatteryState()
            val wifi = isWifiConnected()
            val simReady = isSimReady()
            val selectedSimSlot = prefs.getInt("gateway_sim_slot", 0)

            val payload = hashMapOf(
                "uid" to uid,
                "deviceName" to "${Build.MANUFACTURER} ${Build.MODEL}",
                "lastSeen" to Timestamp.now(),
                "battery" to battery,
                "charging" to charging,
                "wifi" to wifi,
                "simReady" to simReady,
                "selectedSimSlot" to selectedSimSlot
            )
            db.collection("gateway").document("status")
                .set(payload, SetOptions.merge())
                .await()
            Log.d(TAG, "Heartbeat written: battery=$battery% charging=$charging simReady=$simReady")
        } catch (e: Exception) {
            Log.w(TAG, "Heartbeat error: ${e.message}")
        }
    }

    // -------------------------------------------------------------------------
    // Command Listener & Execution
    // -------------------------------------------------------------------------

    private fun startCommandListener() {
        if (commandsListener != null) return

        commandsListener = db.collection("commands")
            .whereEqualTo("status", "pending")
            .addSnapshotListener { snapshots, error ->
                if (error != null) {
                    Log.w(TAG, "Command listener error: ${error.message}")
                    return@addSnapshotListener
                }
                if (snapshots == null || snapshots.isEmpty) return@addSnapshotListener

                for (doc in snapshots.documents) {
                    scope.launch { processPendingCommand(doc.id) }
                }
            }
    }

    private suspend fun processPendingCommand(commandId: String) {
        val cmdRef = db.collection("commands").document(commandId)
        val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        val myUid = FirebaseAuth.getInstance().currentUser?.uid
            ?: prefs.getString("user_uid", "") ?: ""

        // 1. Atomically claim command: pending -> claimed
        val claimedData: Map<String, Any>? = try {
            db.runTransaction { tx ->
                val snap = tx.get(cmdRef)
                if (!snap.exists()) return@runTransaction null
                val status = snap.getString("status")
                if (status != "pending") return@runTransaction null

                val expiresAt = snap.getTimestamp("expiresAt")
                if (expiresAt != null && expiresAt.toDate().before(Date())) {
                    tx.update(cmdRef, mapOf(
                        "status" to "failed",
                        "reason" to "Command expired before execution",
                        "completedAt" to Timestamp.now()
                    ))
                    return@runTransaction null
                }

                tx.update(cmdRef, mapOf(
                    "status" to "claimed",
                    "claimedBy" to myUid,
                    "claimedAt" to Timestamp.now()
                ))
                snap.data
            }.await()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to claim command $commandId: ${e.message}")
            null
        }

        if (claimedData == null) return

        val type = claimedData["type"] as? String ?: ""
        val phone = claimedData["phone"] as? String ?: ""
        val text = claimedData["text"] as? String ?: ""
        val date = claimedData["date"] as? String ?: ""
        val slotKey = claimedData["slotKey"] as? String ?: ""
        val targetUid = claimedData["targetUid"] as? String ?: ""
        val targetName = claimedData["targetName"] as? String ?: "Unknown"

        // 2. Re-check if the slot is STILL not done or muted before placing call/SMS
        val mutedUntil = prefs.getString("muted_until_date", null) ?: prefs.getString("muted_date", null)
        if (!mutedUntil.isNullOrBlank() && date <= mutedUntil) {
            cmdRef.update(mapOf(
                "status" to "cancelled",
                "reason" to "Notifications and calls muted until $mutedUntil by owner",
                "completedAt" to Timestamp.now()
            )).await()
            writeAuditLog(date, slotKey, type, targetName, "cancelled: muted until $mutedUntil by owner")
            return
        }

        if (date.isNotBlank() && slotKey.isNotBlank()) {
            try {
                val rotSnap = db.collection("rotations").document("${date}_${slotKey}").get().await()
                if (rotSnap.exists()) {
                    cmdRef.update(mapOf(
                        "status" to "cancelled",
                        "reason" to "Slot already marked done before execution",
                        "completedAt" to Timestamp.now()
                    )).await()
                    return
                }
            } catch (e: Exception) {
                // Fail loud: if check fails, proceed to alert!
                Log.w(TAG, "Rotation re-check failed for $date $slotKey — failing loud", e)
            }
        }

        // 3. Acquire temporary WakeLock while executing
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "hatcher:gw_$commandId")
        wakeLock.acquire(55_000L)

        try {
            if (type == "call") {
                // Self-call guard: gateway can NEVER call itself
                if (targetUid == myUid) {
                    markCommandResult(cmdRef, "failed", "Skipped self-call to gateway phone")
                    return
                }
                executeCallWithTimeout(cmdRef, phone, targetName, date, slotKey)
            } else if (type == "sms") {
                executeSms(cmdRef, phone, text, targetName, date, slotKey)
            } else {
                markCommandResult(cmdRef, "failed", "Unknown command type: $type")
            }
        } finally {
            if (wakeLock.isHeld) wakeLock.release()
        }
    }

    private suspend fun executeCallWithTimeout(
        cmdRef: com.google.firebase.firestore.DocumentReference,
        phone: String,
        targetName: String,
        date: String,
        slotKey: String
    ) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            markCommandResult(cmdRef, "failed", "CALL_PHONE permission missing")
            return
        }

        try {
            val telecom = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            val uri = Uri.fromParts("tel", phone, null)
            val extras = Bundle()

            val chosenAccount = findSelectedPhoneAccount(telecom)
            if (chosenAccount != null) {
                extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, chosenAccount)
            }

            try {
                telecom.placeCall(uri, extras)
                Log.i(TAG, "Placed call via telecom to $targetName ($phone)")
            } catch (te: Exception) {
                Log.w(TAG, "telecom.placeCall failed, using Intent.ACTION_CALL fallback: ${te.message}")
                val callIntent = Intent(Intent.ACTION_CALL, uri).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    if (chosenAccount != null) {
                        putExtra(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, chosenAccount)
                    }
                }
                startActivity(callIntent)
                Log.i(TAG, "Placed call via ACTION_CALL to $targetName ($phone)")
            }

            // Monitor TelephonyManager call state for up to 40 seconds
            val telephony = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            val startMs = System.currentTimeMillis()
            var callWasActive = false
            var endedEarly = false

            // Wait briefly for call state to transition from IDLE -> OFFHOOK
            delay(2_500L)

            while (System.currentTimeMillis() - startMs < CALL_RING_TIMEOUT_MS) {
                @Suppress("DEPRECATION")
                val state = if (ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.READ_PHONE_STATE
                    ) == PackageManager.PERMISSION_GRANTED
                ) {
                    telephony.callState
                } else {
                    TelephonyManager.CALL_STATE_OFFHOOK
                }

                if (state == TelephonyManager.CALL_STATE_OFFHOOK) {
                    callWasActive = true
                } else if (callWasActive && state == TelephonyManager.CALL_STATE_IDLE) {
                    endedEarly = true
                    break
                }
                delay(1_000L)
            }

            // If 40s elapsed and call didn't finish naturally, hang up cleanly
            if (!endedEarly && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                if (ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.ANSWER_PHONE_CALLS
                    ) == PackageManager.PERMISSION_GRANTED
                ) {
                    @Suppress("DEPRECATION")
                    telecom.endCall()
                }
            }

            val resultLabel = if (endedEarly) "completed/rejected" else "no answer (40s timeout)"
            markCommandResult(cmdRef, "done", resultLabel)
            writeAuditLog(date, slotKey, "call", targetName, resultLabel)
        } catch (e: Exception) {
            Log.e(TAG, "Call execution error for $phone", e)
            markCommandResult(cmdRef, "failed", e.message ?: "Call failed")
            writeAuditLog(date, slotKey, "call", targetName, "failed: ${e.message}")
        }
    }

    private suspend fun executeSms(
        cmdRef: com.google.firebase.firestore.DocumentReference,
        phone: String,
        text: String,
        targetName: String,
        date: String,
        slotKey: String
    ) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            markCommandResult(cmdRef, "failed", "SEND_SMS permission missing")
            return
        }

        try {
            val smsManager = getConfiguredSmsManager()
            val parts = smsManager.divideMessage(text)
            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
            } else {
                smsManager.sendTextMessage(phone, null, text, null, null)
            }
            Log.i(TAG, "SMS sent to $targetName ($phone)")
            markCommandResult(cmdRef, "done", "SMS sent")
            writeAuditLog(date, slotKey, "sms", targetName, "sent")
        } catch (e: Exception) {
            Log.e(TAG, "SMS error for $phone", e)
            markCommandResult(cmdRef, "failed", e.message ?: "SMS failed")
            writeAuditLog(date, slotKey, "sms", targetName, "failed: ${e.message}")
        }
    }

    private suspend fun markCommandResult(
        cmdRef: com.google.firebase.firestore.DocumentReference,
        status: String,
        reason: String
    ) {
        try {
            cmdRef.update(
                mapOf(
                    "status" to status,
                    "reason" to reason,
                    "completedAt" to Timestamp.now()
                )
            ).await()
        } catch (e: Exception) {
            Log.w(TAG, "Failed updating command status: ${e.message}")
        }
    }

    private suspend fun writeAuditLog(
        date: String,
        slotKey: String,
        channel: String,
        targetName: String,
        result: String
    ) {
        val nowMs = System.currentTimeMillis()
        val thirtyDaysMs = 30L * 24 * 60 * 60 * 1000
        try {
            db.collection("auditLogs").add(
                mapOf(
                    "timestamp" to Timestamp.now(),
                    "createdAtMs" to nowMs,
                    "expiresAt" to Timestamp(Date(nowMs + thirtyDaysMs)),
                    "date" to date,
                    "slotKey" to slotKey,
                    "channel" to channel,
                    "targetName" to targetName,
                    "result" to result,
                    "details" to "Executed by GatewayService"
                )
            ).await()
        } catch (_: Exception) {}
    }

    // -------------------------------------------------------------------------
    // SIM, Battery, Connectivity helpers
    // -------------------------------------------------------------------------

    private fun findSelectedPhoneAccount(telecom: TelecomManager): PhoneAccountHandle? {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            return null
        }
        val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        val simSlot = prefs.getInt("gateway_sim_slot", 0)
        val accounts = telecom.callCapablePhoneAccounts
        return accounts.getOrNull(simSlot) ?: accounts.firstOrNull()
    }

    @Suppress("DEPRECATION")
    private fun getConfiguredSmsManager(): SmsManager {
        val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        val simSlot = prefs.getInt("gateway_sim_slot", 0)

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
            == PackageManager.PERMISSION_GRANTED
        ) {
            val subMgr = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            val activeSubs = subMgr.activeSubscriptionInfoList
            val subInfo = activeSubs?.firstOrNull { it.simSlotIndex == simSlot }
                ?: activeSubs?.firstOrNull()
            if (subInfo != null) {
                return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    getSystemService(SmsManager::class.java).createForSubscriptionId(subInfo.subscriptionId)
                } else {
                    SmsManager.getSmsManagerForSubscriptionId(subInfo.subscriptionId)
                }
            }
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(SmsManager::class.java)
        } else {
            SmsManager.getDefault()
        }
    }

    private fun readBatteryState(): Pair<Int, Boolean> {
        val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val pct = if (level >= 0 && scale > 0) (level * 100) / scale else -1
        val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
        return Pair(pct, charging)
    }

    private fun isWifiConnected(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }

    private fun isSimReady(): Boolean {
        val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        return tm.simState == TelephonyManager.SIM_STATE_READY
    }

    // -------------------------------------------------------------------------
    // Notification
    // -------------------------------------------------------------------------

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Hatcher Gateway Mode",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps SIM call/SMS alert gateway active"
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_phone_call)
            .setContentTitle("Hatcher Gateway Active")
            .setContentText("Listening for emergency call & SMS escalation commands")
            .setOngoing(true)
            .setContentIntent(pi)
            .build()
    }
}
