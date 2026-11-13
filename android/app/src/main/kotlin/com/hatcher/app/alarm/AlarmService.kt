package com.hatcher.app.alarm

import android.app.KeyguardManager
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import androidx.core.app.ServiceCompat
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import com.google.firebase.firestore.FirebaseFirestore
import com.hatcher.app.MainActivity
import com.hatcher.app.notification.NotificationHelper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

/**
 * AlarmService — Foreground service that manages the alarm ring lifecycle.
 *
 * Flow:
 * 1. Check local SharedPreferences for slot completion (fast, no network).
 * 2. Query Firestore with a 5-second timeout.
 * 3. FAIL LOUD: if the check fails or times out, ring anyway.
 *    Missing a "slot already done" check is far less harmful than
 *    silently skipping an alarm the user still needs.
 * 4. Determine phone state (screen on+unlocked vs locked/off).
 * 5. If screen on+unlocked → heads-up notification only (small beep at low volume).
 *    If locked/off → launch AlarmActivity full-screen + play alarm audio.
 * 6. Play audio on STREAM_ALARM (bypasses silent/vibrate/DND).
 * 7. Volume ramp: start at 20%, reach 100% over 30 seconds.
 * 8. Restore user's original volume after alarm stops.
 * 9. Repeat every repeatMinutes until slot is done or next slot begins.
 *
 * Foreground service type "alarm" (Android 14+, declared in manifest):
 *   <service android:foregroundServiceType="alarm" .../>
 * This type requires the FOREGROUND_SERVICE_ALARM permission and allows
 * the service to start while in the background (e.g. from AlarmReceiver).
 *
 * WHY a foreground service?
 * - Background services are killed aggressively on API 26+ (Oreo).
 * - Foreground services with STREAM_ALARM audio are specifically allowed
 *   to continue even under battery optimization and Doze mode.
 * - The foreground notification tells the user the alarm is active and
 *   gives them Rotate / Snooze buttons without unlocking the screen.
 */
class AlarmService : Service() {

    companion object {
        private const val TAG = "AlarmService"

        // Notification ID for the ongoing foreground notification.
        // Must be non-zero; we use a fixed ID since only one alarm runs at a time.
        const val FOREGROUND_NOTIFICATION_ID = 101

        // Local broadcast action sent by AlarmActivity / RotateActionReceiver
        // when the user confirms rotation — signals this service to stop.
        const val ACTION_ROTATION_DONE = "com.hatcher.ROTATION_DONE"

        // Local broadcast action to stop the alarm (from snooze or other sources)
        const val ACTION_STOP_ALARM = "com.hatcher.STOP_ALARM"
    }

    // ----------------------------------------------------------------
    // Service state
    // ----------------------------------------------------------------

    // CoroutineScope tied to this service's lifecycle.
    // SupervisorJob ensures one coroutine failure doesn't cancel siblings.
    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // Handler for the repeat runnable (runs on main thread for thread safety)
    private val mainHandler = Handler(Looper.getMainLooper())

    // Current alarm parameters, set in onStartCommand
    private var slotKey: String = ""
    private var date: String = ""
    private var repeatMinutes: Int = 10

    // Volume & Audio management
    private var audioManager: AudioManager? = null
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var originalAlarmVolume: Int = -1  // -1 = not saved yet
    private var maxAlarmVolume: Int = 1

    // Tracks whether the volume ramp coroutine is still running
    private var volumeRampActive = false

    // The repeat runnable — re-rings the alarm after repeatMinutes if still undone
    private var repeatRunnable: Runnable? = null

