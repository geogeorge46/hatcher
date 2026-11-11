// lib/core/constants.dart
//
// App-wide constants for the Hatcher egg-incubation reminder app.
// All string keys and numeric defaults live here so they can be changed
// in one place and referenced across the entire codebase.

/// The name registered in MainActivity / AppDelegate for the Flutter
/// MethodChannel that bridges Dart ↔ Kotlin alarm scheduling logic.
const String kMethodChannel = 'hatcher/native';

/// IANA timezone identifier used throughout the app.
/// All Kolkata-time conversions rely on this string with the `timezone` package.
const String kTimezone = 'Asia/Kolkata';

// ---------------------------------------------------------------------------
// Rotation-slot keys  (stored in Firestore and local prefs)
// ---------------------------------------------------------------------------

/// Morning rotation slot identifier.
const String kSlotMorning = 'morning';

/// Noon rotation slot identifier.
const String kSlotNoon = 'noon';

/// Evening rotation slot identifier.
const String kSlotEvening = 'evening';

/// Ordered list of all three daily rotation slots.
/// The order determines display order in the UI and alarm scheduling order.
const List<String> kSlots = [kSlotMorning, kSlotNoon, kSlotEvening];

// ---------------------------------------------------------------------------
// Incubation parameters
// ---------------------------------------------------------------------------

/// Total incubation period in days (standard for chicken eggs).
const int kIncubationDays = 21;

/// Default day from which rotation reminders are suppressed ("lockdown" phase).
/// Users can override this in Settings.  0 means "never stop".
const int kDefaultStopFromDay = 18;

/// Default days on which a candling reminder notification is fired.
/// Day 7 checks for infertile eggs; Day 14 checks for late deaths.
const List<int> kDefaultCandlingDays = [7, 14];

/// Default snooze duration in minutes when the user taps "Snooze" on an alarm.
const int kDefaultSnoozeMinutes = 10;

/// Default repeat interval in minutes for missed-rotation follow-up alarms.
const int kDefaultRepeatMinutes = 10;

// ---------------------------------------------------------------------------
// Firestore collection / document names
// ---------------------------------------------------------------------------

/// Top-level Firestore collection that stores per-user profile documents.
/// Document ID = Firebase Auth UID.
const String kColUsers = 'users';

/// Top-level Firestore collection that stores egg-batch documents.
const String kColBatches = 'batches';

/// Sub-collection (under a batch doc) that stores individual rotation records.
const String kColRotations = 'rotations';

/// Document ID of the shared settings document inside the implicit
/// `settings` collection.  Full path: `settings/main`.
const String kDocSettings = 'main';

// ---------------------------------------------------------------------------
// User roster
// ---------------------------------------------------------------------------

/// Fixed list of household members who can claim a rotation.
/// Displayed in the name-picker on first launch and in alarm confirmation sheets.
const List<String> kUserNames = ['George', 'Dolly', 'Leo', 'Geo'];
