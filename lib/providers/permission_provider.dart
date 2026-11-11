import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/method_channel.dart';

/// Fetches current Android permissions status from native layer.
final permissionsProvider = FutureProvider<Map<String, bool>>((ref) async {
  return await HatcherChannel.checkPermissions();
}, name: 'permissionsProvider');

/// Checks if all necessary permissions are granted.
final hasAllPermissionsProvider = Provider<bool>((ref) {
  final permsAsync = ref.watch(permissionsProvider);
  return permsAsync.whenOrNull(data: (perms) {
    // Critical permissions
    final notifs = perms['notifications'] ?? true;
    final exact = perms['exact_alarm'] ?? perms['exactAlarm'] ?? true;
    final fullscreen = perms['full_screen_intent'] ?? perms['fullscreen'] ?? true;
    final battery = perms['battery_optimization'] ?? perms['battery'] ?? true;
    return notifs && exact && fullscreen && battery;
  }) ?? true;
}, name: 'hasAllPermissionsProvider');
