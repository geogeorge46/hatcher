// lib/ui/theme/app_theme.dart
//
// Central theme definition for the Hatcher egg-incubation app.
// Design language: warm, natural, easy-to-read on cheap Android screens.

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Brand colours
// ---------------------------------------------------------------------------

/// Primary – deep green, like healthy grass / incubator trays.
const Color kPrimaryGreen = Color(0xFF2E7D32);

/// Secondary – warm amber, like egg yolk / straw.
const Color kSecondaryAmber = Color(0xFFF9A825);

/// Background – near-white with a warm tint to reduce eye-strain.
const Color kBackground = Color(0xFFFAFAF8);

/// Surface (cards, dialogs).
const Color kSurface = Color(0xFFFFFFFF);

/// Error red.
const Color kError = Color(0xFFB00020);

// ---------------------------------------------------------------------------
// Slot colours
// ---------------------------------------------------------------------------
/// Slot-specific accent colours for card left-borders and status chips.
///
/// [slot] should be one of: `'morning'`, `'noon'`, `'evening'`.
/// Falls back to grey for unknown slots.
Color slotColor(String slot) {
  switch (slot.toLowerCase()) {
    case 'morning':
      return const Color(0xFFF9A825); // amber
    case 'noon':
      return const Color(0xFFF57C00); // orange
    case 'evening':
      return const Color(0xFF3949AB); // indigo
    default:
      return Colors.grey;
  }
}

// ---------------------------------------------------------------------------
// lightTheme
// ---------------------------------------------------------------------------
/// The single [ThemeData] used by [HatcherApp].
///
/// Key decisions:
/// - NotoSansMalayalam as the default font family so both scripts look great.
/// - Material 3 is **off** to keep compatibility with older devices (Android 7+).
/// - Card corners: 16 px radius with mild elevation.
/// - ElevatedButton: 12 px radius, generous padding, 18 sp label.
final ThemeData lightTheme = ThemeData(
  useMaterial3: false,
  fontFamily: 'NotoSansMalayalam',

  // Colour scheme ---------------------------------------------------------
  colorScheme: ColorScheme.light(
    primary: kPrimaryGreen,
    onPrimary: Colors.white,
    secondary: kSecondaryAmber,
    onSecondary: Colors.black87,
    surface: kSurface,
    onSurface: Colors.black87,
    error: kError,
    onError: Colors.white,
  ),
  primaryColor: kPrimaryGreen,
  scaffoldBackgroundColor: kBackground,

  // AppBar ----------------------------------------------------------------
  appBarTheme: const AppBarTheme(
    backgroundColor: kPrimaryGreen,
    foregroundColor: Colors.white,
    elevation: 2,
    titleTextStyle: TextStyle(
      fontFamily: 'NotoSansMalayalam',
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
  ),

  // Cards -----------------------------------------------------------------
  cardTheme: CardThemeData(
    color: kSurface,
    elevation: 3,
    shadowColor: Colors.black26,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  ),

  // ElevatedButton --------------------------------------------------------
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kPrimaryGreen,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 52),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(
        fontFamily: 'NotoSansMalayalam',
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      elevation: 2,
    ),
  ),

  // OutlinedButton --------------------------------------------------------
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: kPrimaryGreen,
      side: const BorderSide(color: kPrimaryGreen, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      textStyle: const TextStyle(
        fontFamily: 'NotoSansMalayalam',
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),

  // TextButton ------------------------------------------------------------
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: kPrimaryGreen,
      textStyle: const TextStyle(
        fontFamily: 'NotoSansMalayalam',
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),

  // Input fields ----------------------------------------------------------
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.grey),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kPrimaryGreen, width: 2),
    ),
  ),

  // SnackBar --------------------------------------------------------------
  snackBarTheme: SnackBarThemeData(
    backgroundColor: Colors.grey[850],
    contentTextStyle: const TextStyle(
      fontFamily: 'NotoSansMalayalam',
      color: Colors.white,
      fontSize: 14,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    behavior: SnackBarBehavior.floating,
  ),

  // Progress indicator ----------------------------------------------------
  progressIndicatorTheme: const ProgressIndicatorThemeData(
    color: kPrimaryGreen,
    linearTrackColor: Color(0xFFBBDEFB),
  ),

  // Chip ------------------------------------------------------------------
  chipTheme: ChipThemeData(
    backgroundColor: kBackground,
    labelStyle: const TextStyle(fontFamily: 'NotoSansMalayalam'),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ),

  // Global text theme -----------------------------------------------------
  textTheme: const TextTheme(
    displayLarge: TextStyle(fontSize: 57, fontWeight: FontWeight.w400),
    displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.w400),
    displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.w400),
    headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
    headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
    headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
    bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
    labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    labelMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
  ).apply(fontFamily: 'NotoSansMalayalam'),

  // Divider ---------------------------------------------------------------
  dividerTheme: const DividerThemeData(
    color: Color(0xFFE0E0E0),
    thickness: 1,
  ),
);
