// lib/data/firestore_service.dart
//
// Centralised Firestore access layer for the Hatcher app.
//
// All reads return Streams so the UI rebuilds automatically whenever the
// underlying Firestore documents change.  All writes are fire-and-forget
// (the caller awaits the Future but does not receive a return value unless
// a new document ID is needed).
//
// CONCURRENCY NOTE: Firestore's addRotation uses a Transaction to prevent
// two phones from simultaneously logging a rotation for the same slot.
// If the document already exists the transaction throws 'already_done' so
// the UI can show an appropriate message.
//
// UNDO WINDOW: undoRotation enforces a 10-minute undo window by comparing
// doneAt (server timestamp) with the current client time.  This is a
// best-effort guard – the final arbiter is the Firestore Security Rule.

import 'dart:async';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/batch.dart';
import 'models/escalation_models.dart';
import 'models/rotation.dart';
import 'models/settings_model.dart';

/// Riverpod provider for [FirestoreService].
final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  return FirestoreService();
});

/// Provides all Firestore read/write operations needed by the Hatcher app.
///
/// Inject this class via a Riverpod [Provider] so it can be mocked in tests:
/// ```dart
/// final firestoreServiceProvider = Provider((ref) => FirestoreService());
/// ```
class FirestoreService {
  FirestoreService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // ---------------------------------------------------------------------------
  // Collection / document references (DRY helpers)
  // ---------------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  CollectionReference<Map<String, dynamic>> get _batches =>
      _db.collection('batches');

  CollectionReference<Map<String, dynamic>> get _rotations =>
      _db.collection('rotations');

  DocumentReference<Map<String, dynamic>> get _settingsDoc =>
      _db.collection('settings').doc('main');

  // ---------------------------------------------------------------------------
  // Cache-first stream helpers
  // ---------------------------------------------------------------------------

  /// Streams [liveStream] while ensuring the UI never hangs indefinitely
  /// waiting for an initial server snapshot on slow or stalled networks.
  ///
  /// 1. Reads from Firestore's local cache via [readCache] right away.
  /// 2. If [hasData] holds for the cached value, emits it immediately before
  ///    continuing with [liveStream].
  /// 3. If cache is empty or missing, waits up to [gracePeriod] for
  ///    [liveStream]; if [liveStream] has not emitted by then, emits
  ///    [fallbackValue] so loading spinners clear while keeping [liveStream]
  ///    subscribed for future server updates.
  Stream<T> _watchWithCacheFallback<T>({
    required Future<T?> Function() readCache,
    required bool Function(T value) hasData,
    required T fallbackValue,
    required Stream<T> liveStream,
    Duration gracePeriod = const Duration(seconds: 3),
  }) {
    late final StreamController<T> controller;
    StreamSubscription<T>? subscription;
    Timer? timer;
    var emitted = false;
    var cancelled = false;

    void emitData(T value) {
      if (cancelled || controller.isClosed) return;
      emitted = true;
      timer?.cancel();
      controller.add(value);
    }

    controller = StreamController<T>(
      onListen: () async {
        subscription = liveStream.listen(
          emitData,
          onError: (Object error, StackTrace stack) {
            if (cancelled || controller.isClosed) return;
            timer?.cancel();
            controller.addError(error, stack);
          },
          onDone: () {
            timer?.cancel();
            if (!controller.isClosed) {
              controller.close();
            }
          },
        );

        try {
          final cached = await readCache().timeout(const Duration(seconds: 2));
          if (!cancelled && !emitted && cached != null && hasData(cached)) {
            emitData(cached);
            return;
          }
        } catch (e) {
          dev.log('FirestoreService: cache read skipped ($e)',
              name: 'FirestoreService');
        }

        if (!cancelled && !emitted) {
          timer = Timer(gracePeriod, () {
            if (!cancelled && !emitted) {
              dev.log(
                'FirestoreService: stream timed out after '
                '${gracePeriod.inSeconds}s – using fallback',
                name: 'FirestoreService',
              );
              emitData(fallbackValue);
            }
          });
        }
      },
      onCancel: () async {
        cancelled = true;
        timer?.cancel();
        await subscription?.cancel();
      },
    );

    return controller.stream;
  }

  Stream<T> _watchQueryWithCacheFallback<T>({
    required Query<Map<String, dynamic>> query,
    required T Function(QuerySnapshot<Map<String, dynamic>> qs) mapQuery,
    required bool Function(T value) hasData,
    required T fallbackValue,
  }) {
    return _watchWithCacheFallback<T>(
      readCache: () async =>
          mapQuery(await query.get(const GetOptions(source: Source.cache))),
      hasData: hasData,
      fallbackValue: fallbackValue,
      liveStream: query.snapshots().map(mapQuery),
    );
  }

