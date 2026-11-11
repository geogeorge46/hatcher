// lib/core/extensions.dart
//
// DateTime / String extension methods for Kolkata-timezone conversions and
// formatting helpers used throughout the Hatcher app.
//
// All conversions depend on the `timezone` package being initialised before
// use.  Call `tz.initializeTimeZones()` (and optionally
// `tz.setLocalLocation(...)`) in main() before any extension is invoked.

import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import 'constants.dart';

// ---------------------------------------------------------------------------
// Top-level helper
// ---------------------------------------------------------------------------

/// Returns the current moment expressed as a [DateTime] in the
/// Asia/Kolkata timezone.
///
/// Unlike `DateTime.now()` (which uses the device local timezone),
/// this always reflects IST regardless of the device's system clock setting.
DateTime nowKolkata() {
  final kolkata = tz.getLocation(kTimezone);
  return tz.TZDateTime.now(kolkata);
}

// ---------------------------------------------------------------------------
// DateTime extensions
// ---------------------------------------------------------------------------

extension DateTimeKolkataX on DateTime {
  /// Converts this [DateTime] to a [tz.TZDateTime] in Asia/Kolkata.
  ///
  /// If this instance is already a [tz.TZDateTime] in Kolkata the value is
  /// returned as-is.  Otherwise the UTC representation is used for conversion
  /// so that both UTC and local-timezone DateTimes are handled correctly.
  tz.TZDateTime toKolkata() {
    final kolkata = tz.getLocation(kTimezone);
    if (this is tz.TZDateTime) {
      final tzt = this as tz.TZDateTime;
      if (tzt.location == kolkata) return tzt;
    }
    // Convert via UTC to avoid double-offset bugs.
    return tz.TZDateTime.from(toUtc(), kolkata);
  }

  /// Returns the date portion of this [DateTime] as a 'yyyy-MM-dd' string
  /// evaluated in Asia/Kolkata.
  ///
  /// Use this whenever you need a stable date key for Firestore documents or
  /// SharedPreferences keys (e.g. `'done_2025-06-01_morning'`).
  String kolkataDate() {
    final kdt = toKolkata();
    return DateFormat('yyyy-MM-dd').format(kdt);
  }

  /// Returns a localised human label for a given rotation [slot] key.
  ///
  /// For fully locale-aware labels use the ARB strings via AppLocalizations;
  /// this method is a convenience for contexts where BuildContext is unavailable
  /// (e.g., notification payload building in background isolates).
  String slotLabel(String slot) {
    switch (slot) {
      case 'morning':
        return 'Morning';
      case 'noon':
        return 'Noon';
      case 'evening':
        return 'Evening';
      default:
        return slot;
    }
  }

  /// Formats this [DateTime] as `'h:mm a'` (e.g. `'8:30 AM'`).
  ///
  /// The formatting is done in the system locale but the time value itself
  /// should already be in the desired timezone before calling this method.
  String formatTime() => DateFormat('h:mm a').format(this);

  /// Returns `true` when both this and [other], converted to Kolkata time,
  /// fall on the same calendar day (year + month + day match).
  bool isSameKolkataDay(DateTime other) {
    final a = toKolkata();
    final b = other.toKolkata();
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

// ---------------------------------------------------------------------------
// String extensions
// ---------------------------------------------------------------------------

extension StringKolkataX on String {
  /// Parses a 'yyyy-MM-dd' date string and returns a [tz.TZDateTime] at
  /// **midnight (00:00:00)** in Asia/Kolkata on that date.
  ///
  /// Throws a [FormatException] if the string is not in 'yyyy-MM-dd' format.
  ///
  /// Example:
  /// ```dart
  /// final midnight = '2025-06-01'.toKolkataDateTime();
  /// ```
  tz.TZDateTime toKolkataDateTime() {
    final kolkata = tz.getLocation(kTimezone);
    final parts = split('-');
    if (parts.length != 3) {
      throw FormatException('Expected yyyy-MM-dd, got: $this');
    }
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    // tz.TZDateTime constructor uses the wall-clock time in the given location,
    // so this correctly produces midnight IST rather than midnight UTC.
    return tz.TZDateTime(kolkata, year, month, day);
  }
}
