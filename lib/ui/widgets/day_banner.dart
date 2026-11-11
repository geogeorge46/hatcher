// lib/ui/widgets/day_banner.dart
//
// A banner widget displayed at the top of the home screen showing
// the current incubation day, a progress bar, and the expected hatch date.

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Displays incubation progress: day number, linear bar, and hatch date.
///
/// [day] — current 1-based day number (1–21).
/// [hatchDate] — human-readable expected hatch date string (e.g. "21 Nov 2026").
class DayBanner extends StatelessWidget {
  const DayBanner({
    super.key,
    required this.day,
    required this.hatchDate,
  });

  final int day;
  final String hatchDate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Clamp progress to [0.0, 1.0] — defensive against out-of-range day values.
    final progress = (day / 21).clamp(0.0, 1.0);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Day number heading ─────────────────────────────────────────
            Text(
              l10n.dayBanner(day),
              style: const TextStyle(
                fontFamily: 'NotoSansMalayalam',
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: kPrimaryGreen,
              ),
            ),
            const SizedBox(height: 10),

            // ── Progress bar ───────────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: const Color(0xFFE8F5E9),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(kPrimaryGreen),
              ),
            ),
            const SizedBox(height: 10),

            // ── Hatch date ─────────────────────────────────────────────────
            Row(
              children: [
                const Text('🐣', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  l10n.hatchDate(hatchDate),
                  style: const TextStyle(
                    fontFamily: 'NotoSansMalayalam',
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
