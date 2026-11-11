import 'package:flutter/material.dart';
import 'package:hatcher/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../core/extensions.dart';
import '../../data/models/batch.dart';
import '../../data/models/rotation.dart';
import '../../providers/batch_provider.dart';
import '../../providers/phase2_providers.dart';
import '../../providers/rotation_provider.dart';

final _selectedBatchIdProvider = StateProvider<String?>((ref) => null);

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final selectedBatchId = ref.watch(_selectedBatchIdProvider);

    final allBatchesAsync = ref.watch(allBatchesProvider);
    final rotationsAsync = selectedBatchId == null
        ? ref.watch(allRotationsProvider)
        : ref.watch(rotationsForBatchProvider(selectedBatchId));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.history),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.amberAccent,
            tabs: [
              Tab(icon: Icon(Icons.rotate_right), text: 'Rotations'),
              Tab(icon: Icon(Icons.notifications_active), text: 'Alerts'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            allBatchesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(e.toString())),
              data: (batches) => rotationsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(e.toString())),
                data: (rotations) => _buildBody(
                  context,
                  ref,
                  l10n,
                  batches,
                  rotations,
                  selectedBatchId,
                ),
              ),
            ),
            const _AlertsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    List<Batch> batches,
    List<Rotation> rotations,
    String? selectedBatchId,
  ) {
    return Column(
      children: [
        _BatchFilterDropdown(
          batches: batches,
          selectedBatchId: selectedBatchId,
          l10n: l10n,
          onChanged: (batchId) =>
              ref.read(_selectedBatchIdProvider.notifier).state = batchId,
        ),
        const Divider(height: 1),
        Expanded(
          child: rotations.isEmpty
              ? Center(child: Text(l10n.noBatchActive))
              : _HistoryList(
                  rotations: rotations,
                  batches: batches,
                  selectedBatchId: selectedBatchId,
                  l10n: l10n,
                  ref: ref,
                ),
        ),
      ],
    );
  }
}

class _BatchFilterDropdown extends StatelessWidget {
  const _BatchFilterDropdown({
    required this.batches,
    required this.selectedBatchId,
    required this.l10n,
    required this.onChanged,
  });

