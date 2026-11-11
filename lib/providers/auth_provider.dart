// lib/providers/auth_provider.dart
//
// Firebase Authentication providers for Hatcher.
// Uses anonymous sign-in so the app works without any account creation UX.
// All providers are plain Riverpod 2.x (no code-gen) for simplicity.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// authStateProvider
// ---------------------------------------------------------------------------
/// Streams the current [User?] from FirebaseAuth.
///
/// Re-emits every time the auth state changes (sign-in, sign-out, token refresh).
/// Downstream providers can watch this to react immediately to auth changes.
final authStateProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.authStateChanges(),
  name: 'authStateProvider',
);

// ---------------------------------------------------------------------------
// signInAnonymouslyProvider
// ---------------------------------------------------------------------------
/// Signs the user in anonymously if they are not already signed in.
///
/// Returns the [UserCredential] produced by [FirebaseAuth.signInAnonymously].
/// If a user is already signed in this future resolves immediately with a
/// fresh [UserCredential] snapshot (calling signInAnonymously again is safe
/// and idempotent on Firebase's side).
///
/// Usage: `await ref.read(signInAnonymouslyProvider.future)`
final signInAnonymouslyProvider = FutureProvider<UserCredential>(
  (ref) async {
    // Watch the auth-state stream; if already signed in skip the network call.
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      // Re-authenticate anonymously to get a fresh UserCredential.
      // This is a lightweight call that hits the local cache first.
      return FirebaseAuth.instance.signInAnonymously();
    }
    // No user yet — perform the actual anonymous sign-in.
    return FirebaseAuth.instance.signInAnonymously();
  },
  name: 'signInAnonymouslyProvider',
);

// ---------------------------------------------------------------------------
// currentUidProvider
// ---------------------------------------------------------------------------
/// Synchronous convenience provider that returns the current user's UID.
///
/// Returns `null` when no user is signed in (stream is still loading or the
/// user signed out). Widgets should handle the null case gracefully.
final currentUidProvider = Provider<String?>(
  (ref) {
    // Derive from the auth stream so it updates whenever auth state changes.
    final authAsync = ref.watch(authStateProvider);
    return authAsync.whenOrNull(data: (user) => user?.uid);
  },
  name: 'currentUidProvider',
);