  Stream<T> _watchDocWithCacheFallback<T>({
    required DocumentReference<Map<String, dynamic>> doc,
    required T Function(DocumentSnapshot<Map<String, dynamic>> snap) mapDoc,
    required T fallbackValue,
  }) {
    return _watchWithCacheFallback<T>(
      readCache: () async {
        final snap = await doc.get(const GetOptions(source: Source.cache));
        if (!snap.exists || snap.data() == null) return null;
        return mapDoc(snap);
      },
      hasData: (value) => value != null,
      fallbackValue: fallbackValue,
      liveStream: doc.snapshots().map(mapDoc),
    );
  }

  // ---------------------------------------------------------------------------
  // User management
  // ---------------------------------------------------------------------------

  /// Creates or updates the user profile document at `users/{uid}`.
  ///
  /// Uses `SetOptions(merge: true)` so a partial update (e.g. a new FCM token)
  /// does not wipe fields written by other phones.
  ///
  /// [uid]      – Firebase Auth UID (the document ID).
  /// [name]     – Display name selected on first launch.
  /// [fcmToken] – Current FCM registration token; may be null if FCM has not
  ///              yet returned a token.
  Future<void> saveUser({
    required String uid,
    required String name,
    required String? fcmToken,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'updatedAt': FieldValue.serverTimestamp(),
      if (fcmToken != null) 'fcmToken': fcmToken,
    };
    await _users.doc(uid).set(data, SetOptions(merge: true));
    dev.log('FirestoreService: saveUser uid=$uid name=$name',
        name: 'FirestoreService');
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  /// Streams the shared settings document, emitting a [SettingsModel] on
  /// every change.
  ///
  /// If the document does not exist yet (first launch), emits
  /// [SettingsModel.defaults()] so the app is always in a usable state.
  Stream<SettingsModel> watchSettings() {
    return _watchDocWithCacheFallback<SettingsModel>(
      doc: _settingsDoc,
      fallbackValue: SettingsModel.defaults(),
      mapDoc: (snapshot) {
        if (!snapshot.exists || snapshot.data() == null) {
          dev.log('FirestoreService: settings doc missing – using defaults',
              name: 'FirestoreService');
          return SettingsModel.defaults();
        }
        return SettingsModel.fromFirestore(snapshot);
      },
    );
  }

  /// Writes [s] to `settings/main`, replacing the entire document.
  ///
  /// Uses plain `set` (no merge) so stale fields removed in [SettingsModel]
  /// do not persist.
  Future<void> saveSettings(SettingsModel s) async {
    await _settingsDoc.set(s.toMap(), SetOptions(merge: true));
    dev.log('FirestoreService: saveSettings written', name: 'FirestoreService');
  }

  /// Silences all alarms, notifications, and escalation calls up to and including [untilDate] ('yyyy-MM-dd').
  Future<void> muteUntil(String untilDate) async {
    await _settingsDoc.set({
      'mutedUntilDate': untilDate,
      'mutedDate': untilDate,
    }, SetOptions(merge: true));
    dev.log('FirestoreService: mutedUntilDate set to $untilDate', name: 'FirestoreService');
  }

  /// Silences all alarms, notifications, and escalation calls for today.
  Future<void> muteToday(String date) => muteUntil(date);

  /// Clears the muted dates so notifications resume immediately.
  Future<void> unmuteToday() async {
    await _settingsDoc.set({
      'mutedUntilDate': null,
      'mutedDate': null,
    }, SetOptions(merge: true));
    dev.log('FirestoreService: muted dates cleared', name: 'FirestoreService');
  }

  // ---------------------------------------------------------------------------
  // Batches
  // ---------------------------------------------------------------------------

  /// Streams the list of currently active batches (status == 'active').
  ///
  /// Under normal operation there should be at most one active batch, but
  /// returning a list keeps the API flexible.
  ///
  /// The stream emits an empty list when no batch is active so the UI can
  /// show the "Start a new batch" prompt.
  Stream<List<Batch>> watchActiveBatch() {
    final query = _batches
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true);
    return _watchQueryWithCacheFallback<List<Batch>>(
      query: query,
      mapQuery: (qs) => qs.docs.map(Batch.fromFirestore).toList(),
      hasData: (batches) => batches.isNotEmpty,
      fallbackValue: const [],
    );
  }

  /// Streams all batches ordered by creation date descending.
  Stream<List<Batch>> watchAllBatches() {
    final query = _batches.orderBy('createdAt', descending: true);
    return _watchQueryWithCacheFallback<List<Batch>>(
      query: query,
      mapQuery: (qs) => qs.docs.map(Batch.fromFirestore).toList(),
      hasData: (batches) => batches.isNotEmpty,
      fallbackValue: const [],
    );
  }

