import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/firestore_service.dart';
import '../../providers/phase2_providers.dart';

class TelegramSettingsScreen extends ConsumerStatefulWidget {
  const TelegramSettingsScreen({super.key});

  @override
  ConsumerState<TelegramSettingsScreen> createState() =>
      _TelegramSettingsScreenState();
}

class _TelegramSettingsScreenState
    extends ConsumerState<TelegramSettingsScreen> {
  final _chatIdController = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  bool _sendingTest = false;

  @override
  void dispose() {
    _chatIdController.dispose();
    super.dispose();
  }

  Future<void> _saveChatId() async {
    final chatId = _chatIdController.text.trim();
    if (chatId.isEmpty) return;

    setState(() => _saving = true);
    try {
      await ref.read(firestoreServiceProvider).saveTelegramChatId(chatId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Telegram Group ID saved ✔')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendTestMessage() async {
    setState(() => _sendingTest = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('sendTelegramTest');
      await callable.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test message sent to Telegram group! ✔'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send test message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingTest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tgAsync = ref.watch(telegramSettingsProvider);
    final usersAsync = ref.watch(allUsersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Telegram Bot Setup')),
      body: tgAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (tg) {
          if (!_initialized && tg.chatId != null) {
            _initialized = true;
            _chatIdController.text = tg.chatId!;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: const Color(0xFFE3F2FD),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Setup Steps',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '1. Add your Hatcher bot to the family Telegram group.\n'
                        '2. Send /register inside the group — Chat ID auto-detects.\n'
                        '3. Each family member taps their "I\'m <Name>" button once.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _chatIdController,
                decoration: const InputDecoration(
                  labelText: 'Telegram Group Chat ID',
                  hintText: '-1001234567890',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _saving ? null : _saveChatId,
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Chat ID Manually'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: _sendingTest
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('Send Test Message'),
                onPressed: _sendingTest ? null : _sendTestMessage,
              ),
              const Divider(height: 32),
              const Text(
                'Linked Family Accounts',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ...kUserNames.map((name) {
                final users = usersAsync.value ?? [];
                final matching = users.where((u) => u.name == name).toList();
                final tgId = matching.isNotEmpty
                    ? matching.first.telegramUserId
                    : tg.registeredUsers[name];
                final linked = tgId != null;

                return ListTile(
                  leading: Icon(
                    linked ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: linked ? Colors.green : Colors.grey,
                  ),
                  title: Text(name),
                  subtitle: Text(
                    linked
                        ? 'Linked (Telegram ID: $tgId)'
                        : 'Not linked yet — tap button in group',
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
