// lib/ui/widgets/lockdown_banner.dart
//
// A full-width amber banner displayed when the incubation lockdown period
// starts (e.g. from day 18 onwards) — no more rotation needed.

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// Full-width amber banner indicating that rotation is no longer required.
///
/// Shown when [isLockdownProvider] returns true on the home screen.
class LockdownBanner extends StatelessWidget {
  const LockdownBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        // Warm amber tone — attention-grabbing but not alarming.
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF9A825), width: 1.5),
      ),
      child: Row(
        children: [
          // Lock icon — large enough to be noticed at a glance.
          const Text('🔒', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.lockdownBanner,
              style: const TextStyle(
                fontFamily: 'NotoSansMalayalam',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF5D4037), // deep brown for readability on amber
              ),
            ),
          ),
        ],
      ),
    );
  }
}
