import 'package:flutter/material.dart';
import 'package:hatcher/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/extensions.dart';
import '../../data/models/batch.dart';
import '../../data/models/rotation.dart';
import '../../data/models/settings_model.dart';
import '../../data/models/slot_status.dart';
import '../../providers/batch_provider.dart';
import '../../providers/day_counter_provider.dart';
import '../../providers/permission_provider.dart';
import '../../providers/rotation_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/day_banner.dart';
import '../widgets/gateway_status_chip.dart';
import '../widgets/lockdown_banner.dart';
import '../widgets/permission_warning_bar.dart';
import '../widgets/slot_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final batchAsync = ref.watch(activeBatchProvider);

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.egg_outlined),
            tooltip: l10n.newBatch,
            onPressed: () => context.push('/new-batch'),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: l10n.history,
            onPressed: () => context.push('/history'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.settings,
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: batchAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorBody(message: e.toString()),
        data: (batch) {
          if (batch == null) {
            return _NoBatchBody(l10n: l10n);
          }
          return _ActiveBatchBody(batch: batch, l10n: l10n);
        },
      ),
    );
  }
}

class _NoBatchBody extends StatelessWidget {
  const _NoBatchBody({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🥚', style: TextStyle(fontSize: 72)),
            const SizedBox(height: 20),
            Text(
              l10n.noBatchActive,
              style: const TextStyle(
                fontFamily: 'NotoSansMalayalam',
                fontSize: 20,
                color: Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: Text(l10n.startNewBatch),
              onPressed: () => context.push('/new-batch'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveBatchBody extends ConsumerWidget {
  const _ActiveBatchBody({required this.batch, required this.l10n});

  final Batch batch;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(dayCounterProvider);
    final hatchDate = ref.watch(hatchDateProvider);
    final isLockdown = ref.watch(isLockdownProvider);
    final permsOk = ref.watch(hasAllPermissionsProvider);
    final rotationsAsync = ref.watch(todayRotationsProvider);
    final settingsAsync = ref.watch(settingsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(todayRotationsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // ── Day progress banner ──────────────────────────────────────────
          if (day != null && hatchDate != null)
            DayBanner(day: day, hatchDate: hatchDate)
          else
            const SizedBox(height: 8),

          // ── Phase 2: Gateway Status Chip ─────────────────────────────────
          const Align(
            alignment: Alignment.centerLeft,
            child: GatewayStatusChip(),
          ),

          // ── Lockdown warning ─────────────────────────────────────────────
          if (isLockdown) const LockdownBanner(),

          // ── Permission warning ───────────────────────────────────────────
          if (!permsOk) const PermissionWarningBar(),

          // ── Slot cards ───────────────────────────────────────────────────
          rotationsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _ErrorBody(message: e.toString()),
            data: (rotations) {
              final settings = settingsAsync.value ?? SettingsModel.defaults();
              final now = nowKolkata();

              final morningTime = settings.slots[kSlotMorning] ?? '08:30';
              final noonTime = settings.slots[kSlotNoon] ?? '13:30';
              final eveningTime = settings.slots[kSlotEvening] ?? '20:30';

              return Column(
                children: [
                  _buildSlotCard(
                    context: context,
                    ref: ref,
                    slotKey: kSlotMorning,
                    slotLabel: l10n.slotMorning,
                    slotTime: morningTime,
                    nextSlotTime: noonTime,
                    symbol: l10n.slotSymbolMorning,
                    rotation: rotations[kSlotMorning],
                    isLockdown: isLockdown,
                    batch: batch,
                    nowKolkata: now,
                  ),
                  _buildSlotCard(
                    context: context,
                    ref: ref,
                    slotKey: kSlotNoon,
                    slotLabel: l10n.slotNoon,
                    slotTime: noonTime,
                    nextSlotTime: eveningTime,
                    symbol: l10n.slotSymbolNoon,
                    rotation: rotations[kSlotNoon],
                    isLockdown: isLockdown,
                    batch: batch,
                    nowKolkata: now,
                  ),
                  _buildSlotCard(
                    context: context,
                    ref: ref,
                    slotKey: kSlotEvening,
                    slotLabel: l10n.slotEvening,
                    slotTime: eveningTime,
                    nextSlotTime: null,
                    symbol: l10n.slotSymbolEvening,
                    rotation: rotations[kSlotEvening],
                    isLockdown: isLockdown,
                    batch: batch,
                    nowKolkata: now,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSlotCard({
    required BuildContext context,
    required WidgetRef ref,
    required String slotKey,
    required String slotLabel,
    required String slotTime,
    required String? nextSlotTime,
    required String symbol,
    required Rotation? rotation,
    required bool isLockdown,
    required Batch batch,
    required DateTime nowKolkata,
  }) {
    final status = computeSlotStatus(
      rotation: rotation,
      slotTimeStr: slotTime,
      nextSlotTimeStr: nextSlotTime,
      nowKolkata: nowKolkata,
    );

    final addRotation = ref.read(addRotationProvider);

    return SlotCard(
      slotKey: slotKey,
      slotLabel: slotLabel,
      slotTime: slotTime,
      symbol: symbol,
      status: status,
      rotation: rotation,
      isLockdown: isLockdown,
      onRotated: () async {
        try {
          await addRotation(
            slot: slotKey,
            batchId: batch.id,
          );
        } catch (e) {
          if (!context.mounted) return;
          final msg = e.toString().contains('already_done')
              ? 'മറ്റൊരാൾ ഇതിനകം രേഖപ്പെടുത്തി! / Already logged!'
              : 'Error saving rotation: $e';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: kError),
          );
        }
      },
      onSnooze: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.btnSnooze),
          ),
        );
      },
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
