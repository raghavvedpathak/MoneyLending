import '../models/settings.dart';

/// Domain Contract for Settings Repository.
///
/// Mandated by Architecture Spec §4.6 & [FIX-ARCH-SETTINGS-1]:
/// The SettingsRepository must expose settings as a Flow (Stream in Dart), not as a one-shot suspend fun.
/// If exposed only as a one-shot suspend fun, the default interest rate shown on the Add Record
/// form will not update when the user changes it in Settings without a full screen reload.
abstract class SettingsRepository {
  /// Emits whenever settings are updated. Never null — inserts default row on first access.
  /// H-10 FIX: Default values contract for the first-insert row (id = 1):
  /// - name: ""
  /// - phone: ""
  /// - address: ""
  /// - defaultInterestRate: 2.0
  Stream<Settings> getSettings();

  /// One-shot snapshot query for current settings.
  Future<Settings> getSettingsOnce();

  /// Updates settings and notifies all active getSettings() stream subscribers.
  Future<void> updateSettings(Settings settings);
}
