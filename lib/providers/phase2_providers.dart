import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/firestore_service.dart';
import '../data/models/escalation_models.dart';

final escalationSettingsProvider = StreamProvider<EscalationSettings>((ref) {
  return ref.watch(firestoreServiceProvider).watchEscalationSettings();
});

final telegramSettingsProvider = StreamProvider<TelegramSettings>((ref) {
  return ref.watch(firestoreServiceProvider).watchTelegramSettings();
});

final allUsersProvider = StreamProvider<List<UserProfile>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllUsers();
});

final gatewayStatusProvider = StreamProvider<GatewayStatus?>((ref) {
  return ref.watch(firestoreServiceProvider).watchGatewayStatus();
});

final auditLogsProvider = StreamProvider<List<AuditLogEntry>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAuditLogs();
});
