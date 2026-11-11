package com.hatcher.app.alarm

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.hatcher.app.MainActivity
import com.hatcher.app.R
import com.hatcher.app.notification.NotificationHelper
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * AlarmActivity — full-screen UI shown over the lock screen when rotation alarm fires.
 *
 * Configured with:
 * - setShowWhenLocked(true) / setTurnScreenOn(true)
 * - FLAG_KEEP_SCREEN_ON
 * - Full-screen layout with large symbol and direct "Rotated ✔" and "Snooze" buttons.
 */
class AlarmActivity : Activity() {

    companion object {
        private const val TAG = "AlarmActivity"
    }

    private var slotKey: String = "morning"
    private var date: String = ""
    private var snoozeMinutes: Int = 10

    private val timeHandler = Handler(Looper.getMainLooper())
    private lateinit var tvClock: TextView

    private val timeFormat = SimpleDateFormat("hh:mm:ss a", Locale.getDefault()).apply {
        timeZone = TimeZone.getTimeZone("Asia/Kolkata")
    }

    private val updateTimeRunnable = object : Runnable {
        override fun run() {
            if (::tvClock.isInitialized) {
                tvClock.text = timeFormat.format(Date())
            }
            timeHandler.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Ensure activity wakes screen and displays over lock screen
        configureLockScreenVisibility()

        setContentView(R.layout.activity_alarm)

        slotKey = intent.getStringExtra("slotKey") ?: "morning"
        date = intent.getStringExtra("date") ?: ""
        snoozeMinutes = intent.getIntExtra("snoozeMinutes", 10)

        initViews()
    }

    private fun configureLockScreenVisibility() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun initViews() {
        tvClock = findViewById(R.id.tv_clock)
        val tvSymbol: TextView = findViewById(R.id.tv_symbol)
        val tvSlotLabel: TextView = findViewById(R.id.tv_slot_label)
        val tvMessage: TextView = findViewById(R.id.tv_message)
        val btnRotated: Button = findViewById(R.id.btn_rotated)
        val btnSnooze: Button = findViewById(R.id.btn_snooze)

        val symbol = NotificationHelper.getSlotSymbol(slotKey)
        val malayalamSlot = NotificationHelper.getSlotMalayalamName(slotKey)

        tvSymbol.text = symbol
        tvSlotLabel.text = "$malayalamSlot റൊട്ടേഷൻ"
        tvMessage.text = "മുട്ട തിരിക്കാൻ സമയമായി – ഇപ്പോൾ $symbol വെക്കണം"

        btnRotated.setOnClickListener {
            handleRotated()
        }

        btnSnooze.setOnClickListener {
            handleSnooze()
        }

        timeHandler.post(updateTimeRunnable)
    }

    private fun handleRotated() {
        Log.i(TAG, "Rotated button tapped in AlarmActivity for $slotKey $date")

        val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        val doneBy = prefs.getString("user_name", "Unknown") ?: "Unknown"
        val uid = FirebaseAuth.getInstance().currentUser?.uid
            ?: prefs.getString("user_uid", "anonymous") ?: "anonymous"
        val batchId = prefs.getString("current_batch_id", "") ?: ""

        // 1. Mark done in SharedPreferences locally first (immediate UI feedback)
        prefs.edit().putBoolean("done_${date}_${slotKey}", true).apply()

        // 2. Broadcast to stop the AlarmService ring immediately
        val stopIntent = Intent(AlarmService.ACTION_ROTATION_DONE).apply {
            setPackage(packageName)
            putExtra("slotKey", slotKey)
            putExtra("date", date)
        }
        sendBroadcast(stopIntent)

        // 3. Clear foreground alarm notification
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(AlarmService.FOREGROUND_NOTIFICATION_ID)
        notificationManager.cancel(AlarmService.FOREGROUND_NOTIFICATION_ID + 1)

        // 4. Save to Firestore
        val docId = "${date}_${slotKey}"
        val rotationData = hashMapOf(
            "date" to date,
            "slot" to slotKey,
            "doneBy" to doneBy,
            "doneByUid" to uid,
            "batchId" to batchId,
            "doneAt" to Timestamp.now()
        )

        try {
            val db = FirebaseFirestore.getInstance()
            val docRef = db.collection("rotations").document(docId)
            db.runTransaction { tx ->
                val snapshot = tx.get(docRef)
                if (!snapshot.exists()) {
                    tx.set(docRef, rotationData)
                }
                null
            }.addOnFailureListener { e ->
                Log.w(TAG, "Firestore write error: ${e.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error logging rotation to Firestore", e)
        }

        finish()
    }

    private fun handleSnooze() {
        Log.i(TAG, "Snooze button tapped in AlarmActivity for $slotKey $date")

        // 1. Tell AlarmService to stop ringing
        val stopIntent = Intent(AlarmService.ACTION_STOP_ALARM).apply {
            setPackage(packageName)
        }
        sendBroadcast(stopIntent)

        // 2. Dismiss foreground notification
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(AlarmService.FOREGROUND_NOTIFICATION_ID)
        notificationManager.cancel(AlarmService.FOREGROUND_NOTIFICATION_ID + 1)

        // 3. Schedule snoozed alarm trigger
        val triggerAtMillis = System.currentTimeMillis() + (snoozeMinutes * 60_000L)
        val requestCode = (slotKey + "_snooze").hashCode()

        try {
            AlarmScheduler.scheduleAlarm(
                context = this,
                triggerAtMillis = triggerAtMillis,
                slotKey = slotKey,
                date = date,
                type = "rotation",
                requestCode = requestCode
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error scheduling snooze", e)
        }

        finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Back press triggers Snooze rather than dismissing without reminder
        handleSnooze()
    }

    override fun onDestroy() {
        timeHandler.removeCallbacks(updateTimeRunnable)
        super.onDestroy()
    }
}
