// lib/core/method_channel.dart
//
// Dart-side MethodChannel bridge between Flutter and the Kotlin
// HatcherAlarmPlugin in the Android host app.
//
// All communication goes through the channel named 'hatcher/native'.
// Method names, argument keys, and return-value keys must stay in sync with
// the corresponding Kotlin handler in MainActivity / HatcherPlugin.kt.

import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/services.dart';

import 'constants.dart';

/// Provides typed wrappers around every MethodChannel call that the Flutter
/// side makes into the Kotlin alarm-scheduling layer.
///
/// Every public method is `static` so callers never need to instantiate this
/// class – usage: `await HatcherChannel.scheduleAlarms(...)`.
class HatcherChannel {
  HatcherChannel._(); // Prevent instantiation.

  /// The bidirectional MethodChannel shared with Kotlin.
  /// The channel name must match the string registered in MainActivity.kt.
  static const MethodChannel _channel = MethodChannel(kMethodChannel);

  // ---------------------------------------------------------------------------
  // Alarm scheduling
  // ---------------------------------------------------------------------------

  /// Sends all the data the Kotlin layer needs to schedule (or re-schedule)
  /// the full set of daily rotation alarms for the current batch.
  ///
  /// Parameters
  /// ----------
  /// [placedDate]   – 'yyyy-MM-dd' string; Day 1 of the incubation period.
  /// [slots]        – Map of slot key → 24-hour time string, e.g.
  ///                  `{'morning': '08:30', 'noon': '13:30', 'evening': '20:30'}`.
  /// [stopFromDay]  – Day number (1-based) from which alarms are suppressed.
  ///                  Pass 0 to never suppress ("never stop" setting).
  /// [candlingDays] – List of day numbers on which a candling-reminder
  ///                  notification should fire (e.g. [7, 14]).
  ///
  /// The Kotlin side receives a JSON-encoded string under key `'payload'`.
  /// It is responsible for converting slot times into exact AlarmManager
  /// triggers for every remaining day of the 21-day cycle.
  static Future<void> scheduleAlarms({
    required String placedDate,
    required Map<String, String> slots,
    required int stopFromDay,
    required List<int> candlingDays,
  }) async {
    final payload = jsonEncode({
      'placedDate': placedDate,
      'slots': slots,
      'stopFromDay': stopFromDay,
      'candlingDays': candlingDays,
    });

    try {
      await _channel.invokeMethod<void>('scheduleAlarms', {'payload': payload});
      dev.log('HatcherChannel: scheduleAlarms sent – placedDate=$placedDate',
          name: 'HatcherChannel');
    } on PlatformException catch (e) {
      dev.log(
        'HatcherChannel: scheduleAlarms failed – code=${e.code} '
        'message=${e.message} details=${e.details}',
        name: 'HatcherChannel',
        level: 1000, // Level.SEVERE
      );
      // Re-throw so callers can display an appropriate error UI.
      rethrow;
    }
  }

