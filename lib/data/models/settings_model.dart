// lib/data/models/settings_model.dart
//
// Immutable settings model for the Hatcher app.
//
// Settings are stored as a single Firestore document at:
//   settings/main
//
// and are shared across all four phones in the household.  Any phone can
// change the settings; every other phone receives the update via the
// real-time snapshot stream in [FirestoreService.watchSettings].

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants.dart';

/// Holds all user-configurable alarm and incubation settings.
///
/// All fields are immutable; use [copyWith] to produce modified copies before
/// writing back to Firestore.
class SettingsModel {
  /// Map of slot key → 24-hour time string.
  ///
  /// Keys are always exactly the three values in [kSlots]:
  ///   `'morning'`, `'noon'`, `'evening'`.
  ///
  /// Example: `{'morning': '08:30', 'noon': '13:30', 'evening': '20:30'}`
  final Map<String, String> slots;

  /// The day number (1-based, inclusive) from which rotation alarms are
  /// suppressed to allow the eggs to settle ("lockdown" period).
  ///
  /// Special value `0` means "never stop" – alarms fire every day until
  /// hatching day.
  ///
  /// Typical value: `18` (suppress on days 18-21).
  final int stopRemindersFromDay;

  /// List of day numbers (1-based) on which a candling-reminder notification
  /// is sent.  Standard values: `[7, 14]`.
  final List<int> candlingDays;

  /// Duration in minutes to delay the alarm when the user taps "Snooze".
  final int snoozeMinutes;

  /// Interval in minutes between automatic repeat alarms after a slot time
  /// has passed without a rotation being logged.
  final int repeatMinutes;

  const SettingsModel({
    required this.slots,
    required this.stopRemindersFromDay,
    required this.candlingDays,
    required this.snoozeMinutes,
    required this.repeatMinutes,
  });

  // ---------------------------------------------------------------------------
  // Default factory
  // ---------------------------------------------------------------------------

  /// Returns a [SettingsModel] pre-filled with sensible defaults.
  ///
  /// Used as the fallback when the Firestore settings document does not yet
  /// exist (first launch before any phone has saved settings).
  factory SettingsModel.defaults() => SettingsModel(
        slots: const {
          kSlotMorning: '08:30',
          kSlotNoon: '13:30',
          kSlotEvening: '20:30',
        },
        stopRemindersFromDay: kDefaultStopFromDay,
        candlingDays: List<int>.from(kDefaultCandlingDays),
        snoozeMinutes: kDefaultSnoozeMinutes,
        repeatMinutes: kDefaultRepeatMinutes,
      );

  // ---------------------------------------------------------------------------
  // Firestore ↔ Dart conversion
  // ---------------------------------------------------------------------------

  /// Constructs a [SettingsModel] from a Firestore [DocumentSnapshot].
  ///
  /// Falls back to default values for any missing fields so the app remains
  /// functional even if the document is partially written.
  factory SettingsModel.fromFirestore(DocumentSnapshot doc) {
    final defaults = SettingsModel.defaults();
    final data = doc.data() as Map<String, dynamic>? ?? {};

    // Parse the slots map; keep only the three known keys.
    final rawSlots = data['slots'] as Map<String, dynamic>?;
    final Map<String, String> slots = rawSlots != null
        ? {
            kSlotMorning:
                rawSlots[kSlotMorning] as String? ?? defaults.slots[kSlotMorning]!,
            kSlotNoon:
                rawSlots[kSlotNoon] as String? ?? defaults.slots[kSlotNoon]!,
            kSlotEvening:
                rawSlots[kSlotEvening] as String? ?? defaults.slots[kSlotEvening]!,
          }
        : Map<String, String>.from(defaults.slots);

    // Parse candlingDays; Firestore stores lists as List<dynamic>.
    final rawCandling = data['candlingDays'] as List<dynamic>?;
    final candlingDays = rawCandling != null
        ? rawCandling.map((e) => (e as num).toInt()).toList()
        : List<int>.from(defaults.candlingDays);

    return SettingsModel(
      slots: slots,
      stopRemindersFromDay:
          (data['stopRemindersFromDay'] as num?)?.toInt() ??
              defaults.stopRemindersFromDay,
      candlingDays: candlingDays,
      snoozeMinutes:
          (data['snoozeMinutes'] as num?)?.toInt() ?? defaults.snoozeMinutes,
      repeatMinutes:
          (data['repeatMinutes'] as num?)?.toInt() ?? defaults.repeatMinutes,
    );
  }

  /// Serialises this [SettingsModel] to a plain Dart map for Firestore.
  Map<String, dynamic> toMap() => {
        'slots': Map<String, String>.from(slots),
        'stopRemindersFromDay': stopRemindersFromDay,
        'candlingDays': List<int>.from(candlingDays),
        'snoozeMinutes': snoozeMinutes,
        'repeatMinutes': repeatMinutes,
      };

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  /// Returns a copy of this [SettingsModel] with the specified fields replaced.
  SettingsModel copyWith({
    Map<String, String>? slots,
    int? stopRemindersFromDay,
    List<int>? candlingDays,
    int? snoozeMinutes,
    int? repeatMinutes,
  }) {
    return SettingsModel(
      slots: slots ?? Map<String, String>.from(this.slots),
      stopRemindersFromDay:
          stopRemindersFromDay ?? this.stopRemindersFromDay,
      candlingDays:
          candlingDays ?? List<int>.from(this.candlingDays),
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      repeatMinutes: repeatMinutes ?? this.repeatMinutes,
    );
  }

  @override
  String toString() =>
      'SettingsModel(slots=$slots, stopFromDay=$stopRemindersFromDay, '
      'candling=$candlingDays, snooze=$snoozeMinutes, repeat=$repeatMinutes)';
}
