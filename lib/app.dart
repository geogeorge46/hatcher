import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hatcher/core/router.dart';
import 'package:hatcher/ui/theme/app_theme.dart';
import 'package:hatcher/l10n/app_localizations.dart';

/// languageProvider holds the current app Locale.
/// It is initialized from LocalPrefs in main.dart before ProviderScope mounts.
final languageProvider = StateProvider<Locale>((ref) => const Locale('ml'));

/// HatcherApp is the root widget. It reads the locale and router from providers.
class HatcherApp extends ConsumerWidget {
  const HatcherApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(languageProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Hatcher',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ml'), // Malayalam (default)
        Locale('en'), // English
      ],
      routerConfig: router,
    );
  }
}
