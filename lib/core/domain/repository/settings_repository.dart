import '../../../../domain/models/settings.dart';

/// Domain Contract for Settings Repository.
///
/// Mandated by Architecture Spec §4.6 & [FIX-ARCH-SETTINGS-1]:
/// The SettingsRepository must expose settings as a Stream, not as a one-shot Future.
/// If exposed only as a one-shot Future, the default interest rate shown on the Add Record
/// form will not update when the user changes it in Settings without a full screen reload.
abstract class SettingsRepository {
  /// Emits whenever settings are updated. Never null — inserts a default row
  /// on first access.
  /// ⚠️ H-10 FIX equivalent: default values contract for the first-insert row (id = 1):
  /// - name = "" (empty string — user must fill in business name)
  /// - phone = "" (empty string)
  /// - address = "" (empty string)
  /// - defaultInterestRate = 2.0 (2% per month — common starting rate; user overrides in Settings screen)
  ///
  /// In SettingsRepositoryImpl.watchSettings(): if the underlying stream emits null
  /// (empty table on first install), insert the default row with
  /// InsertMode.insertOrIgnore (safe to call on every stream emission — noop if the
  /// row already exists) inside the stream-mapping step, then re-emit the default.
  Stream<Settings> watchSettings();

  /// Updates settings and notifies all active stream observers.
  Future<void> updateSettings(Settings settings);

  // Backward-compatibility aliases:
  Stream<Settings> getSettings();
  Future<Settings> getSettingsOnce();
}
