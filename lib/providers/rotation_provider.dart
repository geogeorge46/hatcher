import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/extensions.dart';
import '../core/method_channel.dart';
import '../data/firestore_service.dart';
import '../data/local_prefs.dart';
import '../data/models/rotation.dart';
import 'auth_provider.dart';
import 'user_provider.dart';

/// Streams a [Map<String, Rotation>] keyed by slot name for today (Asia/Kolkata).
/// Also keeps LocalPrefs in sync for the native alarm "Is it done?" check.
final todayRotationsProvider = StreamProvider<Map<String, Rotation>>((ref) {
  final service = ref.watch(firestoreServiceProvider);
  final todayStr = nowKolkata().kolkataDate();

  return service.watchTodayRotations(todayStr).map((map) {
    // Mirror today's completions into SharedPreferences so Kotlin AlarmService
    // can check locally without waiting for a network call.
    for (final slot in map.keys) {
      LocalPrefs.markSlotDone(todayStr, slot);
      HatcherChannel.markSlotDoneLocally(date: todayStr, slot: slot);
    }
    return map;
  });
}, name: 'todayRotationsProvider');

/// Streams all rotation records across batches, optionally filtered.
final allRotationsProvider = StreamProvider<List<Rotation>>((ref) {
  final service = ref.watch(firestoreServiceProvider);
  return service.watchAllRotations();
}, name: 'allRotationsProvider');

/// Streams rotations filtered by [batchId].
final rotationsForBatchProvider =
    StreamProvider.family<List<Rotation>, String>((ref, batchId) {
  final service = ref.watch(firestoreServiceProvider);
  return service.watchAllRotations(batchId: batchId);
}, name: 'rotationsForBatchProvider');

/// Provides the [FirestoreService.addRotation] function.
final addRotationProvider = Provider<
    Future<void> Function({
      required String slot,
      required String batchId,
      String? date,
    })>((ref) {
  final service = ref.read(firestoreServiceProvider);
  final userName = ref.read(userNameProvider) ?? 'Unknown';
  final uid = ref.read(currentUidProvider) ?? LocalPrefs.userUid ?? 'anonymous';

  return ({
    required String slot,
    required String batchId,
    String? date,
  }) async {
    final targetDate = date ?? nowKolkata().kolkataDate();
    await service.addRotation(
      date: targetDate,
      slot: slot,
      doneBy: userName,
      doneByUid: uid,
      batchId: batchId,
    );
    await LocalPrefs.markSlotDone(targetDate, slot);
    await HatcherChannel.markSlotDoneLocally(date: targetDate, slot: slot);
  };
}, name: 'addRotationProvider');

/// Provides the [FirestoreService.undoRotation] function.
final undoRotationProvider = Provider<Future<void> Function(String docId)>((ref) {
  final service = ref.read(firestoreServiceProvider);
  return (String docId) => service.undoRotation(docId);
}, name: 'undoRotationProvider');
