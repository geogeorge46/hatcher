import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/method_channel.dart';
import '../data/firestore_service.dart';
import '../data/models/batch.dart';
import 'auth_provider.dart';
import 'user_provider.dart';

/// Streams the currently active [Batch], or null when no batch is running.
final activeBatchProvider = StreamProvider<Batch?>((ref) {
  final service = ref.watch(firestoreServiceProvider);
  return service.watchActiveBatch().map((batches) {
    final active = batches.isNotEmpty ? batches.first : null;
    if (active != null) {
      HatcherChannel.syncContext(batchId: active.id);
    }
    return active;
  });
}, name: 'activeBatchProvider');

/// Streams all batches (active and ended) for history filtering.
final allBatchesProvider = StreamProvider<List<Batch>>((ref) {
  final service = ref.watch(firestoreServiceProvider);
  return service.watchAllBatches();
}, name: 'allBatchesProvider');

/// Provides a function to create a new incubation batch.
final createBatchProvider = Provider<Future<String> Function({required String placedDate, required int eggCount})>((ref) {
  final service = ref.read(firestoreServiceProvider);
  final createdBy = ref.read(userNameProvider) ?? 'Unknown';
  final uid = ref.read(currentUidProvider) ?? 'anonymous';
  return ({required String placedDate, required int eggCount}) =>
      service.createBatch(placedDate: placedDate, eggCount: eggCount, createdBy: createdBy, uid: uid);
}, name: 'createBatchProvider');

/// Provides a function to end an existing batch.
final endBatchProvider = Provider<Future<void> Function(String batchId)>((ref) {
  final service = ref.read(firestoreServiceProvider);
  return (String batchId) => service.endBatch(batchId);
}, name: 'endBatchProvider');