  /// Cancels **all** pending rotation and candling alarms for the current batch.
  ///
  /// Call this when:
  ///   • The user manually ends a batch.
  ///   • A new batch is started (old alarms must be cleared first).
  ///   • The user disables alarms in Settings.
  ///
  /// The Kotlin side iterates over every alarm ID it registered and calls
  /// `AlarmManager.cancel()` for each one.
  static Future<void> cancelAlarms() async {
    try {
      await _channel.invokeMethod<void>('cancelAlarms');
      dev.log('HatcherChannel: cancelAlarms sent', name: 'HatcherChannel');
    } on PlatformException catch (e) {
      dev.log(
        'HatcherChannel: cancelAlarms failed – code=${e.code} '
        'message=${e.message}',
        name: 'HatcherChannel',
        level: 1000,
      );
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Local slot-done marking (used from the alarm notification itself)
  // ---------------------------------------------------------------------------

  /// Tells the Kotlin layer that a specific slot has been marked done so it
  /// can cancel any snoozed / repeating follow-up alarms for that slot.
  ///
  /// [date] – 'yyyy-MM-dd' in Kolkata time.
  /// [slot] – One of 'morning', 'noon', 'evening'.
  ///
  /// This call is *fire-and-forget* from the UI layer; the authoritative
  /// done-state is recorded in Firestore via [FirestoreService.addRotation].
  static Future<void> markSlotDoneLocally({
    required String date,
    required String slot,
  }) async {
    try {
      await _channel.invokeMethod<void>(
        'markSlotDone',
        {'date': date, 'slot': slot},
      );
      dev.log('HatcherChannel: markSlotDone date=$date slot=$slot',
          name: 'HatcherChannel');
    } on PlatformException catch (e) {
      dev.log(
        'HatcherChannel: markSlotDone failed – code=${e.code} '
        'message=${e.message}',
        name: 'HatcherChannel',
        level: 1000,
      );
      // Non-fatal – Firestore is the source of truth; just log and continue.
    }
  }

  // ---------------------------------------------------------------------------
  // Permission introspection
  // ---------------------------------------------------------------------------

  /// Queries the Kotlin layer for the current status of every permission the
  /// app requires to reliably deliver alarms.
  ///
  /// Returns a map keyed by permission identifier:
  /// ```
  /// {
  ///   'notifications': true,
  ///   'exactAlarm':    true,
  ///   'fullscreen':    false,
  ///   'dnd':           false,
  ///   'battery':       true,
  ///   'autostart':     true,   // always true on non-OEM devices
  /// }
  /// ```
  /// Values are `true` when the permission is granted / not needed.
  ///
  /// The SetupChecklistScreen uses this map to show which items still need
  /// user action.
  static Future<Map<String, bool>> checkPermissions() async {
    try {
      final raw = await _channel.invokeMethod<Map>('checkPermissions');
      if (raw == null) return {};
      // Kotlin returns Map<String, Boolean>; cast each value to bool.
      return raw.map(
        (key, value) => MapEntry(key.toString(), value == true),
      );
    } on PlatformException catch (e) {
      dev.log(
        'HatcherChannel: checkPermissions failed – code=${e.code} '
        'message=${e.message}',
        name: 'HatcherChannel',
        level: 1000,
      );
      return {}; // Fail open; the UI will show all items as needing attention.
    }
  }

  // ---------------------------------------------------------------------------
  // Permission settings deep-links
  // ---------------------------------------------------------------------------

  /// Asks the Kotlin layer to open the appropriate system-settings screen for
  /// the given [permissionKey].
  ///
  /// Valid keys (must match the Kotlin switch/when expression):
  /// - `'notifications'` → App notification settings
  /// - `'exactAlarm'`    → "Alarms & reminders" (Android 12+)
  /// - `'fullscreen'`    → Display-over-other-apps / USE_FULL_SCREEN_INTENT
  /// - `'dnd'`           → Notification-policy / DND access
  /// - `'battery'`       → Battery optimisation exemption
  /// - `'autostart'`     → OEM-specific autostart page (best-effort)
  static Future<void> openPermissionSettings(String permissionKey) async {
    try {
      await _channel.invokeMethod<void>(
        'openPermissionSettings',
        {'key': permissionKey},
      );
      dev.log(
        'HatcherChannel: openPermissionSettings key=$permissionKey',
        name: 'HatcherChannel',
      );
    } on PlatformException catch (e) {
      dev.log(
        'HatcherChannel: openPermissionSettings failed – code=${e.code} '
        'message=${e.message}',
        name: 'HatcherChannel',
        level: 1000,
      );
      // Non-fatal; the user can navigate manually if the deep-link fails.
    }
  }

  /// Syncs user context and active batch ID to native Android SharedPreferences
  /// (`hatcher_prefs`) so background alarm receivers can write accurate Firestore
  /// records even when Flutter is terminated.
  static Future<void> syncContext({
    String? userName,
    String? userUid,
    String? batchId,
  }) async {
    try {
      await _channel.invokeMethod<void>('syncContext', {
        if (userName != null) 'userName': userName,
        if (userUid != null) 'userUid': userUid,
        if (batchId != null) 'batchId': batchId,
      });
    } on PlatformException catch (e) {
      dev.log(
        'HatcherChannel: syncContext failed – code=${e.code} message=${e.message}',
        name: 'HatcherChannel',
      );
    }
  }

  /// Sets or clears the muted date ('yyyy-MM-dd') in native Android prefs.
  /// When set to today's date, native AlarmReceiver and AlarmService suppress
  /// all alarms and notifications, and dismiss any currently ringing alarm.
  static Future<void> setMutedDate(String? date) async {
    try {
      await _channel.invokeMethod<void>('setMutedDate', {'date': date ?? ''});
      dev.log('HatcherChannel: setMutedDate date=$date', name: 'HatcherChannel');
    } on PlatformException catch (e) {
      dev.log(
        'HatcherChannel: setMutedDate failed – code=${e.code} message=${e.message}',
        name: 'HatcherChannel',
      );
    }
  }

  /// Requests the POST_NOTIFICATIONS runtime permission on Android 13+ (API 33+).
  static Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } on PlatformException catch (e) {
      dev.log(
        'HatcherChannel: requestNotificationPermission failed – code=${e.code} message=${e.message}',
        name: 'HatcherChannel',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Phase 2: Gateway Mode & Telecom / SMS
  // ---------------------------------------------------------------------------

  static Future<bool> startGatewayService() async {
    try {
      final ok = await _channel.invokeMethod<bool>('startGatewayService');
      return ok == true;
    } on PlatformException catch (e) {
      dev.log('HatcherChannel: startGatewayService failed – ${e.message}');
      rethrow;
    }
  }

  static Future<bool> stopGatewayService() async {
    try {
      final ok = await _channel.invokeMethod<bool>('stopGatewayService');
      return ok == true;
    } on PlatformException catch (e) {
      dev.log('HatcherChannel: stopGatewayService failed – ${e.message}');
      rethrow;
    }
  }

  static Future<bool> isGatewayEnabled() async {
    try {
      final enabled = await _channel.invokeMethod<bool>('isGatewayEnabled');
      return enabled == true;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> setGatewaySimSlot(int slotIndex) async {
    try {
      await _channel.invokeMethod<void>('setGatewaySimSlot', {
        'slotIndex': slotIndex,
      });
    } on PlatformException catch (e) {
      dev.log('HatcherChannel: setGatewaySimSlot failed – ${e.message}');
    }
  }

  static Future<List<Map<String, dynamic>>> getAvailableSims() async {
    try {
      final raw = await _channel.invokeMethod<List>('getAvailableSims');
      if (raw == null) return [];
      return raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } on PlatformException {
      return [];
    }
  }

  static Future<Map<String, bool>> checkGatewayPermissions() async {
    try {
      final raw = await _channel.invokeMethod<Map>('checkGatewayPermissions');
      if (raw == null) return {};
      return raw.map((k, v) => MapEntry(k.toString(), v == true));
    } on PlatformException {
      return {};
    }
  }

  static Future<void> requestGatewayPermissions() async {
    try {
      await _channel.invokeMethod<void>('requestGatewayPermissions');
    } on PlatformException catch (e) {
      dev.log('HatcherChannel: requestGatewayPermissions failed – ${e.message}');
    }
  }

  static Future<void> testGatewayCall(String phone) async {
    try {
      await _channel.invokeMethod<bool>('testGatewayCall', {'phone': phone});
    } on PlatformException catch (e) {
      dev.log('HatcherChannel: testGatewayCall failed – ${e.message}');
      rethrow;
    }
  }

  static Future<void> testGatewaySms(String phone, String text) async {
    try {
      await _channel.invokeMethod<bool>('testGatewaySms', {
        'phone': phone,
        'text': text,
      });
    } on PlatformException catch (e) {
      dev.log('HatcherChannel: testGatewaySms failed – ${e.message}');
      rethrow;
    }
  }
}
