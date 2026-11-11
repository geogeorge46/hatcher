// lib/core/router.dart
//
// Application router for the Hatcher app, built with go_router and
// flutter_riverpod.
//
// Redirect logic (evaluated in order on every navigation event):
//   1. No languageCode in SharedPreferences → /language (first-time setup)
//   2. No userName in SharedPreferences     → /name    (persona selection)
//   3. Otherwise                            → /home    (main app)
//
// All screen imports use the package: URI so the router can be tested
// independently of the directory structure.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/local_prefs.dart';
import '../ui/screens/escalation_settings_screen.dart';
import '../ui/screens/gateway_settings_screen.dart';
import '../ui/screens/history_screen.dart';
import '../ui/screens/home_screen.dart';
import '../ui/screens/language_picker_screen.dart';
import '../ui/screens/name_picker_screen.dart';
import '../ui/screens/new_batch_screen.dart';
import '../ui/screens/phone_numbers_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/screens/setup_checklist_screen.dart';
import '../ui/screens/telegram_settings_screen.dart';

// ---------------------------------------------------------------------------
// Route path constants – import these instead of hard-coding strings.
// ---------------------------------------------------------------------------

/// Route path for the language-picker screen (shown once on first launch).
const String kRouteLanguage = '/language';

/// Route path for the user name-picker screen (shown after language is set).
const String kRouteName = '/name';

/// Route path for the main home / incubator dashboard screen.
const String kRouteHome = '/home';

/// Route path for starting a new egg batch.
const String kRouteNewBatch = '/new-batch';

/// Route path for the rotation-history log screen.
const String kRouteHistory = '/history';

/// Route path for the app settings screen.
const String kRouteSettings = '/settings';

/// Route path for the permission setup checklist screen.
const String kRouteSetupChecklist = '/setup-checklist';

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

/// A [Provider] that exposes the app-wide [GoRouter] instance.
///
/// The router is created once and kept alive for the lifetime of the
/// [ProviderScope].  Screens and widgets should read this provider via
/// `ref.watch(routerProvider)` or `ref.read(routerProvider)` and navigate
/// with `context.go(...)` / `context.push(...)`.
///
/// The redirect closure reads [LocalPrefs] synchronously (after the prefs
/// singleton is initialised in `main()`) so there is no async gap that could
/// cause a redirect race condition.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    // Start at the root; the redirect will immediately send the user to the
    // correct first screen.
    initialLocation: kRouteHome,

    // ---------------------------------------------------------------------------
    // Global redirect – runs before every route transition.
    // ---------------------------------------------------------------------------
    redirect: (BuildContext context, GoRouterState state) {
      final languageCode = LocalPrefs.languageCode;
      final userName = LocalPrefs.userName;

      final goingToLanguage = state.matchedLocation == kRouteLanguage;
      final goingToName = state.matchedLocation == kRouteName;

      // Step 1: language must be chosen before anything else.
      if (languageCode == null) {
        return goingToLanguage ? null : kRouteLanguage;
      }

      // Step 2: a user name must be chosen before entering the main app.
      if (userName == null) {
        return goingToName ? null : kRouteName;
      }

      // Step 3: if the user somehow lands on a setup screen after completing
      // setup, redirect them home.
      if (goingToLanguage || goingToName) {
        return kRouteHome;
      }

      // No redirect needed.
      return null;
    },

    // ---------------------------------------------------------------------------
    // Route definitions
    // ---------------------------------------------------------------------------
    routes: [
      GoRoute(
        path: kRouteLanguage,
        name: 'language',
        builder: (context, state) => const LanguagePickerScreen(),
      ),
      GoRoute(
        path: kRouteName,
        name: 'name',
        builder: (context, state) => const NamePickerScreen(),
      ),
      GoRoute(
        path: kRouteHome,
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: kRouteNewBatch,
        name: 'newBatch',
        builder: (context, state) => const NewBatchScreen(),
      ),
      GoRoute(
        path: kRouteHistory,
        name: 'history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: kRouteSettings,
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: kRouteSetupChecklist,
        name: 'setupChecklist',
        builder: (context, state) => const SetupChecklistScreen(),
      ),
      GoRoute(
        path: '/settings/escalation',
        name: 'escalationSettings',
        builder: (context, state) => const EscalationSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/telegram',
        name: 'telegramSettings',
        builder: (context, state) => const TelegramSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/phone-numbers',
        name: 'phoneNumbers',
        builder: (context, state) => const PhoneNumbersScreen(),
      ),
      GoRoute(
        path: '/settings/gateway',
        name: 'gatewaySettings',
        builder: (context, state) => const GatewaySettingsScreen(),
      ),
    ],

    // ---------------------------------------------------------------------------
    // Error page
    // ---------------------------------------------------------------------------
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text(
          'Page not found: ${state.uri}',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
});
