import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../core/extensions.dart';
import 'batch_provider.dart';
import 'settings_provider.dart';

// ---------------------------------------------------------------------------
// Pure testable helper functions
// ---------------------------------------------------------------------------

/// Computes the 1-based incubation day given [placedDateStr] ('yyyy-MM-dd')
/// and [nowKolkataDateTime] in Kolkata timezone.
/// Day 1 = placedDate. Clamped at minimum 1.
int computeIncubationDay(String placedDateStr, DateTime nowKolkataDateTime) {
  final placed = placedDateStr.toKolkataDateTime();
  final placedMidnight = DateTime(placed.year, placed.month, placed.day);
  final nowMidnight = DateTime(
    nowKolkataDateTime.year,
    nowKolkataDateTime.month,
    nowKolkataDateTime.day,
  );
  final diffDays = nowMidnight.difference(placedMidnight).inDays;
  final day = diffDays + 1;
  return day < 1 ? 1 : day;
}

/// Computes the expected hatch date from [placedDateStr] ('yyyy-MM-dd').
/// Hatch day = placedDate + 21 days (or +20 depending on day 1 vs 21-day cycle;
/// per spec: "hatch date (placed + 21 days)").
DateTime computeHatchDate(String placedDateStr) {
  final placed = placedDateStr.toKolkataDateTime();
  return placed.add(const Duration(days: kIncubationDays));
}

/// Returns true if [day] is in the lockdown period (no daily alarms).
/// If [stopFromDay] <= 0, lockdown never activates.
bool isLockdownDay({required int day, required int stopFromDay}) {
  if (stopFromDay <= 0) return false;
  return day >= stopFromDay;
}

// ---------------------------------------------------------------------------
// Riverpod Providers
// ---------------------------------------------------------------------------

/// Computes the current incubation day number (1-based, clamped 1..21 for display).
final dayCounterProvider = Provider<int?>((ref) {
  final batchAsync = ref.watch(activeBatchProvider);
  return batchAsync.whenOrNull(data: (batch) {
    if (batch == null) return null;
    final day = computeIncubationDay(batch.placedDate, nowKolkata());
    return day.clamp(1, kIncubationDays);
  });
}, name: 'dayCounterProvider');

/// True when rotation reminders should stop (lockdown period, e.g. day >= 18).
final isLockdownProvider = Provider<bool>((ref) {
  final day = ref.watch(dayCounterProvider);
  if (day == null) return false;

  final settingsAsync = ref.watch(settingsProvider);
  return settingsAsync.whenOrNull(data: (settings) {
        return isLockdownDay(
          day: day,
          stopFromDay: settings.stopRemindersFromDay,
        );
      }) ??
      false;
}, name: 'isLockdownProvider');

/// Expected hatch date formatted as "d MMM yyyy".
final hatchDateProvider = Provider<String?>((ref) {
  final batchAsync = ref.watch(activeBatchProvider);
  return batchAsync.whenOrNull(data: (batch) {
    if (batch == null) return null;
    final hatchDate = computeHatchDate(batch.placedDate);
    return DateFormat('d MMM yyyy').format(hatchDate);
  });
}, name: 'hatchDateProvider');
