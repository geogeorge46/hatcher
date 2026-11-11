// lib/ui/screens/language_picker_screen.dart
//
// First-launch screen: the user picks the UI language (Malayalam / English).
// This screen intentionally does NOT use AppLocalizations because the locale
// hasn't been set yet — strings are hardcoded bilingually.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app.dart';
import '../../data/local_prefs.dart';
import '../theme/app_theme.dart';

class LanguagePickerScreen extends ConsumerStatefulWidget {
  const LanguagePickerScreen({super.key});

  @override
  ConsumerState<LanguagePickerScreen> createState() =>
      _LanguagePickerScreenState();
}

class _LanguagePickerScreenState extends ConsumerState<LanguagePickerScreen> {
  /// The language code that is currently selected / highlighted.
  /// Initialised from [LocalPrefs] so a returning user sees their last choice.
  String? _selected;

  @override
  void initState() {
    super.initState();
    // Show the previously saved language as highlighted on re-entry.
    _selected = LocalPrefs.languageCode;
  }

  /// Saves the chosen language code and navigates to the name-picker.
  Future<void> _pick(String code) async {
    setState(() => _selected = code);
    LocalPrefs.languageCode = code;
    ref.read(languageProvider.notifier).state = Locale(code);
    if (!mounted) return;
    context.go('/name');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Egg logo ──────────────────────────────────────────────
                const Text(
                  '🥚',
                  style: TextStyle(fontSize: 72),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hatcher · ഹാച്ചർ',
                  style: TextStyle(
                    fontFamily: 'NotoSansMalayalam',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: kPrimaryGreen,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // ── Instruction (bilingual) ───────────────────────────────
                const Text(
                  'ഭാഷ തിരഞ്ഞെടുക്കൂ  ·  Choose your language',
                  style: TextStyle(
                    fontFamily: 'NotoSansMalayalam',
                    fontSize: 15,
                    color: Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // ── Malayalam card ────────────────────────────────────────
                _LanguageCard(
                  primaryScript: 'മലയാളം',
                  secondaryScript: 'Malayalam',
                  code: 'ml',
                  isSelected: _selected == 'ml',
                  onTap: () => _pick('ml'),
                ),
                const SizedBox(height: 16),

                // ── English card ──────────────────────────────────────────
                _LanguageCard(
                  primaryScript: 'English',
                  secondaryScript: 'ഇംഗ്ലീഷ്',
                  code: 'en',
                  isSelected: _selected == 'en',
                  onTap: () => _pick('en'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _LanguageCard
// ---------------------------------------------------------------------------
class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.primaryScript,
    required this.secondaryScript,
    required this.code,
    required this.isSelected,
    required this.onTap,
  });

  final String primaryScript;
  final String secondaryScript;
  final String code;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 80,
        width: double.infinity,
        decoration: BoxDecoration(
          color: isSelected ? kPrimaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? kPrimaryGreen : Colors.grey.shade300,
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isSelected ? 0.15 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              primaryScript,
              style: TextStyle(
                fontFamily: 'NotoSansMalayalam',
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '·  $secondaryScript',
              style: TextStyle(
                fontFamily: 'NotoSansMalayalam',
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: isSelected ? Colors.white70 : Colors.black54,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 10),
              const Icon(Icons.check_circle, color: Colors.white, size: 22),
            ],
          ],
        ),
      ),
    );
  }
}
