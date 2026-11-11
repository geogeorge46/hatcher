import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/method_channel.dart';
import '../data/firestore_service.dart';
import '../data/local_prefs.dart';
import 'auth_provider.dart';

/// The display name chosen on the name-picker screen.
final userNameProvider = StateProvider<String?>(
  (ref) => LocalPrefs.userName,
  name: 'userNameProvider',
);

/// The anonymous Firebase UID cached in [LocalPrefs].
final userUidProvider = Provider<String?>(
  (ref) => LocalPrefs.userUid,
  name: 'userUidProvider',
);

/// The FCM registration token for this device.
final fcmTokenProvider = StateProvider<String?>(
  (ref) => LocalPrefs.fcmToken,
  name: 'fcmTokenProvider',
);

/// Saves user profile locally and remotely to Firestore.
final saveUserProfileProvider =
    FutureProvider.family<void, String>((ref, name) async {
  // 1. Ensure anonymous auth
  final credential = await ref.read(signInAnonymouslyProvider.future);
  final uid = credential.user?.uid;
  if (uid == null) {
    throw StateError('Anonymous sign-in succeeded but UID is null.');
  }

  // 2. Persist locally
  LocalPrefs.userName = name;
  LocalPrefs.userUid = uid;
  ref.read(userNameProvider.notifier).state = name;
  await HatcherChannel.syncContext(userName: name, userUid: uid);

  // 3. Write to Firestore
  final service = ref.read(firestoreServiceProvider);
  final fcmToken = ref.read(fcmTokenProvider);
  await service.saveUser(uid: uid, name: name, fcmToken: fcmToken);
}, name: 'saveUserProfileProvider');
