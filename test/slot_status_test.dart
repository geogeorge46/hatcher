import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatcher/data/models/rotation.dart';
import 'package:hatcher/data/models/slot_status.dart';

void main() {
  group('Slot Status Rules', () {
    final mockRotation = Rotation(
      id: '2026-11-10_morning',
      date: '2026-11-10',
      slot: 'morning',
      doneBy: 'Geo',
      doneByUid: 'uid-geo',
      doneAt: Timestamp.fromDate(DateTime(2026, 11, 10, 8, 35)),
      batchId: 'batch-1',
    );

    test('Returns pending before scheduled slot time', () {
      final now = DateTime(2026, 11, 10, 8, 29); // 1 min before 08:30
      final status = computeSlotStatus(
        rotation: null,
        slotTimeStr: '08:30',
        nextSlotTimeStr: '13:30',
        nowKolkata: now,
      );
      expect(status, equals(SlotStatus.pending));
    });

    test('Returns late at or after scheduled slot time before next slot', () {
      final nowAtExact = DateTime(2026, 11, 10, 8, 30);
      final nowDuringWindow = DateTime(2026, 11, 10, 11, 0);

      expect(
        computeSlotStatus(
          rotation: null,
          slotTimeStr: '08:30',
          nextSlotTimeStr: '13:30',
          nowKolkata: nowAtExact,
        ),
        equals(SlotStatus.late),
      );
      expect(
        computeSlotStatus(
          rotation: null,
          slotTimeStr: '08:30',
          nextSlotTimeStr: '13:30',
          nowKolkata: nowDuringWindow,
        ),
        equals(SlotStatus.late),
      );
    });

    test('Returns missed when next slot begins and no rotation exists', () {
      final nowAtNext = DateTime(2026, 11, 10, 13, 30);
      final nowAfterNext = DateTime(2026, 11, 10, 15, 0);

      expect(
        computeSlotStatus(
          rotation: null,
          slotTimeStr: '08:30',
          nextSlotTimeStr: '13:30',
          nowKolkata: nowAtNext,
        ),
        equals(SlotStatus.missed),
      );
      expect(
        computeSlotStatus(
          rotation: null,
          slotTimeStr: '08:30',
          nextSlotTimeStr: '13:30',
          nowKolkata: nowAfterNext,
        ),
        equals(SlotStatus.missed),
      );
    });

    test('Returns done whenever rotation exists regardless of time', () {
      final earlyNow = DateTime(2026, 11, 10, 7, 0);
      final lateNow = DateTime(2026, 11, 10, 22, 0);

      expect(
        computeSlotStatus(
          rotation: mockRotation,
          slotTimeStr: '08:30',
          nextSlotTimeStr: '13:30',
          nowKolkata: earlyNow,
        ),
        equals(SlotStatus.done),
      );
      expect(
        computeSlotStatus(
          rotation: mockRotation,
          slotTimeStr: '08:30',
          nextSlotTimeStr: '13:30',
          nowKolkata: lateNow,
        ),
        equals(SlotStatus.done),
      );
    });

    test('Last slot of day (evening) is late until 23:59:59, then missed', () {
      final eveningLate = DateTime(2026, 11, 10, 22, 45);
      final endOfDayMissed = DateTime(2026, 11, 10, 23, 59, 59);

      expect(
        computeSlotStatus(
          rotation: null,
          slotTimeStr: '20:30',
          nextSlotTimeStr: null,
          nowKolkata: eveningLate,
        ),
        equals(SlotStatus.late),
      );
      expect(
        computeSlotStatus(
          rotation: null,
          slotTimeStr: '20:30',
          nextSlotTimeStr: null,
          nowKolkata: endOfDayMissed,
        ),
        equals(SlotStatus.missed),
      );
    });
  });
}
