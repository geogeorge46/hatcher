// lib/ui/screens/name_picker_screen.dart
//
// Second on-boarding screen: the user picks a household name.
// The name is saved to both SharedPreferences and Firestore before navigating
// to the home screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/user_provider.dart';
import '../theme/app_theme.dart';

/// The four pre-defined household names for Hatcher.
const _kNames = ['George', 'Dolly', 'Leo', 'Geo'];

/// Emoji avatars corresponding to each name (displayed on the card).
const _kAvatars = ['👨', '👩', '🧒', '👦'];

class NamePickerScreen extends ConsumerStatefulWidget {
  const NamePickerScreen({super.key});

  @override
  ConsumerState<NamePickerScreen> createState() => _NamePickerScreenState();
}

class _NamePickerScreenState extends ConsumerState<NamePickerScreen> {
  /// Index of the name currently being saved (-1 = idle).
  int _saving = -1;

  /// Saves the chosen name via [saveUserProfileProvider] then navigates home.
  Future<void> _pick(String name, int index) async {
    setState(() => _saving = index);
    try {
      // saveUserProfileProvider is a FutureProvider.family; we await its future.
      await ref.read(saveUserProfileProvider(name).future);
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save name: $e'),
          backgroundColor: kError,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = -1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Header ────────────────────────────────────────────────
                const Text('🐣', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 12),
                Text(
                  l10n.pickYourName,
                  style: const TextStyle(
                    fontFamily: 'NotoSansMalayalam',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: kPrimaryGreen,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),

                // ── Name cards ────────────────────────────────────────────
                ...List.generate(_kNames.length, (i) {
                  final name = _kNames[i];
                  final avatar = _kAvatars[i];
                  final isSaving = _saving == i;
                  final isDisabled = _saving != -1 && !isSaving;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _NameCard(
                      name: name,
                      avatar: avatar,
                      isSaving: isSaving,
                      isDisabled: isDisabled,
                      onTap: isDisabled ? null : () => _pick(name, i),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _NameCard
// ---------------------------------------------------------------------------
class _NameCard extends StatelessWidget {
  const _NameCard({
    required this.name,
    required this.avatar,
    required this.isSaving,
    required this.isDisabled,
    required this.onTap,
  });

  final String name;
  final String avatar;
  final bool isSaving;
  final bool isDisabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedOpacity(
        opacity: isDisabled ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: 80,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(avatar, style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 16),
                Text(
                  name,
                  style: const TextStyle(
                    fontFamily: 'NotoSansMalayalam',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                // Loading spinner replaces the arrow while saving.
                if (isSaving)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(kPrimaryGreen),
                    ),
                  )
                else
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 18,
                    color: Colors.grey,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
