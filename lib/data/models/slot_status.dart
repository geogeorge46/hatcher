// lib/data/models/slot_status.dart
//
// Pure business-logic for computing the display status of a rotation slot.
//
// This file intentionally has zero Flutter / Firebase imports so the logic can
// be unit-tested without a full widget environment.

import 'rotation.dart';

// ---------------------------------------------------------------------------
// Enum
// ---------------------------------------------------------------------------

/// The four possible states a rotation slot can be in at any given moment.
///
/// The UI maps each value to a distinct colour and label:
///   - [pending] → grey / "Pending"
///   - [late]    → amber / "Late"
///   - [missed]  → red   / "Missed"
///   - [done]    → green / "Done by {name}, {time}"
enum SlotStatus { pending, late, missed, done }

// ---------------------------------------------------------------------------
// Pure computation function
// ---------------------------------------------------------------------------

/// Determines the [SlotStatus] for one slot on the **current day** in Kolkata.
///
/// Parameters
/// ----------
/// [rotation]         – The [Rotation] record for this slot if it exists, or
///                      `null` if no one has rotated yet.
/// [slotTimeStr]      – The scheduled alarm time for this slot as `'HH:mm'`
///                      (24-hour), e.g. `'08:30'`.
/// [nextSlotTimeStr]  – The scheduled alarm time of the **next** slot as
///                      `'HH:mm'`, or `null` if this is the last slot of the
///                      day (evening).
/// [nowKolkata]       – The current moment in Kolkata timezone.
///                      Pass [nowKolkata()] from extensions.dart.
///
/// Status rules
/// ------------
/// 1. If [rotation] is non-null → [SlotStatus.done]  (someone already rotated)
/// 2. If [nowKolkata] is before the slot's scheduled time → [SlotStatus.pending]
/// 3. If [nextSlotTimeStr] is non-null and [nowKolkata] is before the next
///    slot's time → [SlotStatus.late]  (overdue but not yet superseded)
/// 4. If [nextSlotTimeStr] is non-null and [nowKolkata] is at or after the
///    next slot's time → [SlotStatus.missed]
/// 5. For the last slot of the day ([nextSlotTimeStr] == null):
///    - If [nowKolkata] is before 23:59:59 → [SlotStatus.late]
///    - At or after 23:59:59 → [SlotStatus.missed]
SlotStatus computeSlotStatus({
  required Rotation? rotation,
  required String slotTimeStr,
  required String? nextSlotTimeStr,
  required DateTime nowKolkata,
}) {
  // Rule 1: already done.
  if (rotation != null) return SlotStatus.done;

  // Parse slot time into a DateTime on today's Kolkata date.
  final slotTime = _parseTimeOnDate(slotTimeStr, nowKolkata);

  // Rule 2: not yet reached the slot's scheduled time.
  if (nowKolkata.isBefore(slotTime)) return SlotStatus.pending;

  // Rules 3 & 4: past the slot time – decide between late and missed.
  if (nextSlotTimeStr != null) {
    // There is a next slot; use its start time as the boundary.
    final nextSlotTime = _parseTimeOnDate(nextSlotTimeStr, nowKolkata);
    if (nowKolkata.isBefore(nextSlotTime)) {
      return SlotStatus.late; // Overdue but next slot hasn't started yet.
    } else {
      return SlotStatus.missed; // Next slot has already started – definitely missed.
    }
  }

  // Rule 5: this is the last slot of the day (evening).
  // Use 23:59:59 as the end-of-day boundary.
  final endOfDay = DateTime(
    nowKolkata.year,
    nowKolkata.month,
    nowKolkata.day,
    23,
    59,
    59,
  );
  if (nowKolkata.isBefore(endOfDay)) {
    return SlotStatus.late; // Still within the same day – technically recoverable.
  } else {
    return SlotStatus.missed; // Day has ended without a rotation.
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Parses a `'HH:mm'` time string and returns a [DateTime] set to that
/// hour and minute on the **same calendar day** as [referenceDate].
///
/// [referenceDate] should already be in Kolkata timezone so the resulting
/// DateTime is on the correct Kolkata date.
DateTime _parseTimeOnDate(String timeStr, DateTime referenceDate) {
  final parts = timeStr.split(':');
  if (parts.length != 2) {
    throw FormatException('Expected HH:mm time string, got: $timeStr');
  }
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);
  return DateTime(
    referenceDate.year,
    referenceDate.month,
    referenceDate.day,
    hour,
    minute,
  );
}
