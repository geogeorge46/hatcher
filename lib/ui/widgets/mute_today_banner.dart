// lib/ui/widgets/mute_today_banner.dart
//
// Widget allowing the owner to completely silence notifications, alarms,
// and escalation calls for 1 day, 2 days, 3 days, or custom dates
// (e.g. while in a function, wedding, ceremony, event, or travel).
//
// Automatically resumes when the chosen duration expires.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/extensions.dart';
import '../../core/method_channel.dart';
import '../../data/firestore_service.dart';
import '../../data/local_prefs.dart';
import '../../data/models/settings_model.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';

class MuteTodayBanner extends ConsumerWidget {
  const MuteTodayBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settingsAsync = ref.watch(settingsProvider);
    final today = nowKolkata();
    final todayStr = today.kolkataDate();

    final settings = settingsAsync.value ?? SettingsModel.defaults();
    final effectiveMutedUntil =
        settings.mutedUntilDate ?? settings.mutedDate ?? LocalPrefs.mutedUntilDate;

    final isMuted = effectiveMutedUntil != null &&
        effectiveMutedUntil.isNotEmpty &&
        todayStr.compareTo(effectiveMutedUntil) <= 0;

    // Keep native Android and local prefs in sync with Firestore
    if (settings.mutedUntilDate != null &&
        settings.mutedUntilDate != LocalPrefs.mutedUntilDate) {
      LocalPrefs.mutedUntilDate = settings.mutedUntilDate;
      HatcherChannel.setMutedDate(settings.mutedUntilDate);
    }

    if (isMuted && effectiveMutedUntil != null) {
      final isSingleDay = effectiveMutedUntil == todayStr;
      final untilDt = DateTime.tryParse(effectiveMutedUntil);
      final daysLeft = untilDt != null ? untilDt.difference(DateTime(today.year, today.month, today.day)).inDays + 1 : 1;

      final title = isSingleDay
          ? l10n.mutedTodayBanner
          : 'അറിയിപ്പുകൾ നിർത്തിയിരിക്കുന്നു ($effectiveMutedUntil വരെ)';
      final subtitle = isSingleDay
          ? l10n.mutedTodayAutoResume
          : '$daysLeft ദിവസം ബാക്കി • കാലാവധി കഴിഞ്ഞാൽ പഴയപടി പ്രവർത്തിക്കും';

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0), // Amber light background
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFB74D), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFFFE0B2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_off_rounded,
                color: Color(0xFFE65100),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'NotoSansMalayalam',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE65100),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'NotoSansMalayalam',
                      fontSize: 12,
                      color: Color(0xFFBF360C),
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              onPressed: () async {
                try {
                  await ref.read(firestoreServiceProvider).unmuteToday();
                  LocalPrefs.mutedUntilDate = null;
                  await HatcherChannel.setMutedDate(null);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.notificationsResumed)),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: Text(
                l10n.btnResumeNotifications,
                style: const TextStyle(
                  fontFamily: 'NotoSansMalayalam',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // When NOT muted: show prominent button / action card
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showMuteOptions(context, ref, l10n, today, todayStr),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE7F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.do_not_disturb_on_outlined,
                    color: Color(0xFF5E35B1),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.muteToday,
                        style: const TextStyle(
                          fontFamily: 'NotoSansMalayalam',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF263238),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.muteTodaySubtitle,
                        style: TextStyle(
                          fontFamily: 'NotoSansMalayalam',
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMuteOptions(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    DateTime today,
    String todayStr,
  ) async {
    final option = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_off, color: Color(0xFFE65100)),
                      const SizedBox(width: 10),
                      Text(
                        l10n.muteConfirmTitle,
                        style: const TextStyle(
                          fontFamily: 'NotoSansMalayalam',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Text(
                    'ഫംഗ്ഷനിലോ ചടങ്ങിലോ ഉള്ളപ്പോൾ അറിയിപ്പുകളും കോളുകളും നിർത്താൻ കാലാവധി തിരഞ്ഞെടുക്കൂ:',
                    style: TextStyle(
                      fontFamily: 'NotoSansMalayalam',
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                const Divider(height: 20),
                ListTile(
                  leading: const Icon(Icons.today, color: Color(0xFFE65100)),
                  title: const Text('ഇന്ന് മാത്രം / Today only (1 day)'),
                  subtitle: Text('നാളെ രാവിലെ പഴയപടി പുനരാരംഭിക്കും (മുട്ട: $todayStr)'),
                  onTap: () => Navigator.pop(ctx, todayStr),
                ),
                ListTile(
                  leading: const Icon(Icons.filter_2, color: Color(0xFFE65100)),
                  title: const Text('2 ദിവസത്തേക്ക് / For 2 days'),
                  subtitle: Text(today.add(const Duration(days: 1)).kolkataDate() + ' വരെ'),
                  onTap: () => Navigator.pop(ctx, today.add(const Duration(days: 1)).kolkataDate()),
                ),
                ListTile(
                  leading: const Icon(Icons.filter_3, color: Color(0xFFE65100)),
                  title: const Text('3 ദിവസത്തേക്ക് / For 3 days'),
                  subtitle: Text(today.add(const Duration(days: 2)).kolkataDate() + ' വരെ'),
                  onTap: () => Navigator.pop(ctx, today.add(const Duration(days: 2)).kolkataDate()),
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_month, color: Color(0xFF5E35B1)),
                  title: const Text('തീയതി തിരഞ്ഞെടുക്കൂ / Pick custom end date...'),
                  subtitle: const Text('നിങ്ങൾക്ക് ആവശ്യമുള്ള ദിവസം വരെ നിർത്താം'),
                  onTap: () async {
                    Navigator.pop(ctx, 'pick');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (option == null || !context.mounted) return;

    String? selectedUntil = option;
    if (option == 'pick') {
      final picked = await showDatePicker(
        context: context,
        initialDate: today.add(const Duration(days: 1)),
        firstDate: today,
        lastDate: today.add(const Duration(days: 25)),
      );
      if (picked != null) {
        selectedUntil = picked.kolkataDate();
      } else {
        selectedUntil = null;
      }
    }

    if (selectedUntil != null && context.mounted) {
      try {
        await ref.read(firestoreServiceProvider).muteUntil(selectedUntil);
        LocalPrefs.mutedUntilDate = selectedUntil;
        await HatcherChannel.setMutedDate(selectedUntil);
        if (context.mounted) {
          final isSingle = selectedUntil == todayStr;
          final msg = isSingle
              ? '${l10n.mutedTodayBanner} – ${l10n.mutedTodayAutoResume}'
              : 'അറിയിപ്പുകൾ $selectedUntil വരെ നിർത്തിവെച്ചിരിക്കുന്നു';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: const Color(0xFFE65100),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }
}
