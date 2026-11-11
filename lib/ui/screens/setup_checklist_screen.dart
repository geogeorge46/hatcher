// lib/ui/screens/setup_checklist_screen.dart
//
// SetupChecklistScreen – guides the user through granting every Android
// permission that Hatcher needs to deliver reliable, on-time alarms.
//
// Why each permission matters:
//   POST_NOTIFICATIONS  – Android 13+ requires explicit permission to show any
//                         notification. Without it alarms are silent.
//   SCHEDULE_EXACT_ALARM – Required on Android 12+ to fire alarms at an exact
//                          moment (e.g. 7:00 AM sharp).
//   USE_FULL_SCREEN_INTENT – Lets the alarm activity launch over the lock screen
//                            so the user can confirm a rotation without unlocking.
//   ACCESS_NOTIFICATION_POLICY – Allows the app to ring even when the phone is
//                                 on Do-Not-Disturb / silent.
//   Battery unrestricted – Prevents Android from killing the alarm service to
//                          save battery (crucial on cheap/aggressive OEM ROMs).
//   Auto-start (OEM) – Xiaomi / Oppo / Vivo / Realme ROMs require a separate
//                       "Auto-start" permission to allow background wake-ups.
//
// Architecture notes:
//   • Permissions are fetched once from the platform via HatcherChannel and
//     held in a [FutureProvider].  The AppBar has a refresh button that
//     invalidates the provider so it re-fetches.
//   • Auto-start is only shown when Build.MANUFACTURER matches a known OEM
//     (detected by HatcherChannel returning a 'manufacturer' key).
//   • tapping "Open Settings" for each item calls
//     HatcherChannel.openPermissionSettings(key) which routes to the correct
//     Android settings screen (not all have a programmatic grant path).

import 'package:flutter/material.dart';
import 'package:hatcher/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/method_channel.dart';
import '../../providers/permission_provider.dart';

// ---------------------------------------------------------------------------
// SetupChecklistScreen
// ---------------------------------------------------------------------------

