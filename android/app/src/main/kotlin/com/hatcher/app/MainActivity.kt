package com.hatcher.app

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.telecom.TelecomManager
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.hatcher.app.alarm.AlarmScheduler
import com.hatcher.app.alarm.AlarmSettings
import com.hatcher.app.escalation.EscalationService
import com.hatcher.app.escalation.FirestoreEscalationService
import com.hatcher.app.gateway.GatewayService
import com.hatcher.app.notification.NotificationHelper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * MainActivity — the single Activity that hosts the Flutter engine.
 *
 * We subclass FlutterActivity (not FlutterFragmentActivity) because we don't
 * need Fragment support and FlutterActivity has less overhead.
 *
 * The MethodChannel "hatcher/native" bridges Flutter UI ↔ native Android logic.
 * All alarm scheduling, permission checks, and system-settings navigation live
 * here or in dedicated Kotlin objects to keep this class lean.
 */
class MainActivity : FlutterActivity() {

    // The MethodChannel name must exactly match the Dart side.
    companion object {
        const val CHANNEL = "hatcher/native"

        // SharedPreferences file name used across the whole app.
        const val PREFS_NAME = "hatcher_prefs"
    }

    /**
     * configureFlutterEngine is called once when the Flutter engine is attached.
     * This is the right place to register MethodChannels — NOT in onCreate() —
     * because the engine may be pre-warmed by Flutter's warm-up mechanism.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Ensure notification channels exist before any alarm fires.
        // Safe to call multiple times; createChannels() is idempotent.
        NotificationHelper.createChannels(this)

        // Phase 2: activate Firestore-backed EscalationService implementation
        EscalationService.setImplementation(FirestoreEscalationService())

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                // ----------------------------------------------------------------
                // scheduleAlarms
                // Called by Flutter when the user creates or edits a batch.
                // Args: JSON string with keys:
                //   placedDate   — "yyyy-MM-dd" when eggs were placed
                //   slots        — Map of slotKey → "HH:mm" (morning/noon/evening)
                //   stopFromDay  — Int, day number after which rotation stops
                //   candlingDays — List<Int> day numbers for candling reminders
                // ----------------------------------------------------------------
                "scheduleAlarms" -> {
                    try {
                        val argsJson = call.argument<String>("payload")
                            ?: call.argument<String>("args")
                            ?: throw IllegalArgumentException("payload/args must be a JSON string")
                        val json = JSONObject(argsJson)

                        val placedDate = json.getString("placedDate")
                        val stopFromDay = json.optInt("stopFromDay", 0)

                        // Parse slots map: { "morning": "08:30", "noon": "13:30", "evening": "20:30" }
                        val slotsJson = json.getJSONObject("slots")
                        val slots = mutableMapOf<String, String>()
                        slotsJson.keys().forEach { key -> slots[key] = slotsJson.getString(key) }

                        // Parse candlingDays list
                        val candlingJson = json.optJSONArray("candlingDays") ?: JSONArray()
                        val candlingDays = (0 until candlingJson.length()).map { candlingJson.getInt(it) }

                        val settings = AlarmSettings(placedDate, slots, stopFromDay, candlingDays)

                        // scheduleAll computes which alarms are needed for the
                        // next 7 days and registers them via AlarmManager.setAlarmClock().
                        AlarmScheduler.scheduleAll(applicationContext, settings)

                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SCHEDULE_ERROR", e.message, null)
                    }
                }

                // ----------------------------------------------------------------
                // cancelAlarms
                // Cancels all pending AlarmManager intents and clears the stored
                // request-code list from SharedPreferences.
                // ----------------------------------------------------------------
                "cancelAlarms" -> {
                    try {
                        AlarmScheduler.cancelAll(applicationContext)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("CANCEL_ERROR", e.message, null)
                    }
                }

                // ----------------------------------------------------------------
                // markSlotDone
                // Called from Flutter when the user logs rotation from within the
                // app (as opposed to the notification action button).
                // Args: date (String "yyyy-MM-dd"), slot (String slotKey)
                // ----------------------------------------------------------------
                "markSlotDone" -> {
                    try {
                        val date = call.argument<String>("date")
                            ?: throw IllegalArgumentException("date is required")
                        val slot = call.argument<String>("slot")
                            ?: throw IllegalArgumentException("slot is required")

                        // Key pattern: "done_<date>_<slot>" e.g. "done_2024-05-01_morning"
                        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        prefs.edit().putBoolean("done_${date}_${slot}", true).apply()

                        result.success(null)
                    } catch (e: Exception) {
                        result.error("MARK_DONE_ERROR", e.message, null)
                    }
                }

                // ----------------------------------------------------------------
                // checkPermissions
                // Returns Map<String, Boolean> so Flutter can show a permission
                // checklist to the user and guide them to fix any gaps.
                // Keys: notifications, exact_alarm, full_screen_intent, dnd_access,
                //       battery_optimization, autostart
                // ----------------------------------------------------------------
                "checkPermissions" -> {
                    try {
                        result.success(buildPermissionMap())
                    } catch (e: Exception) {
                        result.error("PERMISSION_CHECK_ERROR", e.message, null)
                    }
                }

                // ----------------------------------------------------------------
                // openPermissionSettings
                // Opens the correct system Settings screen for a given permission
                // key so the user can grant it without manually navigating menus.
                // Args: key (String)
                // ----------------------------------------------------------------
                "openPermissionSettings" -> {
                    try {
                        val key = call.argument<String>("key")
                            ?: throw IllegalArgumentException("key is required")
                        openSettingsForKey(key)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message, null)
                    }
                }

                // ----------------------------------------------------------------
                // syncContext
                // Syncs userName, userUid, and currentBatchId into hatcher_prefs
                // so native background components (AlarmActivity / RotateActionReceiver)
                // can write accurate Firestore records even when Flutter is closed.
                // ----------------------------------------------------------------
                "syncContext" -> {
                    try {
                        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        val editor = prefs.edit()
                        call.argument<String>("userName")?.let { editor.putString("user_name", it) }
                        call.argument<String>("userUid")?.let { editor.putString("user_uid", it) }
                        call.argument<String>("batchId")?.let { editor.putString("current_batch_id", it) }
                        editor.apply()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SYNC_ERROR", e.message, null)
                    }
                }

                // ----------------------------------------------------------------
                // Phase 2: Gateway Mode Methods
                // ----------------------------------------------------------------
                "startGatewayService" -> {
                    try {
                        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        prefs.edit().putBoolean("gateway_enabled", true).apply()
                        val gwIntent = Intent(this, GatewayService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(gwIntent)
                        } else {
                            startService(gwIntent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("GATEWAY_START_ERROR", e.message, null)
                    }
                }

                "stopGatewayService" -> {
                    try {
                        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        prefs.edit().putBoolean("gateway_enabled", false).apply()
                        stopService(Intent(this, GatewayService::class.java))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("GATEWAY_STOP_ERROR", e.message, null)
                    }
                }

                "isGatewayEnabled" -> {
                    val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    result.success(prefs.getBoolean("gateway_enabled", false))
                }

                "setGatewaySimSlot" -> {
                    val slot = call.argument<Int>("slotIndex") ?: 0
                    val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    prefs.edit().putInt("gateway_sim_slot", slot).apply()
                    result.success(null)
                }

                "getAvailableSims" -> {
                    result.success(getAvailableSimsList())
                }

                "checkGatewayPermissions" -> {
                    result.success(buildGatewayPermissionMap())
                }

                "requestGatewayPermissions" -> {
                    requestGatewayRuntimePermissions()
                    result.success(null)
                }

                "testGatewayCall" -> {
                    try {
                        val phone = call.argument<String>("phone")
                            ?: throw IllegalArgumentException("phone is required")
                        placeTestCall(phone)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("TEST_CALL_ERROR", e.message, null)
                    }
                }

                "testGatewaySms" -> {
                    try {
                        val phone = call.argument<String>("phone")
                            ?: throw IllegalArgumentException("phone is required")
                        val text = call.argument<String>("text")
                            ?: "Hatcher Gateway Test SMS"
                        sendTestSms(phone, text)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("TEST_SMS_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    // ============================================================
    //  Permission helpers
    // ============================================================

    /**
     * Builds a map of all permission states relevant to reliable alarm delivery.
     * Each key corresponds to a permission the app needs; Flutter renders a list
     * of check/cross badges based on this map.
     */
    private fun buildPermissionMap(): Map<String, Boolean> {
        val map = mutableMapOf<String, Boolean>()

        // 1. POST_NOTIFICATIONS (Android 13+, API 33)
        //    On older versions NotificationManagerCompat.areNotificationsEnabled()
        //    still works and returns false if the user disabled notifications at
        //    the app level in Settings → Apps → Hatcher → Notifications.
        map["notifications"] = NotificationManagerCompat.from(this).areNotificationsEnabled()

        // 2. SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM (Android 12+, API 31)
        //    Required to call AlarmManager.setAlarmClock().
        //    On older API levels exact alarms are always allowed.
        val alarmManager = getSystemService(ALARM_SERVICE) as AlarmManager
        map["exact_alarm"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            alarmManager.canScheduleExactAlarms()
        } else {
            true // Exact alarms unrestricted below API 31
        }

        // 3. USE_FULL_SCREEN_INTENT (Android 14+, API 34)
        //    Required to show AlarmActivity over the lock screen.
        //    On older versions this is implicitly allowed via the manifest permission.
        val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        map["full_screen_intent"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            notificationManager.canUseFullScreenIntent()
        } else {
            true // Full-screen intents always allowed below API 34
        }

        // 4. ACCESS_NOTIFICATION_POLICY — DND bypass
        //    Without this, STREAM_ALARM audio and high-priority notifications are
        //    suppressed during Do Not Disturb. The user must grant this in
        //    Settings → Apps → Special app access → Do Not Disturb access.
        map["dnd_access"] = notificationManager.isNotificationPolicyAccessGranted

        // 5. REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
        //    Without this, Android may kill our foreground service or delay
        //    alarm delivery on heavily optimized devices (Xiaomi, Samsung One UI).
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        map["battery_optimization"] = powerManager.isIgnoringBatteryOptimizations(packageName)

        // 6. Autostart (OEM-specific)
        //    Many Chinese OEMs (Xiaomi, OPPO, Vivo, Realme, OnePlus) have a
        //    proprietary "autostart" permission that must be granted manually.
        //    We detect it by checking if the manufacturer-specific settings
        //    Intent resolves on this device.
        map["autostart"] = checkAutostartPermission()

        return map
    }

