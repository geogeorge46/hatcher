package com.hatcher.app.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import com.hatcher.app.MainActivity
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * AlarmSettings — a plain data class that holds everything needed to (re-)
 * schedule alarms after a device reboot or after the user edits a batch.
 *
 * We persist this to SharedPreferences as JSON so AlarmReceiver and
 * BootReceiver can call scheduleAll() without Flutter being alive.
 */
data class AlarmSettings(
    val placedDate: String,            // "yyyy-MM-dd" — when eggs were placed in the incubator
    val slots: Map<String, String>,    // slotKey → "HH:mm" e.g. "morning" → "08:30"
    val stopFromDay: Int,              // day number after which rotation should stop (0 = never stop)
    val candlingDays: List<Int>        // day numbers on which a candling reminder should fire
)

/**
 * AlarmScheduler schedules all rotation alarms for the next 7 days using
 * AlarmManager.setAlarmClock(), which is the highest-priority alarm type,
 * exempt from Doze mode, and guaranteed to fire even with battery optimization.
 *
 * WHY setAlarmClock()?
 * - setExact() / setExactAndAllowWhileIdle() can be delayed by up to 9 minutes in
 *   Doze mode (Android 6+).
 * - setAlarmClock() is specifically carved out of Doze restrictions by Android.
 *   The system also shows a clock icon in the status bar, reinforcing to the user
 *   that an alarm is pending.
 * - On API 31+ we still need SCHEDULE_EXACT_ALARM or USE_EXACT_ALARM permission.
 *
 * WHY only 7 days?
 * - Android limits the number of pending PendingIntents; keeping a rolling 7-day
 *   window stays well within any OEM-imposed ceiling.
 * - After each alarm fires, AlarmReceiver re-schedules the NEXT occurrence of the
 *   same slot (rolling schedule pattern), so we always have coverage.
 */
object AlarmScheduler {

    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    private val KOLKATA = ZoneId.of("Asia/Kolkata")
    private val DATE_FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd")
    private val TIME_FMT = DateTimeFormatter.ofPattern("HH:mm")

    // SharedPreferences key under which we store the full AlarmSettings JSON
    // so it can be restored after reboot without Flutter.
    private const val KEY_SETTINGS = "alarm_settings_json"

    // SharedPreferences key for the JSON array of active request codes.
    // We track these so cancelAll() can cancel every PendingIntent precisely.
    private const val KEY_REQUEST_CODES = "alarm_request_codes"

    // Base request codes per slot type to avoid collisions.
    // Each alarm's request code = BASE + (dayOffset * 10) + slotIndex
    private const val RC_BASE_ROTATION  = 1000
    private const val RC_BASE_CANDLING  = 2000
    private const val RC_BASE_HATCH     = 3000
    private const val RC_BASE_LOCKDOWN  = 4000
    private const val RC_BASE_SNOOZE    = 5000  // used by snooze scheduling

    // Slot indices for request code arithmetic
    private val SLOT_INDEX = mapOf("morning" to 0, "noon" to 1, "evening" to 2)

    // The day on which a fully incubated egg should hatch
    private const val HATCH_DAY = 21

    // ----------------------------------------------------------------
    // Public API
    // ----------------------------------------------------------------

