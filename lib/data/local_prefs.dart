// lib/data/local_prefs.dart
//
// Thin wrapper around shared_preferences for the Hatcher app.
//
// All keys are private string constants defined in this file.
// All public members are static so callers never need to hold an instance:
//   await LocalPrefs.init();
//   LocalPrefs.userName = 'George';
//   final name = LocalPrefs.userName;
//
// IMPORTANT: `LocalPrefs.init()` MUST be awaited in `main()` before any
// static getter or setter is called.  Calling a getter before init() will
// throw a [StateError].

import 'package:shared_preferences/shared_preferences.dart';

/// Static accessor for all locally-persisted preferences.
///
/// Usage:
/// ```dart
/// // In main():
/// await LocalPrefs.init();
///
/// // Anywhere else:
/// LocalPrefs.languageCode = 'ml';
/// final lang = LocalPrefs.languageCode; // 'ml'
/// ```
class LocalPrefs {
  LocalPrefs._(); // Static-only class; prevent instantiation.

  // ---------------------------------------------------------------------------
  // Preference keys  (keep in sync if you change them – existing installs
  // will lose data if key names change between versions).
  // ---------------------------------------------------------------------------

  static const _kLanguageCode = 'languageCode';
  static const _kUserName = 'userName';
  static const _kUserUid = 'userUid';
  static const _kFcmToken = 'fcmToken';

  /// Prefix for per-day, per-slot done flags.
  /// Full key: `'done_{date}_{slot}'` e.g. `'done_2025-06-01_morning'`
  static const _kDonePrefix = 'done_';

  // ---------------------------------------------------------------------------
  // Singleton prefs instance
  // ---------------------------------------------------------------------------

  static SharedPreferences? _prefs;

  /// Must be called (and awaited) in `main()` before the runApp() call.
  ///
  /// Initialises the [SharedPreferences] singleton that backs all subsequent
  /// static get/set calls.
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Returns the initialised [SharedPreferences] instance.
  /// Throws [StateError] if [init] has not been called yet.
  static SharedPreferences get _p {
    if (_prefs == null) {
      throw StateError(
        'LocalPrefs.init() must be awaited before accessing LocalPrefs.',
      );
    }
    return _prefs!;
  }

  // ---------------------------------------------------------------------------
  // Language
  // ---------------------------------------------------------------------------

  /// The BCP-47 language code selected by the user, e.g. `'ml'` or `'en'`.
  /// Returns `null` if the user has not yet selected a language (first launch).
  static String? get languageCode => _p.getString(_kLanguageCode);

  /// Persists the [value] language code (e.g. `'ml'`).
  static set languageCode(String? value) {
    if (value == null) {
      _p.remove(_kLanguageCode);
    } else {
      _p.setString(_kLanguageCode, value);
    }
  }

  // ---------------------------------------------------------------------------
  // User name
  // ---------------------------------------------------------------------------

  /// Display name selected on the name-picker screen.
  /// Returns `null` if the user has not yet picked a name.
  static String? get userName => _p.getString(_kUserName);

  /// Persists the user's display [name].
  static set userName(String? name) {
    if (name == null) {
      _p.remove(_kUserName);
    } else {
      _p.setString(_kUserName, name);
    }
  }

  // ---------------------------------------------------------------------------
  // User UID
  // ---------------------------------------------------------------------------

  /// Firebase Auth UID for the currently signed-in user.
  /// Returns `null` if anonymous sign-in has not completed yet.
  static String? get userUid => _p.getString(_kUserUid);

  /// Persists the Firebase Auth [uid].
  static set userUid(String? uid) {
    if (uid == null) {
      _p.remove(_kUserUid);
    } else {
      _p.setString(_kUserUid, uid);
    }
  }

  // ---------------------------------------------------------------------------
  // FCM token
  // ---------------------------------------------------------------------------

  /// The last-known FCM registration token for push notifications.
  /// Returns `null` if no token has been received yet.
  static String? get fcmToken => _p.getString(_kFcmToken);

  /// Persists the FCM [token].
  static set fcmToken(String? token) {
    if (token == null) {
      _p.remove(_kFcmToken);
    } else {
      _p.setString(_kFcmToken, token);
    }
  }

  // ---------------------------------------------------------------------------
  // Per-day slot done flags
  //
  // These flags are written immediately when the user taps "Rotated ✔" so the
  // alarm notification can be dismissed even before Firestore confirms the
  // write.  They are reset daily by [clearTodaySlots].
  // ---------------------------------------------------------------------------

  /// Marks a specific slot as done in local prefs.
  ///
  /// [date] – 'yyyy-MM-dd' in Kolkata time.
  /// [slot] – One of 'morning', 'noon', 'evening'.
  static Future<void> markSlotDone(String date, String slot) async {
    await _p.setString('${_kDonePrefix}${date}_$slot', 'true');
  }

  /// Returns `true` if the given slot has been locally marked as done.
  ///
  /// [date] – 'yyyy-MM-dd' in Kolkata time.
  /// [slot] – One of 'morning', 'noon', 'evening'.
  static bool isSlotDone(String date, String slot) {
    return _p.getString('${_kDonePrefix}${date}_$slot') == 'true';
  }

  /// Removes the done flags for all three slots on the given [date].
  ///
  /// Call this at app startup when [date] has rolled over (i.e. a new Kolkata
  /// calendar day has begun) to prevent stale flags from hiding missed-rotation
  /// indicators.
  ///
  /// [date] – 'yyyy-MM-dd' in Kolkata time.
  static Future<void> clearTodaySlots(String date) async {
    await Future.wait([
      _p.remove('${_kDonePrefix}${date}_morning'),
      _p.remove('${_kDonePrefix}${date}_noon'),
      _p.remove('${_kDonePrefix}${date}_evening'),
    ]);
  }
}