  final List<Batch> batches;
  final String? selectedBatchId;
  final AppLocalizations l10n;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(l10n.filterByBatch,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<String?>(
              isExpanded: true,
              value: selectedBatchId,
              onChanged: onChanged,
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l10n.allBatches),
                ),
                ...batches.map((b) {
                  final label = DateFormat('dd MMM yyyy')
                      .format(b.placedDate.toKolkataDateTime());
                  return DropdownMenuItem<String?>(
                    value: b.id,
                    child: Text('$label (${b.eggCount} eggs)'),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.rotations,
    required this.batches,
    required this.selectedBatchId,
    required this.l10n,
    required this.ref,
  });

  final List<Rotation> rotations;
  final List<Batch> batches;
  final String? selectedBatchId;
  final AppLocalizations l10n;
  final WidgetRef ref;

  List<Batch> get _relevantBatches => selectedBatchId == null
      ? batches
      : batches.where((b) => b.id == selectedBatchId).toList();

  Map<String, List<Rotation>> _groupByDate(List<Rotation> rots) {
    final map = <String, List<Rotation>>{};
    for (final r in rots) {
      map.putIfAbsent(r.date, () => []).add(r);
    }
    return map;
  }

  Set<String> _allDateKeys() {
    final today = nowKolkata();
    final keys = <String>{};
    for (final batch in _relevantBatches) {
      var current = batch.placedDate.toKolkataDateTime();
      final end = today;
      while (!current.isAfter(end)) {
        keys.add(current.kolkataDate());
        current = current.add(const Duration(days: 1));
      }
    }
    // Also include any dates present in rotations
    for (final r in rotations) {
      keys.add(r.date);
    }
    return keys;
  }

  String _symbol(String slot) {
    switch (slot) {
      case kSlotMorning:
        return l10n.slotSymbolMorning;
      case kSlotNoon:
        return l10n.slotSymbolNoon;
      case kSlotEvening:
        return l10n.slotSymbolEvening;
      default:
        return '•';
    }
  }

  String _slotName(String slot) {
    switch (slot) {
      case kSlotMorning:
        return l10n.slotMorning;
      case kSlotNoon:
        return l10n.slotNoon;
      case kSlotEvening:
        return l10n.slotEvening;
      default:
        return slot;
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDate(rotations);
    final allKeys = _allDateKeys();

    final sortedDates = allKeys.toList()..sort((a, b) => b.compareTo(a));
    final now = nowKolkata();

    final items = <_ListItem>[];
    for (final dateKey in sortedDates) {
      items.add(_DateHeaderItem(dateKey));
      final rotationsOnDate = grouped[dateKey] ?? [];
      final rotationsBySlot = {
        for (final r in rotationsOnDate) r.slot: r,
      };
      final isPast = dateKey.compareTo(now.kolkataDate()) < 0;
      for (final slot in kSlots) {
        final rotation = rotationsBySlot[slot];
        if (rotation != null) {
          items.add(_DoneRotationItem(rotation, slot));
        } else if (isPast) {
          items.add(_MissedSlotItem(dateKey, slot));
        }
      }
    }

    if (items.isEmpty) {
      return Center(child: Text(l10n.noBatchActive));
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is _DateHeaderItem) {
          return _buildDateHeader(context, item.dateKey);
        } else if (item is _DoneRotationItem) {
          return _buildDoneRow(context, item.rotation, item.slot, now);
        } else if (item is _MissedSlotItem) {
          return _buildMissedRow(context, item.slot);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildDateHeader(BuildContext context, String dateKey) {
    final dt = dateKey.toKolkataDateTime();
    final label = DateFormat('dd MMM yyyy').format(dt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.bold, color: Colors.blueGrey),
      ),
    );
  }

  Widget _buildDoneRow(
    BuildContext context,
    Rotation rotation,
    String slot,
    DateTime now,
  ) {
    final doneDateTime = rotation.doneAt.toDate();
    final withinUndoWindow =
        now.difference(doneDateTime).inMinutes.abs() <= 10;
    final timeLabel = rotation.formattedTime(kTimezone);

    return ListTile(
      dense: true,
      leading: const Text(
        '✔',
        style: TextStyle(color: Colors.green, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      title: Text('${_symbol(slot)}  ${_slotName(slot)}'),
      subtitle: Text(
        l10n.statusDoneBy(rotation.doneBy, timeLabel),
        style: const TextStyle(fontSize: 13),
      ),
      trailing: withinUndoWindow
          ? IconButton(
              tooltip: l10n.undo,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _confirmUndo(context, rotation),
            )
          : null,
    );
  }

  Widget _buildMissedRow(BuildContext context, String slot) {
    return ListTile(
      dense: true,
      leading: const Text(
        '✘',
        style: TextStyle(color: Colors.red, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      title: Text('${_symbol(slot)}  ${_slotName(slot)}'),
      subtitle: Text(
        l10n.statusMissed,
        style: const TextStyle(color: Colors.red, fontSize: 13),
      ),
    );
  }

  Future<void> _confirmUndo(
      BuildContext context, Rotation rotation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.undo),
        content: Text(l10n.undoConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.confirmOk),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final undoRotation = ref.read(undoRotationProvider);
        await undoRotation(rotation.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error undoing rotation: $e')),
          );
        }
      }
    }
  }
}

abstract class _ListItem {}

class _DateHeaderItem extends _ListItem {
  _DateHeaderItem(this.dateKey);
  final String dateKey;
}

class _DoneRotationItem extends _ListItem {
  _DoneRotationItem(this.rotation, this.slot);
  final Rotation rotation;
  final String slot;
}

class _MissedSlotItem extends _ListItem {
  _MissedSlotItem(this.dateKey, this.slot);
  final String dateKey;
  final String slot;
}

class _AlertsTab extends ConsumerWidget {
  const _AlertsTab();

  IconData _iconForChannel(String channel) {
    switch (channel) {
      case 'call':
        return Icons.call;
      case 'sms':
        return Icons.sms;
      case 'telegram':
        return Icons.send;
      case 'fcm':
        return Icons.notifications;
      default:
        return Icons.info_outline;
    }
  }

  Color _colorForResult(String result) {
    final lower = result.toLowerCase();
    if (lower.contains('failed') || lower.contains('missed')) return Colors.red;
    if (lower.contains('no answer') || lower.contains('skipped')) {
      return Colors.orange;
    }
    return Colors.green;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(auditLogsProvider);
    return logsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading alerts: $e')),
      data: (logs) {
        if (logs.isEmpty) {
          return const Center(
            child: Text('No escalation alerts logged yet.'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: logs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final log = logs[i];
            final ts = log.timestamp != null
                ? DateFormat('dd MMM, h:mm a').format(log.timestamp!.toKolkata())
                : log.date;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: _colorForResult(log.result).withOpacity(0.12),
                child: Icon(
                  _iconForChannel(log.channel),
                  color: _colorForResult(log.channel == 'call' ? log.result : 'ok'),
                ),
              ),
              title: Text(
                '${log.channel.toUpperCase()} → ${log.targetName} (${log.slotKey})',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: Text(
                '${log.result}${log.details.isNotEmpty ? ' · ${log.details}' : ''}\n$ts',
                style: const TextStyle(fontSize: 12),
              ),
              isThreeLine: true,
            );
          },
        );
      },
    );
  }
}
