import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/firestore_service.dart';
import '../../data/models/escalation_models.dart';
import '../../providers/phase2_providers.dart';

class PhoneNumbersScreen extends ConsumerStatefulWidget {
  const PhoneNumbersScreen({super.key});

  @override
  ConsumerState<PhoneNumbersScreen> createState() => _PhoneNumbersScreenState();
}

class _PhoneNumbersScreenState extends ConsumerState<PhoneNumbersScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _errors = {};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(UserProfile user) {
    return _controllers.putIfAbsent(
      user.uid,
      () => TextEditingController(text: user.phone ?? ''),
    );
  }

  Future<void> _saveUser(UserProfile user) async {
    final raw = _controllerFor(user).text.trim();
    if (raw.isEmpty || !isValidE164Phone(raw)) {
      setState(() {
        _errors[user.uid] =
            'Invalid format. Use E.164 with country code, e.g. +919876543210';
      });
      return;
    }

    setState(() {
      _errors[user.uid] = null;
      _saving = true;
    });

    try {
      await ref
          .read(firestoreServiceProvider)
          .saveUserPhone(uid: user.uid, phone: raw);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${user.name}\'s number ✔')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Family Phone Numbers')),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (users) {
          if (users.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No family phones registered yet. Each person must open Hatcher and pick their name first.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Enter each person\'s phone number in E.164 format (e.g. +919876543210) so Geo\'s gateway phone can call or SMS them.',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ...users.map((user) {
                final ctrl = _controllerFor(user);
                final err = _errors[user.uid];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          user.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: ctrl,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'Phone Number (E.164)',
                            hintText: '+919876543210',
                            errorText: err,
                            errorMaxLines: 2,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: _saving ? null : () => _saveUser(user),
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