    // BroadcastReceiver that listens for rotation-done / stop signals
    private val stopReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                ACTION_ROTATION_DONE, ACTION_STOP_ALARM -> {
                    Log.i(TAG, "Stop signal received — stopping alarm")
                    stopAlarm()
                }
            }
        }
    }

    // ----------------------------------------------------------------
    // Lifecycle
    // ----------------------------------------------------------------

    override fun onBind(intent: Intent?): IBinder? = null // Not a bound service

    override fun onCreate() {
        super.onCreate()

        audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        maxAlarmVolume = audioManager!!.getStreamMaxVolume(AudioManager.STREAM_ALARM)

        // Register the stop receiver using local broadcast (more efficient than
        // system broadcast for intra-app communication).
        val filter = IntentFilter().apply {
            addAction(ACTION_ROTATION_DONE)
            addAction(ACTION_STOP_ALARM)
        }
        // Use exported=false equivalent: LocalBroadcastManager is deprecated,
        // so we use Context.registerReceiver with RECEIVER_NOT_EXPORTED (API 33+)
        // or simply ContextCompat approach for older APIs.
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(stopReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(stopReceiver, filter)
        }
    }

    /**
     * onStartCommand is called each time startForegroundService() is invoked
     * (including from AlarmReceiver and from the repeat runnable).
     *
     * We call startForeground() IMMEDIATELY (before any coroutine) because
     * Android requires it within 5 seconds of onStartCommand returning on API 26+.
     * Failure to do so causes a ForegroundServiceDidNotStartInTimeException (API 31+)
     * and an ANR on older versions.
     *
     * We return START_NOT_STICKY so the service is not automatically restarted
     * if killed — the next scheduled alarm via AlarmManager will fire correctly.
     */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // ---- Parse intent extras ----
        slotKey = intent?.getStringExtra("slotKey") ?: slotKey
        date = intent?.getStringExtra("date") ?: date
        repeatMinutes = intent?.getIntExtra("repeatMinutes", 10) ?: 10

        Log.i(TAG, "onStartCommand: slotKey=$slotKey date=$date repeat=${repeatMinutes}min")

        // ---- Guard: If today is muted by user, stop immediately ----
        val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        val mutedUntil = prefs.getString("muted_until_date", null) ?: prefs.getString("muted_date", null)
        if (!mutedUntil.isNullOrBlank() && date <= mutedUntil) {
            Log.i(TAG, "AlarmService: Date ($date) is muted until $mutedUntil — stopping immediately")
            stopSelf()
            return START_NOT_STICKY
        }

        // ---- Start foreground IMMEDIATELY ----
        // We build a placeholder "in progress" notification. The real alarm
        // notification (with actions) is posted by ringAlarm() shortly after.
        val ongoingNotification = NotificationHelper.buildAlarmNotification(
            context = this,
            slotKey = slotKey,
            date = date,
            doneBy = loadUserName(),
            snoozeMinutes = repeatMinutes
        )
        ServiceCompat.startForeground(
            this,
            FOREGROUND_NOTIFICATION_ID,
            ongoingNotification,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            } else {
                0
            }
        )

        // ---- Launch the check+ring flow on a coroutine ----
        serviceScope.launch {
            runAlarmFlow()
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(stopReceiver)
        serviceScope.cancel()
        mainHandler.removeCallbacksAndMessages(null)
        stopAlarmAudio()
        stopVibration()
        restoreVolume()
    }

    // ----------------------------------------------------------------
    // Core alarm flow
    // ----------------------------------------------------------------

    /**
     * runAlarmFlow — the main coroutine that:
     * 1. Checks if the slot is already done (local + Firestore).
     * 2. Rings the alarm if not done.
     * 3. Schedules a repeat check after repeatMinutes.
     */
    private suspend fun runAlarmFlow() {
        val isDone = checkSlotDone(date, slotKey)
        if (isDone) {
            Log.i(TAG, "Slot $slotKey on $date is already done — stopping service")
            stopSelf()
            return
        }
        ringAlarm()
    }

    /**
     * checkSlotDone — two-tier completion check.
     *
     * Tier 1: SharedPreferences — instant, no network, O(1).
     *   Return true immediately if the local flag is set. This handles the
     *   common case where the user already logged rotation on this device.
     *
     * Tier 2: Firestore — authoritative, but network-dependent.
     *   We use withTimeoutOrNull(5000) so a slow/no connection doesn't
     *   delay the alarm by more than 5 seconds. If Firestore times out or
     *   throws, we assume NOT done (fail loud = ring the alarm).
     *
     * This design ensures:
     * - Multi-device households: if person A logged rotation on their phone,
     *   person B's device learns this via Firestore and doesn't ring.
     * - Offline robustness: Firestore failure never silences the alarm.
     */
    private suspend fun checkSlotDone(date: String, slot: String): Boolean {
        // ---- Tier 1: Local SharedPreferences ----
        val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        val mutedUntil = prefs.getString("muted_until_date", null) ?: prefs.getString("muted_date", null)
        if (!mutedUntil.isNullOrBlank() && date <= mutedUntil) {
            Log.d(TAG, "Slot suppressed: date ($date) is muted until $mutedUntil")
            return true
        }

        if (prefs.getBoolean("done_${date}_${slot}", false)) {
            Log.d(TAG, "Slot done (local): $date $slot")
            return true
        }

        // ---- Tier 2: Firestore with 5-second timeout ----
        val docId = "${date}_${slot}"
        val firestoreResult = withTimeoutOrNull(5_000L) {
            suspendCoroutine<Boolean> { cont ->
                FirebaseFirestore.getInstance()
                    .collection("rotations")
                    .document(docId)
                    .get()
                    .addOnSuccessListener { snapshot ->
                        val done = snapshot.exists()
                        // Cache locally to skip Firestore next time
                        if (done) {
                            prefs.edit().putBoolean("done_${date}_${slot}", true).apply()
                        }
                        cont.resume(done)
                    }
                    .addOnFailureListener { e ->
                        Log.w(TAG, "Firestore check failed: ${e.message}")
                        // Fail loud: return false (not done) on error
                        cont.resume(false)
                    }
            }
        }

        // If timeout (null) or false → not confirmed done → ring the alarm
        return firestoreResult == true
    }

    // ----------------------------------------------------------------
    // Phone state detection
    // ----------------------------------------------------------------

    /**
     * PhoneState describes the current screen and lock state.
     * This determines whether we show a full-screen Activity or a
     * heads-up notification.
     */
    enum class PhoneState { SCREEN_ON_UNLOCKED, LOCKED, OFF }

    /**
     * determinePhoneState — uses PowerManager and KeyguardManager to decide
     * the current screen state.
     *
     * PowerManager.isInteractive(): true if the screen is on (interactive),
     *   false if the screen is off or in a low-power non-interactive state.
     *   (Do NOT use the deprecated isScreenOn().)
     *
     * KeyguardManager.isKeyguardLocked(): true if the keyguard (lock screen)
     *   is currently shown or if the device is secured and the screen is off.
     *
     * Combined logic:
     *   isInteractive=true  + isKeyguardLocked=false → SCREEN_ON_UNLOCKED
     *   isInteractive=true  + isKeyguardLocked=true  → LOCKED (screen on but locked)
     *   isInteractive=false                           → OFF
     */
    private fun determinePhoneState(): PhoneState {
        val power = getSystemService(POWER_SERVICE) as PowerManager
        val keyguard = getSystemService(KEYGUARD_SERVICE) as KeyguardManager

        return when {
            !power.isInteractive -> PhoneState.OFF
            keyguard.isKeyguardLocked -> PhoneState.LOCKED
            else -> PhoneState.SCREEN_ON_UNLOCKED
        }
    }

    // ----------------------------------------------------------------
    // Alarm ringing
    // ----------------------------------------------------------------

    /**
     * ringAlarm — determines phone state and launches the appropriate UI.
     *
     * Design rationale:
     * - SCREEN_ON_UNLOCKED: The user is actively using the phone.
     *   A full-screen takeover would be jarring and disruptive. Instead,
     *   we show a heads-up (banner) notification at a low volume. The user
     *   can tap it to get the full action buttons.
     * - LOCKED / OFF: The screen must be turned on and the alarm shown
     *   full-screen over the lock screen so the user can act without
     *   having to unlock (they may have wet/dirty hands in a farm setting).
     */
    private fun ringAlarm() {
        val state = determinePhoneState()
        Log.i(TAG, "Phone state: $state — ringing alarm for $slotKey $date")

        when (state) {
            PhoneState.SCREEN_ON_UNLOCKED -> {
                // Show heads-up banner and play alarm audio on STREAM_ALARM
                // so it rings audibly even when phone is in silent/vibrate mode!
                showHeadsUpNotification()
                startAlarmAudio(gentleBeepOnly = false)
                startVibration()
                serviceScope.launch { startVolumeRamp(gentle = true) }
            }
            PhoneState.LOCKED, PhoneState.OFF -> {
                // Full-screen alarm: launch AlarmActivity AND show the ongoing
                // foreground notification, plus full looping ALARM-stream sound & vibration.
                launchAlarmActivity()
                showFullScreenNotification()
                startAlarmAudio(gentleBeepOnly = false)
                startVibration()
                serviceScope.launch { startVolumeRamp(gentle = false) }
            }
        }

        // Schedule repeat check in case the user ignores the alarm
        scheduleRepeat()
    }

    /**
     * showHeadsUpNotification — posts a HIGH priority notification that
     * appears as a banner at the top of the screen. Used when the screen is on.
     */
    private fun showHeadsUpNotification() {
        val notification = NotificationHelper.buildHeadsUpNotification(
            context = this,
            slotKey = slotKey,
            date = date,
            snoozeMinutes = repeatMinutes
        )
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(FOREGROUND_NOTIFICATION_ID + 1, notification)
    }

    /**
     * showFullScreenNotification — updates the ongoing foreground notification
     * with a full-screen intent so it can invoke AlarmActivity from the lock
     * screen notification shade.
     */
    private fun showFullScreenNotification() {
        val notification = NotificationHelper.buildAlarmNotification(
            context = this,
            slotKey = slotKey,
            date = date,
            doneBy = loadUserName(),
            snoozeMinutes = repeatMinutes
        )
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(FOREGROUND_NOTIFICATION_ID, notification)
    }

    /**
     * launchAlarmActivity — starts AlarmActivity with FLAG_ACTIVITY_NEW_TASK.
     *
     * Combined with AlarmActivity's setShowWhenLocked(true) + setTurnScreenOn(true),
     * this causes the system to light up the screen and show the Activity over
     * the keyguard without requiring a PIN/biometric.
     *
     * Note: On Android 10+ (API 29+) this also requires the app to hold
     * USE_FULL_SCREEN_INTENT permission; we check this in MainActivity.
     */
    private fun launchAlarmActivity() {
        val activityIntent = Intent(this, AlarmActivity::class.java).apply {
            putExtra("slotKey", slotKey)
            putExtra("date", date)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_NO_HISTORY or // Don't add to back stack
                Intent.FLAG_ACTIVITY_SINGLE_TOP    // Don't create multiple instances
            )
        }
        startActivity(activityIntent)
    }

    // ----------------------------------------------------------------
    // Volume ramp
    // ----------------------------------------------------------------

    /**
     * startVolumeRamp — coroutine that gradually increases STREAM_ALARM volume.
     *
     * We ramp volume rather than starting at full blast because:
     * 1. A sudden loud alarm is jarring if the phone is in a pocket.
     * 2. Users in noisy environments (farms, workshops) need loud; users who
     *    notice the alarm early get a gentler wake.
     *
     * Ramp profile:
     *   - Start at 20% of max volume
     *   - Increase by 10% every 10 seconds
     *   - Reach 100% at 80 seconds (8 steps of 10%)
     *
     * @param gentle If true (screen-on case), cap at 50% and ramp faster.
     */
    private suspend fun startVolumeRamp(gentle: Boolean) {
        val am = audioManager ?: return

        // Save original volume before we touch it, so we can restore it on stop.
        // We only save once per service instance to avoid overwriting with our
        // own ramp value if this coroutine is somehow called twice.
        if (originalAlarmVolume == -1) {
            originalAlarmVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
        }

        val targetPercent = if (gentle) 80 else 100
        val startVolume = (maxAlarmVolume * 0.70).toInt().coerceAtLeast(2)
        val targetVolume = (maxAlarmVolume * targetPercent / 100.0).toInt().coerceAtLeast(startVolume)

        // Set initial volume immediately to an audible level so it breaks through silent mode
        am.setStreamVolume(AudioManager.STREAM_ALARM, startVolume, 0)
        volumeRampActive = true

        var currentVolume = startVolume
        // Each step adds volume; delay 5 seconds between steps
        val stepSize = (maxAlarmVolume * 0.15).toInt().coerceAtLeast(1)

        while (volumeRampActive && currentVolume < targetVolume) {
            delay(5_000L) // 5-second interval between volume steps
            if (!volumeRampActive) break
            currentVolume = (currentVolume + stepSize).coerceAtMost(targetVolume)
            am.setStreamVolume(AudioManager.STREAM_ALARM, currentVolume, 0)
            Log.d(TAG, "Volume ramp: $currentVolume / $maxAlarmVolume")
        }

        // Hold at max until alarm stops
    }

    /**
     * restoreVolume — returns STREAM_ALARM to its pre-alarm level.
     * Called from stopAlarm() and onDestroy() to ensure we never leave
     * the user's volume settings in a modified state.
     */
    private fun restoreVolume() {
        if (originalAlarmVolume >= 0) {
            audioManager?.setStreamVolume(AudioManager.STREAM_ALARM, originalAlarmVolume, 0)
            Log.d(TAG, "Volume restored to $originalAlarmVolume")
            originalAlarmVolume = -1
        }
        volumeRampActive = false
    }

    // ----------------------------------------------------------------
    // Repeat scheduling
    // ----------------------------------------------------------------

    /**
     * scheduleRepeat — posts a delayed Runnable on the main thread that
     * re-runs the alarm flow after [repeatMinutes].
     *
     * We also check whether we're approaching the next scheduled slot time.
     * If the next slot fires within [repeatMinutes], we don't repeat — the
     * next alarm will handle it. This prevents overlapping alarms.
     */
    private fun scheduleRepeat() {
        // Cancel any existing repeat to avoid stacking
        repeatRunnable?.let { mainHandler.removeCallbacks(it) }

        val delayMillis = repeatMinutes * 60_000L
        repeatRunnable = Runnable {
            Log.i(TAG, "Repeating alarm check for $slotKey $date")
            serviceScope.launch { runAlarmFlow() }
        }
        mainHandler.postDelayed(repeatRunnable!!, delayMillis)
    }

    // ----------------------------------------------------------------
    // Stop
    // ----------------------------------------------------------------

    /**
     * startAlarmAudio — initializes and plays audio on AudioAttributes.USAGE_ALARM
     * so it plays through Silent, Vibrate, and DND modes.
     * Uses bundled res/raw/alarm_sound if valid, else falls back to system alarm ringtone.
     */
    private fun startAlarmAudio(gentleBeepOnly: Boolean) {
        stopAlarmAudio()
        try {
            // Always use system ALARM stream and sound so it penetrates Silent/Vibrate mode!
            val uri = run {
                val resId = resources.getIdentifier("alarm_sound", "raw", packageName)
                var validRaw = false
                if (resId != 0) {
                    try {
                        resources.openRawResourceFd(resId)?.use { afd ->
                            if (afd.length > 100) validRaw = true
                        }
                    } catch (_: Exception) {}
                }
                if (validRaw) {
                    android.net.Uri.parse("android.resource://$packageName/$resId")
                } else {
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                        ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                }
            }

            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            val player = MediaPlayer().apply {
                setAudioAttributes(attrs)
                @Suppress("DEPRECATION")
                setAudioStreamType(AudioManager.STREAM_ALARM)
                setDataSource(this@AlarmService, uri)
                isLooping = true
                prepare()
                start()
            }
            mediaPlayer = player
        } catch (e: Exception) {
            Log.e(TAG, "Custom/primary alarm audio failed, trying system default fallback", e)
            try {
                val fallbackUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                val player = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                    @Suppress("DEPRECATION")
                    setAudioStreamType(AudioManager.STREAM_ALARM)
                    setDataSource(this@AlarmService, fallbackUri)
                    isLooping = true
                    prepare()
                    start()
                }
                mediaPlayer = player
            } catch (ex: Exception) {
                Log.e(TAG, "Fallback alarm audio also failed", ex)
            }
        }
    }

    private fun stopAlarmAudio() {
        try {
            mediaPlayer?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping MediaPlayer", e)
        } finally {
            mediaPlayer = null
        }
    }

    @Suppress("DEPRECATION")
    private fun startVibration() {
        try {
            val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator
            } else {
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            vibrator = vib
            val pattern = longArrayOf(0, 600, 400, 600, 400)
            vib.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } catch (e: Exception) {
            Log.w(TAG, "Vibration error", e)
        }
    }

    private fun stopVibration() {
        try {
            vibrator?.cancel()
        } catch (_: Exception) {}
        vibrator = null
    }

    /**
     * stopAlarm — cleanly shuts down the alarm.
     *
     * Called when:
     * - The user taps "Rotated ✔" in AlarmActivity or the notification
     * - RotateActionReceiver broadcasts ACTION_ROTATION_DONE
     * - Snooze is tapped (AlarmScheduler will handle the new alarm)
     */
    fun stopAlarm() {
        Log.i(TAG, "stopAlarm() called for $slotKey $date")
        volumeRampActive = false
        repeatRunnable?.let { mainHandler.removeCallbacks(it) }
        repeatRunnable = null
        stopAlarmAudio()
        stopVibration()
        restoreVolume()

        // Dismiss the heads-up notification (if shown)
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(FOREGROUND_NOTIFICATION_ID + 1)

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------

    private fun loadUserName(): String {
        val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString("user_name", "Unknown") ?: "Unknown"
    }
}