  /// Creates a new batch document and returns its auto-generated Firestore ID.
  ///
  /// [placedDate]  – 'yyyy-MM-dd' in Kolkata time.
  /// [eggCount]    – Number of eggs placed.
  /// [createdBy]   – Display name of the user creating the batch.
  /// [uid]         – Firebase Auth UID of the creating user.
  ///
  /// Uses `FieldValue.serverTimestamp()` for `createdAt` so all phones agree
  /// on the creation time regardless of local clock skew.
  Future<String> createBatch({
    required String placedDate,
    required int eggCount,
    required String createdBy,
    required String uid,
  }) async {
    final ref = await _batches.add({
      'placedDate': placedDate,
      'eggCount': eggCount,
      'status': 'active',
      'createdBy': createdBy,
      'createdByUid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    dev.log('FirestoreService: createBatch id=${ref.id} placedDate=$placedDate',
        name: 'FirestoreService');
    return ref.id;
  }

  /// Marks a batch as ended by setting its `status` field to `'ended'`.
  ///
  /// Also records the time the batch was ended for history display.
  Future<void> endBatch(String batchId) async {
    await _batches.doc(batchId).update({
      'status': 'ended',
      'endedAt': FieldValue.serverTimestamp(),
    });
    dev.log('FirestoreService: endBatch batchId=$batchId',
        name: 'FirestoreService');
  }

  // ---------------------------------------------------------------------------
  // Rotations
  // ---------------------------------------------------------------------------

  /// Streams today's rotation records as a map keyed by slot name.
  ///
  /// [dateStr] – The current Kolkata date as 'yyyy-MM-dd'.
  ///
  /// Returns e.g.:
  /// ```dart
  /// {
  ///   'morning': Rotation(...),   // morning done
  ///   'noon':    null,            // not in map → not done
  /// }
  /// ```
  /// Only completed slots appear in the map; missing keys mean pending/late/missed.
  Stream<Map<String, Rotation>> watchTodayRotations(String dateStr) {
    final query = _rotations.where('date', isEqualTo: dateStr);
    return _watchQueryWithCacheFallback<Map<String, Rotation>>(
      query: query,
      mapQuery: (qs) {
        final map = <String, Rotation>{};
        for (final doc in qs.docs) {
          final rotation = Rotation.fromFirestore(doc);
          map[rotation.slot] = rotation;
        }
        return map;
      },
      hasData: (map) => map.isNotEmpty,
      fallbackValue: const {},
    );
  }

  /// Streams all rotation records, optionally filtered by [batchId].
  ///
  /// Results are ordered by [doneAt] descending so the most recent rotation
  /// appears at the top of the history list.
  ///
  /// Pass `batchId: null` to show rotations for all batches.
  Stream<List<Rotation>> watchAllRotations({String? batchId}) {
    Query<Map<String, dynamic>> query = _rotations;
    if (batchId != null) {
      query = query.where('batchId', isEqualTo: batchId);
    }
    query = query.orderBy('doneAt', descending: true);
    return _watchQueryWithCacheFallback<List<Rotation>>(
      query: query,
      mapQuery: (qs) => qs.docs.map(Rotation.fromFirestore).toList(),
      hasData: (list) => list.isNotEmpty,
      fallbackValue: const [],
    );
  }

  /// Records a rotation for the given [slot] on [date].
  ///
  /// Uses a Firestore transaction to atomically check whether a rotation
  /// document already exists before writing.  Throws a [Exception] with
  /// message `'already_done'` if the slot was already claimed by another user.
  ///
  /// The document ID is deterministic: `'{date}_{slot}'` (e.g.
  /// `'2025-06-01_morning'`).  This prevents any chance of duplicate documents
  /// for the same slot even under concurrent writes.
  ///
  /// [date]       – 'yyyy-MM-dd' in Kolkata time.
  /// [slot]       – One of 'morning', 'noon', 'evening'.
  /// [doneBy]     – Display name of the user performing the rotation.
  /// [doneByUid]  – Firebase Auth UID of the performing user.
  /// [batchId]    – ID of the currently active batch.
  Future<void> addRotation({
    required String date,
    required String slot,
    required String doneBy,
    required String doneByUid,
    required String batchId,
  }) async {
    final docId = '${date}_$slot';
    final docRef = _rotations.doc(docId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (snapshot.exists) {
        // Another phone logged this slot while this user was tapping.
        // Throw a typed exception so the UI can show a friendly message.
        throw Exception('already_done');
      }
      transaction.set(docRef, {
        'date': date,
        'slot': slot,
        'doneBy': doneBy,
        'doneByUid': doneByUid,
        'batchId': batchId,
        // Server timestamp ensures consistent time across all devices even if
        // a phone has a skewed local clock.
        'doneAt': FieldValue.serverTimestamp(),
      });
    });

    dev.log(
      'FirestoreService: addRotation date=$date slot=$slot by=$doneBy',
      name: 'FirestoreService',
    );
  }

