import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/method_channel.dart';
import '../../data/firestore_service.dart';
import '../../data/local_prefs.dart';
import '../../data/models/escalation_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/phase2_providers.dart';

class GatewaySettingsScreen extends ConsumerStatefulWidget {
  const GatewaySettingsScreen({super.key});

  @override
  ConsumerState<GatewaySettingsScreen> createState() =>
      _GatewaySettingsScreenState();
}

class _GatewaySettingsScreenState extends ConsumerState<GatewaySettingsScreen> {
  bool _gatewayEnabled = false;
  Map<String, bool> _perms = {};
  List<Map<String, dynamic>> _sims = [];
  int _selectedSimSlot = 0;
  final _testPhoneController = TextEditingController();
  bool _loadingNative = true;

  @override
  void initState() {
    super.initState();
    _loadNativeState();
  }

  @override
  void dispose() {
    _testPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadNativeState() async {
    setState(() => _loadingNative = true);
    final enabled = await HatcherChannel.isGatewayEnabled();
    final perms = await HatcherChannel.checkGatewayPermissions();
    final sims = await HatcherChannel.getAvailableSims();
    if (mounted) {
      setState(() {
        _gatewayEnabled = enabled;
        _perms = perms;
        _sims = sims;
        _loadingNative = false;
      });
    }
  }

  Future<void> _toggleGateway(bool enable) async {
    final uid = ref.read(currentUidProvider) ?? LocalPrefs.userUid;
    try {
      if (enable) {
        if (uid != null && uid.isNotEmpty) {
          await ref.read(firestoreServiceProvider).claimGatewayIdentity(uid);
        }
        await HatcherChannel.startGatewayService();
      } else {
        await HatcherChannel.stopGatewayService();
      }
      setState(() => _gatewayEnabled = enable);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gateway toggle error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _normalizePhone(String raw) {
    var p = raw.trim().replaceAll(' ', '');
    if (p.length == 10 && !p.startsWith('+')) {
      p = '+91$p';
    }
    return p;
  }

  Future<void> _runTestCall([String? targetPhone]) async {
    final rawPhone = targetPhone ?? _testPhoneController.text.trim();
    final phone = _normalizePhone(rawPhone);
    if (!isValidE164Phone(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid 10-digit or E.164 phone number, e.g. +919876543210'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    try {
      await HatcherChannel.testGatewayCall(phone);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Calling $phone directly from SIM...')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Call failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _runTestSms([String? targetPhone]) async {
    final rawPhone = targetPhone ?? _testPhoneController.text.trim();
    final phone = _normalizePhone(rawPhone);
    if (!isValidE164Phone(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid 10-digit or E.164 phone number, e.g. +919876543210'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    try {
      await HatcherChannel.testGatewaySms(
          phone, 'Hatcher Gateway Test SMS ✔');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test SMS sent to $phone ✔')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SMS failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gwAsync = ref.watch(gatewayStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gateway Mode (Geo Phone)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNativeState,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Live Gateway Status from Firestore
          gwAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Status error: $e'),
            data: (gw) {
              if (gw == null) {
                return const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('No gateway registered yet'),
                    subtitle: Text('Enable Gateway Mode on Geo\'s phone.'),
                  ),
                );
              }
              final lastSeenStr = gw.lastSeen != null
                  ? DateFormat('dd MMM, h:mm:ss a').format(gw.lastSeen!)
                  : 'Never';
              return Card(
                color: gw.isOnline
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFFFEBEE),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            gw.isOnline ? Icons.check_circle : Icons.error,
                            color: gw.isOnline ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            gw.isOnline ? 'Gateway ONLINE' : 'Gateway OFFLINE',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Device: ${gw.deviceName}'),
                      Text('Last heartbeat: $lastSeenStr'),
                      Text(
                          'Battery: ${gw.battery}% ${gw.charging ? '(Charging ⚡)' : ''}'),
                      Text('Wi-Fi: ${gw.wifi ? 'Connected' : 'Mobile/Off'}  |  SIM Ready: ${gw.simReady ? 'Yes ✔' : 'No ✘'}'),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // Toggle on this phone
          SwitchListTile(
            title: const Text('Enable Gateway Mode on THIS Phone'),
            subtitle: const Text(
                'Keep toggled ON only on Geo\'s phone (places calls & SMS)'),
            value: _gatewayEnabled,
            onChanged: _loadingNative ? null : _toggleGateway,
          ),
          const Divider(),

          // Permissions Checklist
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Gateway Permissions',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              TextButton(
                onPressed: () async {
                  await HatcherChannel.requestGatewayPermissions();
                  await Future.delayed(const Duration(seconds: 1));
                  await _loadNativeState();
                },
                child: const Text('Grant Runtime Permissions'),
              ),
            ],
          ),
          _PermRow('CALL_PHONE (Place Calls)', _perms['call_phone'] == true),
          _PermRow('SEND_SMS (Send SMS)', _perms['send_sms'] == true),
          _PermRow(
              'READ_PHONE_STATE (SIM & Call State)', _perms['read_phone_state'] == true),
          _PermRow('ANSWER_PHONE_CALLS (40s Hangup)',
              _perms['answer_phone_calls'] == true),
          ListTile(
            dense: true,
            leading: Icon(
              _perms['battery_optimization'] == true
                  ? Icons.check_circle
                  : Icons.warning,
              color: _perms['battery_optimization'] == true
                  ? Colors.green
                  : Colors.orange,
            ),
            title: const Text('Battery Unrestricted'),
            trailing: TextButton(
              onPressed: () => HatcherChannel.openPermissionSettings(
                  'battery_optimization'),
              child: const Text('Settings'),
            ),
          ),
          const Divider(),

          // Dual-SIM Selector
          const Text(
            'SIM Card Selection',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          if (_sims.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No SIM info detected yet (grant READ_PHONE_STATE and refresh).',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
            )
          else
            ..._sims.map((sim) {
              final slot = (sim['slotIndex'] as num).toInt();
              final name = '${sim['displayName']} (${sim['carrierName']})';
              return RadioListTile<int>(
                title: Text('SIM ${slot + 1}: $name'),
                value: slot,
                groupValue: _selectedSimSlot,
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() => _selectedSimSlot = v);
                  await HatcherChannel.setGatewaySimSlot(v);
                },
              );
            }),
          const Divider(),

          // Test Call / Test SMS
          const Text(
            'Test Gateway SIM',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _testPhoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone number to test (E.164)',
              hintText: '+919876543210',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.call),
                  label: const Text('Test Call to Me'),
                  onPressed: _runTestCall,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.sms),
                  label: const Text('Test SMS'),
                  onPressed: _runTestSms,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const Text(
            'Family Quick Call & SMS',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap call to immediately dial any member\'s phone directly from this gateway phone.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ref.watch(allUsersProvider).when(
            data: (users) {
              if (users.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('No family members registered yet.'),
                );
              }
              return Column(
                children: users.map((u) {
                  final phone = u.phone;
                  final hasPhone = phone != null && phone.trim().isNotEmpty;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(u.name.isNotEmpty ? u.name[0].toUpperCase() : '?'),
                      ),
                      title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        hasPhone ? phone : 'No phone set in Escalation Settings',
                        style: TextStyle(
                          color: hasPhone ? null : Colors.orange.shade800,
                          fontSize: 12,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.call, color: Colors.green),
                            tooltip: 'Call ${u.name}',
                            onPressed: hasPhone
                                ? () => _runTestCall(phone)
                                : () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('No phone saved for ${u.name}. Set it in Escalation Settings.'),
                                      ),
                                    );
                                  },
                          ),
                          IconButton(
                            icon: const Icon(Icons.sms, color: Colors.blue),
                            tooltip: 'SMS ${u.name}',
                            onPressed: hasPhone
                                ? () => _runTestSms(phone)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Text('Could not load family members: $e'),
          ),
        ],
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  const _PermRow(this.label, this.granted);
  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        granted ? Icons.check_circle : Icons.cancel,
        color: granted ? Colors.green : Colors.red,
      ),
      title: Text(label),
    );
  }
}
