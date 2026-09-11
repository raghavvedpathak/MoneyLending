import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/settings_entity.dart';

/// DAO for SettingsEntity.
///
/// Mandated by Data Spec §4.2, §4.4, & §4.6 [FIX-ARCH-SETTINGS-1]:
/// - Single-row table with id = 1.
/// - Backing query: SELECT * FROM settings WHERE id = 1.
/// - insertSettings uses ConflictAlgorithm.ignore (OnConflictStrategy.IGNORE):
///   No-op if row already exists, safe to call on initial access.
/// - upsertSettings uses ConflictAlgorithm.replace: safe for single-row settings table.
class SettingsDao {
  final DatabaseExecutor _db;

  const SettingsDao(this._db);

  /// Backing query matching §4.6: SELECT * FROM settings WHERE id = 1
  /// Returns null if table is empty on first install.
  Future<SettingsEntity?> getSettingsEntity() async {
    final maps = await _db.query('settings', where: 'id = 1', limit: 1);
    if (maps.isEmpty) return null;
    return SettingsEntity.fromMap(maps.first);
  }

  /// Direct DAO query with automatic default insertion fallback
  Future<SettingsEntity> getSettings() async {
    final entity = await getSettingsEntity();
    if (entity == null) {
      const defaultSettings = SettingsEntity(
        id: 1,
        name: '',
        phone: '',
        address: '',
        defaultInterestRate: 2.0,
      );
      await insertSettings(defaultSettings);
      return defaultSettings;
    }
    return entity;
  }

  /// Initial insert using ConflictAlgorithm.ignore (no-op if id=1 already exists)
  Future<void> insertSettings(SettingsEntity settings) async {
    await _db.insert(
      'settings',
      settings.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Upsert using ConflictAlgorithm.replace for setting updates
  Future<void> upsertSettings(SettingsEntity settings) async {
    await _db.insert(
      'settings',
      settings.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
