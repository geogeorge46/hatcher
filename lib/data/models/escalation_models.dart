import 'package:cloud_firestore/cloud_firestore.dart';

/// Validates E.164 international phone numbers, e.g. +919876543210.
bool isValidE164Phone(String input) {
  final trimmed = input.trim();
  return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(trimmed);
}

class EscalationStepConfig {
  final int offsetMinutes;
  final List<String> actions; // 'fcm_push' | 'telegram_prompt' | 'telegram_urgent' | 'call' | 'sms_others'
  final int? callIndex;

  const EscalationStepConfig({
    required this.offsetMinutes,
    required this.actions,
    this.callIndex,
  });

  factory EscalationStepConfig.fromMap(Map<String, dynamic> map) {
    return EscalationStepConfig(
      offsetMinutes: (map['offsetMinutes'] as num?)?.toInt() ?? 10,
      actions: (map['actions'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      callIndex: (map['callIndex'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
        'offsetMinutes': offsetMinutes,
        'actions': actions,
        if (callIndex != null) 'callIndex': callIndex,
      };

  EscalationStepConfig copyWith({
    int? offsetMinutes,
    List<String>? actions,
    int? callIndex,
  }) {
    return EscalationStepConfig(
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      actions: actions ?? List<String>.from(this.actions),
      callIndex: callIndex ?? this.callIndex,
    );
  }
}

class EscalationSettings {
  final bool enabled;
  final List<EscalationStepConfig> steps;
  final List<String> callOrder;
  final int stopAfterMinutes;

  const EscalationSettings({
    required this.enabled,
    required this.steps,
    required this.callOrder,
    required this.stopAfterMinutes,
  });

  factory EscalationSettings.defaults() => const EscalationSettings(
        enabled: true,
        callOrder: ['George', 'Dolly', 'Leo'],
        stopAfterMinutes: 60,
        steps: [
          EscalationStepConfig(
            offsetMinutes: 10,
            actions: ['fcm_push', 'telegram_prompt'],
          ),
          EscalationStepConfig(
            offsetMinutes: 20,
            actions: ['call'],
            callIndex: 0,
          ),
          EscalationStepConfig(
            offsetMinutes: 30,
            actions: ['call', 'sms_others'],
            callIndex: 1,
          ),
          EscalationStepConfig(
            offsetMinutes: 45,
            actions: ['call', 'telegram_urgent'],
            callIndex: 2,
          ),
        ],
      );

  factory EscalationSettings.fromFirestore(DocumentSnapshot doc) {
    final defaults = EscalationSettings.defaults();
    final data = doc.data() as Map<String, dynamic>? ?? {};

    final rawSteps = data['steps'] as List<dynamic>?;
    final steps = rawSteps != null && rawSteps.isNotEmpty
        ? rawSteps
            .map((e) => EscalationStepConfig.fromMap(
                Map<String, dynamic>.from(e as Map)))
            .toList()
        : defaults.steps;

    final rawCallOrder = data['callOrder'] as List<dynamic>?;
    final callOrder = rawCallOrder != null && rawCallOrder.isNotEmpty
        ? rawCallOrder.map((e) => e.toString()).toList()
        : defaults.callOrder;

    return EscalationSettings(
      enabled: data['enabled'] as bool? ?? defaults.enabled,
      steps: steps,
      callOrder: callOrder,
      stopAfterMinutes:
          (data['stopAfterMinutes'] as num?)?.toInt() ?? defaults.stopAfterMinutes,
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'steps': steps.map((s) => s.toMap()).toList(),
        'callOrder': callOrder,
        'stopAfterMinutes': stopAfterMinutes,
      };
}

class TelegramSettings {
  final String? chatId;
  final Map<String, int> registeredUsers;

  const TelegramSettings({
    this.chatId,
    required this.registeredUsers,
  });

  factory TelegramSettings.empty() =>
      const TelegramSettings(chatId: null, registeredUsers: {});

  factory TelegramSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawReg = data['registeredUsers'] as Map<String, dynamic>? ?? {};
    final parsedReg = <String, int>{};
    rawReg.forEach((k, v) {
      if (v is num) parsedReg[k] = v.toInt();
    });

    return TelegramSettings(
      chatId: data['chatId']?.toString(),
      registeredUsers: parsedReg,
    );
  }
}

class UserProfile {
  final String uid;
  final String name;
  final String? phone;
  final int? telegramUserId;
  final String? fcmToken;

  const UserProfile({
    required this.uid,
    required this.name,
    this.phone,
    this.telegramUserId,
    this.fcmToken,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserProfile(
      uid: doc.id,
      name: data['name']?.toString() ?? 'Unknown',
      phone: data['phone']?.toString(),
      telegramUserId: (data['telegramUserId'] as num?)?.toInt(),
      fcmToken: data['fcmToken']?.toString(),
    );
  }
}

class GatewayStatus {
  final String uid;
  final String deviceName;
  final DateTime? lastSeen;
  final int battery;
  final bool charging;
  final bool wifi;
  final bool simReady;
  final int selectedSimSlot;

  const GatewayStatus({
    required this.uid,
    required this.deviceName,
    this.lastSeen,
    required this.battery,
    required this.charging,
    required this.wifi,
    required this.simReady,
    required this.selectedSimSlot,
  });

  /// Online if last heartbeat was within 3 minutes.
  bool get isOnline {
    if (lastSeen == null) return false;
    return DateTime.now().difference(lastSeen!).inSeconds <= 180;
  }

  factory GatewayStatus.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final ts = data['lastSeen'] as Timestamp?;
    return GatewayStatus(
      uid: data['uid']?.toString() ?? '',
      deviceName: data['deviceName']?.toString() ?? 'Unknown Phone',
      lastSeen: ts?.toDate(),
      battery: (data['battery'] as num?)?.toInt() ?? -1,
      charging: data['charging'] as bool? ?? false,
      wifi: data['wifi'] as bool? ?? false,
      simReady: data['simReady'] as bool? ?? false,
      selectedSimSlot: (data['selectedSimSlot'] as num?)?.toInt() ?? 0,
    );
  }
}

class AuditLogEntry {
  final String id;
  final DateTime? timestamp;
  final String date;
  final String slotKey;
  final String channel;
  final String targetName;
  final String result;
  final String details;

  const AuditLogEntry({
    required this.id,
    this.timestamp,
    required this.date,
    required this.slotKey,
    required this.channel,
    required this.targetName,
    required this.result,
    required this.details,
  });

  factory AuditLogEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final ts = data['timestamp'] as Timestamp?;
    return AuditLogEntry(
      id: doc.id,
      timestamp: ts?.toDate(),
      date: data['date']?.toString() ?? '',
      slotKey: data['slotKey']?.toString() ?? '',
      channel: data['channel']?.toString() ?? 'system',
      targetName: data['targetName']?.toString() ?? '',
      result: data['result']?.toString() ?? '',
      details: data['details']?.toString() ?? '',
    );
  }
}
