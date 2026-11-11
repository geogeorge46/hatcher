import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/firestore_service.dart';
import '../../data/models/escalation_models.dart';
import '../../providers/phase2_providers.dart';

class EscalationSettingsScreen extends ConsumerStatefulWidget {
  const EscalationSettingsScreen({super.key});

  @override
  ConsumerState<EscalationSettingsScreen> createState() =>
      _EscalationSettingsScreenState();
}

class _EscalationSettingsScreenState
    extends ConsumerState<EscalationSettingsScreen> {
  bool _initialized = false;
  bool _saving = false;
  bool _enabled = true;
  late List<EscalationStepConfig> _steps;
  late List<String> _callOrder;
  final _stopAfterCtrl = TextEditingController();

  @override
  void dispose() {
    _stopAfterCtrl.dispose();
    super.dispose();
  }

  void _populate(EscalationSettings s) {
    if (_initialized) return;
    _initialized = true;
    _enabled = s.enabled;
    _steps = s.steps.map((e) => e.copyWith()).toList();
    _callOrder = List<String>.from(s.callOrder);
    _stopAfterCtrl.text = s.stopAfterMinutes.toString();
  }

  Future<void> _save() async {
    final stopAfter = int.tryParse(_stopAfterCtrl.text.trim());
    if (stopAfter == null || stopAfter < 10 || stopAfter > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stop-after minutes must be 10–180')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = EscalationSettings(
        enabled: _enabled,
        steps: _steps,
        callOrder: _callOrder,
        stopAfterMinutes: stopAfter,
      );
      await ref
          .read(firestoreServiceProvider)
          .saveEscalationSettings(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escalation settings saved ✔')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _describeStep(EscalationStepConfig step) {
    final parts = <String>[];
    for (final a in step.actions) {
      switch (a) {
        case 'fcm_push':
          parts.add('FCM Push to all');
          break;
        case 'telegram_prompt':
          parts.add('Telegram + Rotated button');
          break;
        case 'telegram_urgent':
          parts.add('Urgent Telegram');
          break;
        case 'call':
          final idx = step.callIndex ?? 0;
          final target = idx < _callOrder.length ? _callOrder[idx] : '#${idx + 1}';
          parts.add('Call $target');
          break;
        case 'sms_others':
          parts.add('SMS all others');
          break;
      }
    }
    return parts.join(' + ');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(escalationSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Escalation Ladder')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (settings) {
          _populate(settings);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                title: const Text('Enable Automatic Escalation'),
                subtitle: const Text(
                    'Escalate via Telegram, push, calls & SMS if slot is not done'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              const Divider(),
              const Text(
                'Call Order (Person #1 → #2 → #3)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ...List.generate(_callOrder.length, (i) {
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: DropdownButton<String>(
                      isExpanded: true,
                      value: _callOrder[i],
                      underline: const SizedBox.shrink(),
                      items: kUserNames
                          .map((name) => DropdownMenuItem(
                                value: name,
                                child: Text(name),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _callOrder[i] = val);
                        }
                      },
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              const Text(
                'Escalation Steps (Minutes After Due Time)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ...List.generate(_steps.length, (i) {
                final step = _steps[i];
                return Card(
                  child: ListTile(
                    title: Text('+${step.offsetMinutes} min'),
                    subtitle: Text(_describeStep(step)),
                    trailing: SizedBox(
                      width: 72,
                      child: TextFormField(
                        initialValue: step.offsetMinutes.toString(),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Min',
                          isDense: true,
                        ),
                        onChanged: (val) {
                          final parsed = int.tryParse(val);
                          if (parsed != null && parsed >= 1 && parsed <= 180) {
                            _steps[i] = step.copyWith(offsetMinutes: parsed);
                          }
                        },
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              TextFormField(
                controller: _stopAfterCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Stop & mark missed after (minutes)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Escalation Settings'),
              ),
            ],
          );
        },
      ),
    );
  }
}