    /**
     * scheduleAll — the main entry point called from MainActivity when the
     * Flutter UI creates or updates a batch.
     *
     * Logic:
     * 1. Persist [settings] to SharedPreferences (for reboot recovery).
     * 2. Determine today's date in Kolkata timezone.
     * 3. For each of the next 7 days:
     *    a. Compute the incubation day number relative to placedDate.
     *    b. Skip rotation alarms if dayNumber >= stopFromDay (lockdown period).
     *    c. For each slot, if the target time is in the future, call scheduleAlarm().
     *    d. If dayNumber is in candlingDays, schedule a candling reminder at 09:00.
     * 4. Schedule hatch-day notification on day 21 at 07:00.
     * 5. Schedule lockdown notification on day stopFromDay at 07:00.
     */
    fun scheduleAll(context: Context, settings: AlarmSettings) {
        // Persist settings so BootReceiver can call us after reboot
        saveSettings(context, settings)

        val today = LocalDate.now(KOLKATA)
        val nowMillis = System.currentTimeMillis()
        val activeCodes = mutableListOf<Int>()

        // We schedule up to 7 days of alarms at a time (rolling window).
        for (offset in 0..6) {
            val date = today.plusDays(offset.toLong())
            val dateStr = date.format(DATE_FMT)
            val dayNum = dayNumber(settings.placedDate, dateStr)

            // ---- Rotation alarms ----
            // Skip rotation if we're in the "lockdown" period (day >= stopFromDay).
            // stopFromDay == 0 means rotation never stops.
            val inRotationWindow = settings.stopFromDay <= 0 || dayNum < settings.stopFromDay

            if (inRotationWindow) {
                settings.slots.forEach { (slotKey, timeStr) ->
                    val triggerMillis = slotTimeToEpochMillis(dateStr, timeStr)
                    if (triggerMillis > nowMillis) {
                        val slotIdx = SLOT_INDEX[slotKey] ?: 0
                        // Request code must be unique per (day, slot) pair.
                        val rc = RC_BASE_ROTATION + (offset * 10) + slotIdx
                        scheduleAlarm(
                            context = context,
                            triggerAtMillis = triggerMillis,
                            slotKey = slotKey,
                            date = dateStr,
                            type = "rotation",
                            requestCode = rc
                        )
                        activeCodes.add(rc)
                    }
                }
            }

            // ---- Candling alarms ----
            if (dayNum in settings.candlingDays) {
                // Candling reminder fires at 09:00 on the candling day
                val triggerMillis = slotTimeToEpochMillis(dateStr, "09:00")
                if (triggerMillis > nowMillis) {
                    val rc = RC_BASE_CANDLING + offset
                    scheduleAlarm(
                        context = context,
                        triggerAtMillis = triggerMillis,
                        slotKey = "candling",
                        date = dateStr,
                        type = "candling",
                        requestCode = rc
                    )
                    activeCodes.add(rc)
                }
            }

            // ---- Hatch day notification ----
            if (dayNum == HATCH_DAY) {
                val triggerMillis = slotTimeToEpochMillis(dateStr, "07:00")
                if (triggerMillis > nowMillis) {
                    scheduleAlarm(
                        context = context,
                        triggerAtMillis = triggerMillis,
                        slotKey = "hatch",
                        date = dateStr,
                        type = "hatch",
                        requestCode = RC_BASE_HATCH
                    )
                    activeCodes.add(RC_BASE_HATCH)
                }
            }

            // ---- Lockdown notification ----
            if (settings.stopFromDay > 0 && dayNum == settings.stopFromDay) {
                val triggerMillis = slotTimeToEpochMillis(dateStr, "07:00")
                if (triggerMillis > nowMillis) {
                    scheduleAlarm(
                        context = context,
                        triggerAtMillis = triggerMillis,
                        slotKey = "lockdown",
                        date = dateStr,
                        type = "lockdown",
                        requestCode = RC_BASE_LOCKDOWN
                    )
                    activeCodes.add(RC_BASE_LOCKDOWN)
                }
            }
        }

        // Persist active request codes for cancelAll()
        saveRequestCodes(context, activeCodes)
    }

