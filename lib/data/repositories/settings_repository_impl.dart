import 'dart:async';
import '../../domain/models/settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/database_helper.dart';
import '../models/settings_entity.dart';

/// Concrete Data Layer implementation of SettingsRepository.
///
/// Mandated by Architecture Spec §4.6 & [FIX-ARCH-SETTINGS-1]:
/// - Exposes settings as a reactive Stream (Flow in Kotlin), never requiring full-screen reloads.
/// - Never null — inserts default row on first access.
/// - H-10 FIX: Default values contract for the first-insert row (id = 1):
///   name = "" (empty string — user must fill in business name)
///   phone = "" (empty string)
///   address = "" (empty string)
///   defaultInterestRate = 2.0 (2% per month — common starting rate; user overrides in Settings screen)
/// - Uses ConflictAlgorithm.ignore (OnConflictStrategy.IGNORE) for initial insert, making it a safe no-op.
class SettingsRepositoryImpl implements SettingsRepository {
  final DatabaseHelper _dbHelper;
  late final StreamController<Settings> _settingsStreamController =
      StreamController<Settings>.broadcast(onListen: _refreshSettings);

  SettingsRepositoryImpl([DatabaseHelper? dbHelper])
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Settings _toDomain(SettingsEntity entity) {
    return Settings(
      id: entity.id,
      name: entity.name,
      phone: entity.phone,
      address: entity.address,
      defaultInterestRate: entity.defaultInterestRate,
    );
  }

  Future<void> _refreshSettings() async {
    final current = await getSettingsOnce();
    _settingsStreamController.add(current);
  }

  @override
  Stream<Settings> watchSettings() async* {
    final dao = await _dbHelper.settingsDao;
    await for (final row in dao.watchSettingsRow()) {
      if (row == null) {
        const defaultEntity = SettingsEntity(
          id: 1,
          name: '',
          phone: '',
          address: '',
          defaultInterestRate: 2.0,
        );
        await dao.insertSettings(defaultEntity);
        yield _toDomain(defaultEntity);
      } else {
        yield _toDomain(row);
      }
    }
  }

  @override
  Stream<Settings> getSettings() => watchSettings();

  @override
  Future<Settings> getSettingsOnce() async {
    final dao = await _dbHelper.settingsDao;
    var entity = await dao.getSettingsEntity();

    // H-10 FIX: First-insert default contract on empty table
    if (entity == null) {
      const defaultEntity = SettingsEntity(
        id: 1,
        name: '',
        phone: '',
        address: '',
        defaultInterestRate: 2.0,
      );
      await dao.insertSettings(defaultEntity);
      entity = defaultEntity;
    }

    return _toDomain(entity);
  }

  @override
  Future<void> updateSettings(Settings settings) async {
    final dao = await _dbHelper.settingsDao;
    final entity = SettingsEntity(
      id: 1,
      name: settings.name,
      phone: settings.phone,
      address: settings.address,
      defaultInterestRate: settings.defaultInterestRate,
    );
    await dao.upsertSettings(entity);
    await _refreshSettings();
  }
}
