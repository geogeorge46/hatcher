import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hatcher/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../core/constants.dart';
import '../../core/extensions.dart';
import '../../core/method_channel.dart';
import '../../data/local_prefs.dart';
import '../../data/models/settings_model.dart';
import '../../providers/batch_provider.dart';
import '../../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _languageCode = 'ml';
  TimeOfDay _morningTime = const TimeOfDay(hour: 8, minute: 30);
  TimeOfDay _noonTime = const TimeOfDay(hour: 13, minute: 30);
  TimeOfDay _eveningTime = const TimeOfDay(hour: 20, minute: 30);

  bool _neverStop = false;

  final _stopFromDayController = TextEditingController();
  final _snoozeController = TextEditingController();
  final _repeatController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _languageCode = LocalPrefs.languageCode ?? 'ml';
  }

  @override
  void dispose() {
    _stopFromDayController.dispose();
    _snoozeController.dispose();
    _repeatController.dispose();
    super.dispose();
  }

  TimeOfDay _parseTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      return TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    } catch (_) {
      return const TimeOfDay(hour: 8, minute: 30);
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _populate(SettingsModel s) {
    if (_initialised) return;
    _initialised = true;

    final morningStr = s.slots[kSlotMorning] ?? '08:30';
    final noonStr = s.slots[kSlotNoon] ?? '13:30';
    final eveningStr = s.slots[kSlotEvening] ?? '20:30';

    _morningTime = _parseTime(morningStr);
    _noonTime = _parseTime(noonStr);
    _eveningTime = _parseTime(eveningStr);

    _neverStop = s.stopRemindersFromDay == 0;
    _stopFromDayController.text =
        s.stopRemindersFromDay == 0 ? '' : s.stopRemindersFromDay.toString();
    _snoozeController.text = s.snoozeMinutes.toString();
    _repeatController.text = s.repeatMinutes.toString();
  }

  Future<void> _pickTime(BuildContext context, String slot) async {
    final initial = slot == kSlotMorning
        ? _morningTime
        : slot == kSlotNoon
            ? _noonTime
            : _eveningTime;

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return;
    setState(() {
      if (slot == kSlotMorning) _morningTime = picked;
      if (slot == kSlotNoon) _noonTime = picked;
      if (slot == kSlotEvening) _eveningTime = picked;
    });
  }

  Future<void> _changeLanguage(String code) async {
    setState(() => _languageCode = code);
    LocalPrefs.languageCode = code;
    ref.read(languageProvider.notifier).state = Locale(code);
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final stopDay = _neverStop
          ? 0
          : (int.tryParse(_stopFromDayController.text) ?? kDefaultStopFromDay);
      final snooze =
          int.tryParse(_snoozeController.text) ?? kDefaultSnoozeMinutes;
      final repeat =
          int.tryParse(_repeatController.text) ?? kDefaultRepeatMinutes;

      final slots = {
        kSlotMorning: _formatTimeOfDay(_morningTime),
        kSlotNoon: _formatTimeOfDay(_noonTime),
        kSlotEvening: _formatTimeOfDay(_eveningTime),
      };

      final updated = SettingsModel(
        slots: slots,
        stopRemindersFromDay: stopDay,
        candlingDays: kDefaultCandlingDays,
        snoozeMinutes: snooze,
        repeatMinutes: repeat,
      );

      // 1. Save to Firestore
      await ref.read(saveSettingsProvider)(updated);

      // 2. Schedule native alarms
      final activeBatch = ref.read(activeBatchProvider).value;
      final placedDateStr = activeBatch?.placedDate ?? nowKolkata().kolkataDate();

      await HatcherChannel.scheduleAlarms(
        placedDate: placedDateStr,
        slots: slots,
        stopFromDay: stopDay,
        candlingDays: kDefaultCandlingDays,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.done)),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (settings) {
          _populate(settings);
          return _buildForm(context, l10n);
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context, AppLocalizations l10n) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Language ---------------------------------------------------
          _SectionHeader(label: l10n.language),
          RadioListTile<String>(
            title: const Text('മലയാളം'),
            value: 'ml',
            groupValue: _languageCode,
            onChanged: (v) => _changeLanguage(v!),
          ),
          RadioListTile<String>(
            title: const Text('English'),
            value: 'en',
            groupValue: _languageCode,
            onChanged: (v) => _changeLanguage(v!),
          ),
          const Divider(),

          // ---- Slot alarm times -------------------------------------------
          _SectionHeader(label: l10n.slotTimes),
          _TimePickerTile(
            label: l10n.slotMorning,
            symbol: l10n.slotSymbolMorning,
            time: _morningTime,
            onTap: () => _pickTime(context, kSlotMorning),
          ),
          _TimePickerTile(
            label: l10n.slotNoon,
            symbol: l10n.slotSymbolNoon,
            time: _noonTime,
            onTap: () => _pickTime(context, kSlotNoon),
          ),
          _TimePickerTile(
            label: l10n.slotEvening,
            symbol: l10n.slotSymbolEvening,
            time: _eveningTime,
            onTap: () => _pickTime(context, kSlotEvening),
          ),
          const Divider(),

          // ---- Stop alarms from day ---------------------------------------
          _SectionHeader(label: l10n.stopFromDay),
          SwitchListTile(
            title: Text(l10n.stopFromDayOff),
            value: _neverStop,
            onChanged: (v) => setState(() {
              _neverStop = v;
              if (v) _stopFromDayController.clear();
            }),
          ),
          if (!_neverStop) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _stopFromDayController,
              decoration: InputDecoration(
                labelText: l10n.stopFromDay,
                hintText: '1 – 21',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              validator: (val) {
                if (_neverStop) return null;
                final n = int.tryParse(val ?? '');
                if (n == null || n < 1 || n > 21) return '1 – 21';
                return null;
              },
            ),
          ],
          const Divider(),

          // ---- Snooze minutes ---------------------------------------------
          _SectionHeader(label: l10n.snoozeMinutes),
          TextFormField(
            controller: _snoozeController,
            decoration: InputDecoration(
              labelText: l10n.snoozeMinutes,
              hintText: '5 / 10 / 15 / 20',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            validator: (val) {
              final n = int.tryParse(val ?? '');
              if (n == null || n < 1 || n > 60) return '1 – 60';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // ---- Repeat minutes ---------------------------------------------
          _SectionHeader(label: l10n.repeatMinutes),
          TextFormField(
            controller: _repeatController,
            decoration: InputDecoration(
              labelText: l10n.repeatMinutes,
              hintText: '5 – 60',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            validator: (val) {
              final n = int.tryParse(val ?? '');
              if (n == null || n < 1 || n > 60) return '1 – 60';
              return null;
            },
          ),
          const SizedBox(height: 32),

          // ---- Save button ------------------------------------------------
          ElevatedButton(
            onPressed: _loading ? null : _handleSave,
            child: _loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(l10n.done),
          ),
          const SizedBox(height: 24),

          // ---- Setup Checklist link ---------------------------------------
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.checklist),
              label: Text(l10n.setupChecklist),
              onPressed: () => context.push('/setup-checklist'),
            ),
          ),
          const Divider(height: 24),

          // ---- Phase 2: Escalation, Telegram, Phones & Gateway ------------
          const _SectionHeader(label: 'Phase 2: Escalation & Gateway'),
          ListTile(
            leading: const Icon(Icons.trending_up),
            title: const Text('Escalation Ladder'),
            subtitle: const Text('Steps, offsets & call order'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/escalation'),
          ),
          ListTile(
            leading: const Icon(Icons.send),
            title: const Text('Telegram Bot'),
            subtitle: const Text('Family group & account linking'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/telegram'),
          ),
          ListTile(
            leading: const Icon(Icons.contacts),
            title: const Text('Phone Numbers'),
            subtitle: const Text('E.164 numbers for calls & SMS'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/phone-numbers'),
          ),
          ListTile(
            leading: const Icon(Icons.cell_tower),
            title: const Text('Gateway Mode (Geo Phone)'),
            subtitle: const Text('SIM call/SMS relay & heartbeat'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/gateway'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _TimePickerTile extends StatelessWidget {
  const _TimePickerTile({
    required this.label,
    required this.symbol,
    required this.time,
    required this.onTap,
  });

  final String label;
  final String symbol;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final formatted = time.format(context);
    return ListTile(
      leading: Text(
        symbol,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      title: Text(label),
      trailing: Text(
        formatted,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    );
  }
}
