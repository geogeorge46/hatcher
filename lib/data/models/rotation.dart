// lib/data/models/rotation.dart
//
// Immutable data model representing a single egg-rotation event.
//
// A rotation document lives in Firestore at:
//   rotations/{rotationId}
//
// where rotationId is deterministic: '{yyyy-MM-dd}_{slot}'
// (e.g. '2025-06-01_morning').  Using a deterministic ID lets us use
// `setDoc` with merge semantics and prevents duplicate entries via
// Firestore transaction checks.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/constants.dart';

/// Represents one completed egg-rotation event for a specific slot on a
/// specific day, as stored in Firestore.
class Rotation {
  /// Firestore document ID in the format `'yyyy-MM-dd_slot'`.
  /// Example: `'2025-06-01_morning'`.
  final String id;

  /// Kolkata-timezone date string ('yyyy-MM-dd') for the day of this rotation.
  final String date;

  /// Slot key: one of 'morning', 'noon', 'evening'.
  final String slot;

  /// Display name of the household member who performed the rotation.
  final String doneBy;

  /// Firebase Auth UID of the user who performed the rotation.
  /// Used to guard the undo action (only the author can undo within 10 min).
  final String doneByUid;

  /// Firestore server timestamp set when the rotation document was written.
  /// Used for the 10-minute undo window and for display in the history screen.
  final Timestamp doneAt;

  /// ID of the [Batch] this rotation belongs to.
  /// Used for filtering in the history screen.
  final String batchId;

  const Rotation({
    required this.id,
    required this.date,
    required this.slot,
    required this.doneBy,
    required this.doneByUid,
    required this.doneAt,
    required this.batchId,
  });

  // ---------------------------------------------------------------------------
  // Firestore ↔ Dart conversion
  // ---------------------------------------------------------------------------

  /// Constructs a [Rotation] from a Firestore [DocumentSnapshot].
  factory Rotation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Rotation(
      id: doc.id,
      date: data['date'] as String,
      slot: data['slot'] as String,
      doneBy: data['doneBy'] as String,
      doneByUid: data['doneByUid'] as String,
      doneAt: data['doneAt'] as Timestamp,
      batchId: data['batchId'] as String,
    );
  }

  /// Serialises this [Rotation] to a plain Dart map suitable for Firestore.
  ///
  /// [id] is excluded because it is used as the document path, not stored
  /// inside the document body.
  Map<String, dynamic> toMap() => {
        'date': date,
        'slot': slot,
        'doneBy': doneBy,
        'doneByUid': doneByUid,
        'doneAt': doneAt,
        'batchId': batchId,
      };

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Formats [doneAt] as `'h:mm a'` (e.g. `'8:30 AM'`) in [timezone].
  ///
  /// [timezone] should be [kTimezone] (`'Asia/Kolkata'`) for all in-app
  /// display, but is kept as a parameter to simplify unit testing with
  /// different zones.
  String formattedTime(String timezone) {
    final location = tz.getLocation(timezone);
    // Convert the UTC epoch from Timestamp to a TZDateTime in the target zone.
    final tzDateTime = tz.TZDateTime.fromMillisecondsSinceEpoch(
      location,
      doneAt.millisecondsSinceEpoch,
    );
    return DateFormat('h:mm a').format(tzDateTime);
  }

  @override
  String toString() =>
      'Rotation(id=$id, date=$date, slot=$slot, doneBy=$doneBy)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Rotation && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