  /// Deletes a rotation document, enforcing a 10-minute undo window.
  ///
  /// The window is enforced client-side by comparing [Rotation.doneAt] with
  /// the current time.  For production hardening you should also enforce this
  /// in a Firestore Security Rule:
  ///   `request.time < resource.data.doneAt + duration.value(10, 'm')`
  ///
  /// Throws [Exception('undo_expired')] if the 10-minute window has passed.
  /// Throws [Exception('not_found')] if the document no longer exists.
  Future<void> undoRotation(String docId) async {
    final docRef = _rotations.doc(docId);
    final snapshot = await docRef.get();

    if (!snapshot.exists) {
      throw Exception('not_found');
    }

    final rotation = Rotation.fromFirestore(snapshot);
    final doneAtMs = rotation.doneAt.millisecondsSinceEpoch;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 10 minutes = 600 000 milliseconds.
    const undoWindowMs = 10 * 60 * 1000;
    if (nowMs - doneAtMs > undoWindowMs) {
      throw Exception('undo_expired');
    }

    await docRef.delete();
    dev.log('FirestoreService: undoRotation docId=$docId',
        name: 'FirestoreService');
  }

  // ---------------------------------------------------------------------------
  // Phase 2: Escalation, Telegram, Phone Numbers, Gateway, Audit Logs
  // ---------------------------------------------------------------------------

  Stream<EscalationSettings> watchEscalationSettings() {
    return _watchDocWithCacheFallback<EscalationSettings>(
      doc: _db.collection('settings').doc('escalation'),
      fallbackValue: EscalationSettings.defaults(),
      mapDoc: (snap) {
        if (!snap.exists || snap.data() == null) {
          return EscalationSettings.defaults();
        }
        return EscalationSettings.fromFirestore(snap);
      },
    );
  }

  Future<void> saveEscalationSettings(EscalationSettings settings) async {
    await _db
        .collection('settings')
        .doc('escalation')
        .set(settings.toMap());
  }

  Stream<TelegramSettings> watchTelegramSettings() {
    return _watchDocWithCacheFallback<TelegramSettings>(
      doc: _db.collection('settings').doc('telegram'),
      fallbackValue: TelegramSettings.empty(),
      mapDoc: (snap) {
        if (!snap.exists || snap.data() == null) {
          return TelegramSettings.empty();
        }
        return TelegramSettings.fromFirestore(snap);
      },
    );
  }

  Future<void> saveTelegramChatId(String chatId) async {
    await _db.collection('settings').doc('telegram').set(
      {'chatId': chatId.trim()},
      SetOptions(merge: true),
    );
  }

  Stream<List<UserProfile>> watchAllUsers() {
    return _watchQueryWithCacheFallback<List<UserProfile>>(
      query: _users,
      mapQuery: (qs) => qs.docs.map(UserProfile.fromFirestore).toList(),
      hasData: (users) => users.isNotEmpty,
      fallbackValue: const [],
    );
  }

  Future<void> saveUserPhone({
    required String uid,
    required String phone,
  }) async {
    await _users.doc(uid).set(
      {
        'phone': phone.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Stream<GatewayStatus?> watchGatewayStatus() {
    return _watchDocWithCacheFallback<GatewayStatus?>(
      doc: _db.collection('gateway').doc('status'),
      fallbackValue: null,
      mapDoc: (snap) {
        if (!snap.exists || snap.data() == null) return null;
        return GatewayStatus.fromFirestore(snap);
      },
    );
  }

  Future<void> claimGatewayIdentity(String uid) async {
    await _db.collection('gateway').doc('status').set(
      {
        'uid': uid,
        'lastSeen': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Stream<List<AuditLogEntry>> watchAuditLogs({int limit = 100}) {
    final query = _db
        .collection('auditLogs')
        .orderBy('createdAtMs', descending: true)
        .limit(limit);
    return _watchQueryWithCacheFallback<List<AuditLogEntry>>(
      query: query,
      mapQuery: (qs) => qs.docs.map(AuditLogEntry.fromFirestore).toList(),
      hasData: (logs) => logs.isNotEmpty,
      fallbackValue: const [],
    );
  }
}