    /**
     * scheduleAlarm — registers a single alarm via AlarmManager.setAlarmClock().
     *
     * @param triggerAtMillis  Epoch millis when the alarm should fire.
     * @param slotKey          "morning" | "noon" | "evening" | "candling" | "hatch" | "lockdown"
     * @param date             "yyyy-MM-dd" string passed to AlarmReceiver as an extra.
     * @param type             "rotation" | "candling" | "hatch" | "lockdown"
     * @param requestCode      Unique int used to identify this PendingIntent.
     *
     * setAlarmClock() requires two PendingIntents:
     *   1. The "work" PendingIntent → AlarmReceiver (fires when alarm goes off).
     *   2. The "show" PendingIntent → opens the app/AlarmActivity when the user
     *      taps the clock icon shown in the system status bar.
     */
    fun scheduleAlarm(
        context: Context,
        triggerAtMillis: Long,
        slotKey: String,
        date: String,
        type: String,
        requestCode: Int
    ) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        // Guard: on API 31+ verify we still have exact-alarm permission before
        // attempting the call. If we don't, the app would crash with a SecurityException.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !alarmManager.canScheduleExactAlarms()
        ) {
            // Cannot schedule; MainActivity's checkPermissions will surface this
            // to the user. We silently skip rather than crash.
            return
        }

        // ---- Work intent → AlarmReceiver ----
        val receiverIntent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("slotKey", slotKey)
            putExtra("date", date)
            putExtra("type", type)
            // Embed the request code so AlarmReceiver can pass it to scheduleNext()
            putExtra("requestCode", requestCode)
        }
        // FLAG_UPDATE_CURRENT: if a PendingIntent with the same requestCode already
        // exists, replace its extras. This handles reschedule scenarios correctly.
        // FLAG_IMMUTABLE is required on API 31+ for security; the receiver doesn't
        // need to mutate the intent.
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val workPendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            receiverIntent,
            pendingFlags
        )

        // ---- Show intent → AlarmActivity (shown in status bar clock tap) ----
        val showIntent = Intent(context, AlarmActivity::class.java).apply {
            putExtra("slotKey", slotKey)
            putExtra("date", date)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val showPendingIntent = PendingIntent.getActivity(
            context,
            requestCode + 10_000, // Different namespace from broadcast PIs
            showIntent,
            pendingFlags
        )

        // ---- Register with AlarmManager ----
        // AlarmClockInfo pairs the trigger time with the "show" intent.
        // The AlarmManager guarantees delivery even in Doze mode and shows
        // a clock indicator in the system status bar.
        val alarmClockInfo = AlarmManager.AlarmClockInfo(triggerAtMillis, showPendingIntent)
        alarmManager.setAlarmClock(alarmClockInfo, workPendingIntent)
    }

    /**
     * cancelAll — cancels every PendingIntent we previously registered.
     *
     * We iterate over the saved list of request codes and call cancel() on
     * each reconstructed PendingIntent. After cancellation we clear the list.
     */
    fun cancelAll(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val codes = loadRequestCodes(context)
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_NO_CREATE
        }

        codes.forEach { rc ->
            // Reconstruct a matching PendingIntent (extras don't need to match for cancel)
            val pi = PendingIntent.getBroadcast(
                context,
                rc,
                Intent(context, AlarmReceiver::class.java),
                pendingFlags
            )
            // FLAG_NO_CREATE returns null if the PI doesn't exist — safe to skip
            if (pi != null) {
                alarmManager.cancel(pi)
                pi.cancel()
            }

            // Also cancel the corresponding "show" PendingIntent
            val showPi = PendingIntent.getActivity(
                context,
                rc + 10_000,
                Intent(context, AlarmActivity::class.java),
                pendingFlags
            )
            showPi?.cancel()
        }

        // Clear the stored code list
        saveRequestCodes(context, emptyList())
    }

    /**
     * scheduleNext — called by AlarmReceiver immediately after an alarm fires
     * to maintain the rolling schedule (schedules the same slot for the NEXT
     * occurrence 24 hours later).
     *
     * This ensures continuous coverage even if the app is not running when
     * the initial 7-day window expires.
     *
     * @param slotKey     The slot that just fired ("morning" | "noon" | "evening")
     * @param date        The date string of the alarm that just fired ("yyyy-MM-dd")
     * @param settings    The persisted AlarmSettings (loaded from SharedPreferences)
     */
    fun scheduleNext(context: Context, slotKey: String, date: String, settings: AlarmSettings) {
        val firedDate = LocalDate.parse(date, DATE_FMT)
        val nextDate = firedDate.plusDays(1)
        val nextDateStr = nextDate.format(DATE_FMT)

        // Check whether the next day is still within the rotation window
        val nextDayNum = dayNumber(settings.placedDate, nextDateStr)
        val inWindow = settings.stopFromDay <= 0 || nextDayNum < settings.stopFromDay
        if (!inWindow) return // Rotation ends; don't schedule further

        val timeStr = settings.slots[slotKey] ?: return
        val triggerMillis = slotTimeToEpochMillis(nextDateStr, timeStr)
        if (triggerMillis <= System.currentTimeMillis()) return // Already past

        // Use a rolling request code derived from the absolute epoch day to stay unique
        val slotIdx = SLOT_INDEX[slotKey] ?: 0
        val epochDay = nextDate.toEpochDay().toInt()
        val rc = RC_BASE_ROTATION + ((epochDay % 1000) * 10) + slotIdx

        scheduleAlarm(
            context = context,
            triggerAtMillis = triggerMillis,
            slotKey = slotKey,
            date = nextDateStr,
            type = "rotation",
            requestCode = rc
        )

        // Append new request code to stored list
        val codes = loadRequestCodes(context).toMutableList()
        if (!codes.contains(rc)) {
            codes.add(rc)
            saveRequestCodes(context, codes)
        }
    }

    // ----------------------------------------------------------------
    // Time helpers
    // ----------------------------------------------------------------

    /**
     * slotTimeToEpochMillis — converts a "yyyy-MM-dd" date and "HH:mm" time
     * string in the Asia/Kolkata timezone to a UTC epoch millisecond value
     * suitable for passing to AlarmManager.
     *
     * We use java.time (API 26+) which is available because minSdk = 26.
     * java.time handles DST and timezone transitions correctly, unlike the
     * deprecated java.util.Calendar approach.
     */
    fun slotTimeToEpochMillis(date: String, slotTimeStr: String): Long {
        val localDate = LocalDate.parse(date, DATE_FMT)
        val (hour, minute) = slotTimeStr.split(":").map { it.toInt() }
        val localDateTime = LocalDateTime.of(localDate, java.time.LocalTime.of(hour, minute))
        return localDateTime.atZone(KOLKATA).toInstant().toEpochMilli()
    }

    /**
     * dayNumber — computes how many days have elapsed since placedDate up to
     * and including currentDate, expressed as a 1-based incubation day number.
     *
     * Example: placedDate = "2024-05-01", currentDate = "2024-05-01" → day 1
     *          placedDate = "2024-05-01", currentDate = "2024-05-02" → day 2
     */
    fun dayNumber(placedDate: String, currentDate: String): Int {
        val placed = LocalDate.parse(placedDate, DATE_FMT)
        val current = LocalDate.parse(currentDate, DATE_FMT)
        return (current.toEpochDay() - placed.toEpochDay()).toInt() + 1
    }

    // ----------------------------------------------------------------
    // SharedPreferences persistence helpers
    // ----------------------------------------------------------------

    private fun getPrefs(context: Context): SharedPreferences =
        context.getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)

    /** Serialises [settings] to JSON and saves to SharedPreferences. */
    fun saveSettings(context: Context, settings: AlarmSettings) {
        val json = JSONObject().apply {
            put("placedDate", settings.placedDate)
            put("stopFromDay", settings.stopFromDay)
            val slotsObj = JSONObject()
            settings.slots.forEach { (k, v) -> slotsObj.put(k, v) }
            put("slots", slotsObj)
            val candlingArr = JSONArray()
            settings.candlingDays.forEach { candlingArr.put(it) }
            put("candlingDays", candlingArr)
        }
        getPrefs(context).edit().putString(KEY_SETTINGS, json.toString()).apply()
    }

    /** Loads and deserialises AlarmSettings from SharedPreferences, or null if none saved. */
    fun loadSettings(context: Context): AlarmSettings? {
        val jsonStr = getPrefs(context).getString(KEY_SETTINGS, null) ?: return null
        return try {
            val json = JSONObject(jsonStr)
            val slotsObj = json.getJSONObject("slots")
            val slots = mutableMapOf<String, String>()
            slotsObj.keys().forEach { slots[it] = slotsObj.getString(it) }
            val candlingArr = json.getJSONArray("candlingDays")
            val candlingDays = (0 until candlingArr.length()).map { candlingArr.getInt(it) }
            AlarmSettings(
                placedDate = json.getString("placedDate"),
                slots = slots,
                stopFromDay = json.getInt("stopFromDay"),
                candlingDays = candlingDays
            )
        } catch (e: Exception) {
            null
        }
    }

    private fun saveRequestCodes(context: Context, codes: List<Int>) {
        val arr = JSONArray()
        codes.forEach { arr.put(it) }
        getPrefs(context).edit().putString(KEY_REQUEST_CODES, arr.toString()).apply()
    }

    private fun loadRequestCodes(context: Context): List<Int> {
        val jsonStr = getPrefs(context).getString(KEY_REQUEST_CODES, null) ?: return emptyList()
        return try {
            val arr = JSONArray(jsonStr)
            (0 until arr.length()).map { arr.getInt(it) }
        } catch (e: Exception) {
            emptyList()
        }
    }
}
