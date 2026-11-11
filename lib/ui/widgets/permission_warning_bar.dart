// lib/ui/widgets/permission_warning_bar.dart
//
// A red warning banner that appears on the home screen when one or more
// required Android permissions are missing.  Tapping it navigates to the
// setup checklist screen so the user can fix the issue.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/app_localizations.dart';

/// Full-width red banner warning that permissions are missing.
///
/// Navigates to `/setup-checklist` when tapped.
class PermissionWarningBar extends StatelessWidget {
  const PermissionWarningBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      onTap: () => context.push('/setup-checklist'),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE), // light red background
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE53935), width: 1.5),
        ),
        child: Row(
          children: [
            // Warning emoji — universally understood across locales.
            const Text('⚠️', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.permWarningTitle,
                style: const TextStyle(
                  fontFamily: 'NotoSansMalayalam',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFB71C1C), // deep red text
                ),
              ),
            ),
            // Chevron to indicate tappability.
            const Icon(
              Icons.chevron_right,
              color: Color(0xFFE53935),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
