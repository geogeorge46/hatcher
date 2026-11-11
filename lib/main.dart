import 'dart:developer' as dev;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import 'app.dart';
import 'core/method_channel.dart';
import 'data/firestore_service.dart';
import 'data/local_prefs.dart';
import 'firebase_options.dart';
import 'providers/user_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize timezone database for Asia/Kolkata conversions.
  tz_data.initializeTimeZones();

  // 2. Initialize SharedPreferences cache.
  try {
    await LocalPrefs.init();
  } catch (e, stack) {
    dev.log('Failed to initialize LocalPrefs: $e', error: e, stackTrace: stack);
  }

  // 3. Initialize Firebase + Firestore offline persistence + FCM registration.
  String? initialFcmToken;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Explicitly ensure Cloud Firestore offline persistence is enabled.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // Register FCM token for Phase 2 push notifications.
    try {
      final messaging = FirebaseMessaging.instance;
      initialFcmToken = await messaging.getToken();
      if (initialFcmToken != null) {
        LocalPrefs.fcmToken = initialFcmToken;
      }

      // Listen for foreground FCM data messages (background handled natively by
      // HatcherFirebaseMessagingService.kt even when app is terminated).
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        final action = message.data['action'];
        if (action == 'cancel_slot') {
          final date = message.data['date']?.toString();
          final slotKey = message.data['slotKey']?.toString();
          if (date != null && slotKey != null) {
            await LocalPrefs.markSlotDone(date, slotKey);
            await HatcherChannel.markSlotDoneLocally(date: date, slot: slotKey);
          }
        }
      });

      // Listen for token refreshes and update Firestore if user is signed in.
      messaging.onTokenRefresh.listen((newToken) async {
        LocalPrefs.fcmToken = newToken;
        final uid = LocalPrefs.userUid;
        final name = LocalPrefs.userName;
        if (uid != null && name != null) {
          await FirestoreService().saveUser(
            uid: uid,
            name: name,
            fcmToken: newToken,
          );
        }
      });
    } catch (e) {
      dev.log('FCM token registration warning: $e', error: e);
    }

    // Sync existing user identity to native SharedPreferences on launch.
    if (LocalPrefs.userName != null || LocalPrefs.userUid != null) {
      await HatcherChannel.syncContext(
        userName: LocalPrefs.userName,
        userUid: LocalPrefs.userUid,
      );
    }

    dev.log('Firebase initialized successfully.');
  } catch (e) {
    dev.log(
      'Firebase initialization warning: $e\n'
      'Ensure google-services.json is in android/app/ and firebase_options.dart is configured.',
      error: e,
    );
  }

  // 4. Read persisted language preference if present, defaulting to Malayalam ('ml').
  final savedLanguageCode = LocalPrefs.languageCode ?? 'ml';

  runApp(
    ProviderScope(
      overrides: [
        languageProvider.overrideWith((ref) => Locale(savedLanguageCode)),
        if (initialFcmToken != null)
          fcmTokenProvider.overrideWith((ref) => initialFcmToken),
      ],
      child: const HatcherApp(),
    ),
  );
}
