import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/firestore_service.dart';
import '../data/models/settings_model.dart';

/// Streams the shared [SettingsModel] from Firestore.
final settingsProvider = StreamProvider<SettingsModel>((ref) {
  final service = ref.watch(firestoreServiceProvider);
  return service.watchSettings();
}, name: 'settingsProvider');

/// Provides a callable function that persists a [SettingsModel] to Firestore.
final saveSettingsProvider = Provider<Future<void> Function(SettingsModel)>((ref) {
  final service = ref.read(firestoreServiceProvider);
  return (SettingsModel settings) => service.saveSettings(settings);
}, name: 'saveSettingsProvider');