    /**
     * Checks whether this device has an autostart settings screen and whether
     * it appears to be granted. Because autostart is not a standard Android API,
     * we can only detect the presence of the settings screen (via packageManager
     * .resolveActivity()), not the actual grant state. So we return true if
     * either (a) the device is not an OEM that requires it, or (b) the settings
     * Activity cannot be found (can't tell either way, default true).
     *
     * This is a best-effort check; true means "not definitively denied".
     */
    private fun checkAutostartPermission(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val autostartManufacturers = listOf("xiaomi", "oppo", "vivo", "realme", "oneplus")

        if (manufacturer !in autostartManufacturers) return true // No autostart restriction known

        val intent = buildAutostartIntent(manufacturer) ?: return true
        // If the intent resolves, the settings screen exists; we cannot read the
        // actual state so we return false to prompt the user to verify.
        val resolves = packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) != null
        return !resolves // If screen exists, we can't confirm granted → false to prompt user
    }

    // ============================================================
    //  Open Settings helpers
    // ============================================================

    /**
     * Opens the correct system Settings intent for the given permission key.
     * We use startActivity() with FLAG_ACTIVITY_NEW_TASK because we may be
     * calling this from a context where there's no task stack for Settings.
     */
    private fun openSettingsForKey(key: String) {
        val intent: Intent = when (key) {

            // App-level notification settings
            "notifications" -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }

            // Exact alarm permission settings (Android 12+ only)
            "exact_alarm" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = Uri.parse("package:$packageName")
                }
            } else {
                // Fallback to general app settings on older API levels
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                }
            }

            // Full-screen intent permission settings (Android 14+ only)
            "full_screen_intent" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                    data = Uri.parse("package:$packageName")
                }
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                }
            }

            // DND policy access — opens global DND access list (no per-app URI)
            "dnd_access" -> Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)

            // Battery optimization exemption
            "battery_optimization" -> Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }

            // OEM autostart — manufacturer-specific deep link
            "autostart" -> {
                val manufacturer = Build.MANUFACTURER.lowercase()
                buildAutostartIntent(manufacturer)
                    ?: Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    }
            }

            else -> throw IllegalArgumentException("Unknown permission key: $key")
        }

        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(intent)
        } catch (e: Exception) {
            // Fallback to general App Info settings if OEM activity cannot be launched
            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(fallback)
        }
    }

    /**
     * Returns a manufacturer-specific Intent that opens the autostart settings
     * screen, or null if the manufacturer is unknown / not in our list.
     *
     * These component names were sourced from community research and OEM docs.
     * They may change with OEM software updates — that's an inherent limitation
     * of relying on private OEM APIs.
     */
    private fun buildAutostartIntent(manufacturer: String): Intent? {
        return when (manufacturer) {
            "xiaomi" -> Intent().apply {
                // MIUI Security Center → Autostart management
                setClassName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"
                )
            }
            "oppo", "realme" -> Intent().apply {
                // ColorOS / Realme UI Security Center → Startup Manager
                setClassName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                )
            }
            "vivo" -> Intent().apply {
                // Vivo Permission Management → Background app management
                setClassName(
                    "com.vivo.permissionmanagement",
                    "com.vivo.permissionmanagement.activity.SoftPermissionDetailActivity"
                )
            }
            "oneplus" -> Intent().apply {
                // OxygenOS / ColorOS (post-merger) — same as OPPO for newer devices
                setClassName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                )
            }
            else -> null
        }
    }

    // ============================================================
    //  Phase 2: Gateway Permission, SIM & Test Helpers
    // ============================================================

    private fun buildGatewayPermissionMap(): Map<String, Boolean> {
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        return mapOf(
            "call_phone" to (ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED),
            "send_sms" to (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED),
            "read_phone_state" to (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED),
            "answer_phone_calls" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.checkSelfPermission(this, Manifest.permission.ANSWER_PHONE_CALLS) == PackageManager.PERMISSION_GRANTED
            } else true),
            "battery_optimization" to powerManager.isIgnoringBatteryOptimizations(packageName)
        )
    }

    private fun requestGatewayRuntimePermissions() {
        val perms = mutableListOf(
            Manifest.permission.CALL_PHONE,
            Manifest.permission.SEND_SMS,
            Manifest.permission.READ_PHONE_STATE
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            perms.add(Manifest.permission.ANSWER_PHONE_CALLS)
        }
        ActivityCompat.requestPermissions(this, perms.toTypedArray(), 2026)
    }

    @Suppress("MissingPermission")
    private fun getAvailableSimsList(): List<Map<String, Any>> {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            return emptyList()
        }
        val subMgr = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
        val list = subMgr.activeSubscriptionInfoList ?: return emptyList()
        return list.map { info ->
            mapOf(
                "slotIndex" to info.simSlotIndex,
                "displayName" to (info.displayName?.toString() ?: "SIM ${info.simSlotIndex + 1}"),
                "carrierName" to (info.carrierName?.toString() ?: "")
            )
        }
    }

    @Suppress("MissingPermission")
    private fun placeTestCall(phone: String) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("CALL_PHONE permission not granted")
        }
        val telecom = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val simSlot = prefs.getInt("gateway_sim_slot", 0)
        val extras = Bundle()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
            == PackageManager.PERMISSION_GRANTED
        ) {
            val accounts = telecom.callCapablePhoneAccounts
            val chosen = accounts.getOrNull(simSlot) ?: accounts.firstOrNull()
            if (chosen != null) {
                extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, chosen)
            }
        }
        telecom.placeCall(Uri.fromParts("tel", phone, null), extras)
    }

    @Suppress("MissingPermission", "DEPRECATION")
    private fun sendTestSms(phone: String, text: String) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("SEND_SMS permission not granted")
        }
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val simSlot = prefs.getInt("gateway_sim_slot", 0)
        var smsMgr: SmsManager? = null
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
            == PackageManager.PERMISSION_GRANTED
        ) {
            val subMgr = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            val activeSubs = subMgr.activeSubscriptionInfoList
            val subInfo = activeSubs?.firstOrNull { it.simSlotIndex == simSlot }
                ?: activeSubs?.firstOrNull()
            if (subInfo != null) {
                smsMgr = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    getSystemService(SmsManager::class.java).createForSubscriptionId(subInfo.subscriptionId)
                } else {
                    SmsManager.getSmsManagerForSubscriptionId(subInfo.subscriptionId)
                }
            }
        }
        val finalMgr = smsMgr ?: if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(SmsManager::class.java)
        } else {
            SmsManager.getDefault()
        }
        finalMgr.sendTextMessage(phone, null, text, null, null)
    }
}