class SetupChecklistScreen extends ConsumerWidget {
  const SetupChecklistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final permsAsync = ref.watch(permissionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.setupChecklist),
        actions: [
          // Refresh button re-checks all permissions from the platform.
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(permissionsProvider),
          ),
        ],
      ),
      body: permsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (perms) => _buildList(context, l10n, perms, ref),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // List builder
  // ---------------------------------------------------------------------------

  Widget _buildList(
    BuildContext context,
    AppLocalizations l10n,
    Map<String, bool> perms,
    WidgetRef ref,
  ) {
    // Show the OEM auto-start row if the native check detected an OEM autostart screen.
    final showAutostart = !(perms['autostart'] ?? true);

    final items = <_ChecklistItem>[
      _ChecklistItem(
        key: 'notifications',
        granted: perms['notifications'] ?? false,
        titleEn: l10n.checklistNotifications,
        titleMl: 'അറിയിപ്പ് അനുവദിക്കൽ',
        descriptionEn:
            'Required on Android 13+ to display any notification. '
            'Without this, all rotation alarms will be silent.',
        descriptionMl:
            'Android 13-ൽ അറിയിപ്പ് കാണിക്കാൻ ഇത് ആവശ്യമാണ്. '
            'ഇല്ലെങ്കിൽ എല്ലാ അലാറങ്ങളും നിശബ്ദമായിരിക്കും.',
      ),
      _ChecklistItem(
        key: 'exact_alarm',
        granted: perms['exact_alarm'] ?? false,
        titleEn: l10n.checklistExactAlarm,
        titleMl: 'കൃത്യസമയ അലാറം',
        descriptionEn:
            'Needed on Android 12+ to fire alarms at the exact scheduled '
            'minute rather than within a loose time window.',
        descriptionMl:
            'Android 12-ൽ ആലോചിച്ച സമയത്ത് തന്നെ അലാറം ഉണർത്താൻ ഇത് ആവശ്യമാണ്.',
      ),
      _ChecklistItem(
        key: 'full_screen_intent',
        granted: perms['full_screen_intent'] ?? false,
        titleEn: l10n.checklistFullscreen,
        titleMl: 'ഫുൾ-സ്ക്രീൻ ഇൻ്റൻ്റ്',
        descriptionEn:
            'Allows the alarm screen to appear over the lock screen so '
            'you can confirm a rotation without unlocking the phone.',
        descriptionMl:
            'ഫോൺ അൺലോക്ക് ചെയ്യാതെ തന്നെ ലോക്ക്-സ്ക്രീനിൽ അലാറം കാണിക്കാൻ.',
      ),
      _ChecklistItem(
        key: 'dnd_access',
        granted: perms['dnd_access'] ?? false,
        titleEn: l10n.checklistDnd,
        titleMl: 'ഡോ നോട്ട് ഡിസ്റ്റർബ് ആക്സസ്',
        descriptionEn:
            'Without DND access, alarms may be silenced when the phone '
            'is in Do-Not-Disturb or Silent mode.',
        descriptionMl:
            'ഡോ-നോട്ട്-ഡിസ്റ്റർബ് ഓണായിരിക്കുമ്പോൾ അലാറം മുഴങ്ങാൻ ഇത് ആവശ്യമാണ്.',
      ),
      _ChecklistItem(
        key: 'battery_optimization',
        granted: perms['battery_optimization'] ?? false,
        titleEn: l10n.checklistBattery,
        titleMl: 'ബാറ്ററി ഒപ്റ്റിമൈസേഷൻ ഒഴിവാക്കൽ',
        descriptionEn:
            'Prevents Android from killing the alarm service to save '
            'battery. Essential on budget ROMs (Xiaomi MIUI, ColorOS, etc.).',
        descriptionMl:
            'ബാറ്ററി ലാഭിക്കാൻ Android അലാറം സർവീസ് നിർത്തുന്നത് തടയുന്നു. '
            'ബജറ്റ് ഫോണുകളിൽ ഇത് വളരെ പ്രധാനമാണ്.',
      ),
      if (showAutostart)
        _ChecklistItem(
          key: 'autostart',
          granted: perms['autostart'] ?? false,
          titleEn: l10n.checklistAutostart,
          titleMl: 'ഓട്ടോ-സ്റ്റാർട്ട് (Xiaomi/Oppo/Vivo)',
          descriptionEn:
              'Xiaomi, Oppo, Vivo, and Realme ROMs have an extra '
              '"Auto-start" permission. Without it, the app cannot start '
              'at boot and alarms will not fire after a reboot.',
          descriptionMl:
              'ഇന്ത്യൻ ബ്രാൻഡ് ഫോണുകളിൽ റീബൂട്ടിന് ശേഷം ആപ്പ് ആരംഭിക്കാൻ '
              'ഓട്ടോ-സ്റ്റാർട്ട് അനുമതി ആവശ്യമാണ്.',
        ),
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, i) => _ChecklistCard(
        item: items[i],
        l10n: l10n,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ChecklistCard
// ---------------------------------------------------------------------------

/// A single permission row rendered as a [Card].
class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({required this.item, required this.l10n});

  final _ChecklistItem item;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status icon
            Icon(
              item.granted ? Icons.check_circle : Icons.cancel,
              color: item.granted ? Colors.green : Colors.red,
              size: 28,
            ),
            const SizedBox(width: 12),

            // Text block
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Primary title (localised label from ARB)
                  Text(
                    item.titleEn,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  // Malayalam subtitle
                  Text(
                    item.titleMl,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 6),
                  // Description (English)
                  Text(
                    item.descriptionEn,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  // Description (Malayalam)
                  Text(
                    item.descriptionMl,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  // Open Settings button – routes to the platform settings page.
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed: () =>
                          HatcherChannel.openPermissionSettings(item.key),
                      child: Text(l10n.openSettings),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ChecklistItem data class
// ---------------------------------------------------------------------------

class _ChecklistItem {
  const _ChecklistItem({
    required this.key,
    required this.granted,
    required this.titleEn,
    required this.titleMl,
    required this.descriptionEn,
    required this.descriptionMl,
  });

  /// The string key passed to [HatcherChannel.openPermissionSettings].
  /// Must match the `when` branch in MainActivity.kt.
  final String key;

  /// Whether the permission is currently granted.
  final bool granted;

  final String titleEn;
  final String titleMl;
  final String descriptionEn;
  final String descriptionMl;
}
