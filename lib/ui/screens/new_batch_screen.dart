import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hatcher/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/extensions.dart';
import '../../core/method_channel.dart';
import '../../data/models/batch.dart';
import '../../data/models/settings_model.dart';
import '../../providers/batch_provider.dart';
import '../../providers/settings_provider.dart';

class NewBatchScreen extends ConsumerStatefulWidget {
  const NewBatchScreen({super.key});

  @override
  ConsumerState<NewBatchScreen> createState() => _NewBatchScreenState();
}

class _NewBatchScreenState extends ConsumerState<NewBatchScreen> {
  late DateTime _placedDate;
  final _eggController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _placedDate = nowKolkata();
  }

  @override
  void dispose() {
    _eggController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = nowKolkata();
    final picked = await showDatePicker(
      context: context,
      initialDate: _placedDate,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked != null && picked != _placedDate) {
      setState(() => _placedDate = picked);
    }
  }

  Future<bool> _confirmEndBatch(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.endBatch),
        content: Text(l10n.endBatchConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.yes),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _handleEndBatch(Batch activeBatch) async {
    final confirmed = await _confirmEndBatch(context);
    if (!confirmed) return;

    setState(() => _loading = true);
    try {
      final endBatch = ref.read(endBatchProvider);
      await endBatch(activeBatch.id);
      await HatcherChannel.cancelAlarms();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ബാച്ച് അവസാനിപ്പിച്ചു / Batch ended.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final eggCount = int.parse(_eggController.text.trim());
      final placedDateStr = _placedDate.kolkataDate();
      final createBatch = ref.read(createBatchProvider);
      await createBatch(placedDate: placedDateStr, eggCount: eggCount);

      // Reschedule alarms for the new batch
      final settings = ref.read(settingsProvider).value ?? SettingsModel.defaults();
      await HatcherChannel.scheduleAlarms(
        placedDate: placedDateStr,
        slots: settings.slots,
        stopFromDay: settings.stopRemindersFromDay,
        candlingDays: settings.candlingDays,
      );

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final activeBatchAsync = ref.watch(activeBatchProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.newBatch)),
      body: activeBatchAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (activeBatch) => _buildBody(context, l10n, activeBatch),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    Batch? activeBatch,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (activeBatch != null) ...[
            _ActiveBatchCard(
              batch: activeBatch,
              loading: _loading,
              onEndBatch: () => _handleEndBatch(activeBatch),
              l10n: l10n,
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),
          ],
          Text(
            l10n.newBatch,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DatePickerField(
                  label: l10n.placedDate,
                  date: _placedDate,
                  onTap: () => _pickDate(context),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _eggController,
                  decoration: InputDecoration(
                    labelText: l10n.eggCount,
                    hintText: '1 – 999',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  validator: (val) {
                    if (val == null || val.isEmpty) {
                      return l10n.eggCount;
                    }
                    final n = int.tryParse(val);
                    if (n == null || n < 1 || n > 999) {
                      return '1 – 999';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _loading ? null : _handleSubmit,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(l10n.newBatch),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveBatchCard extends StatelessWidget {
  const _ActiveBatchCard({
    required this.batch,
    required this.loading,
    required this.onEndBatch,
    required this.l10n,
  });

  final Batch batch;
  final bool loading;
  final VoidCallback onEndBatch;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final placedDateTime = batch.placedDate.toKolkataDateTime();
    final dateLabel = DateFormat('dd MMM yyyy').format(placedDateTime);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'സജീവ ബാച്ച് / Active Batch',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('${l10n.placedDate}: $dateLabel'),
            Text('${l10n.eggCount}: ${batch.eggCount}'),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: loading ? null : onEndBatch,
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 1.5,
                ),
              ),
              child: Text(l10n.endBatch),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final formatted = DateFormat('dd MMM yyyy').format(date);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
        ),
        child: Text(
          formatted,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
