import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/data/data.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SettingsDao settingsDao;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE settings (
              id INTEGER PRIMARY KEY,
              name TEXT,
              phone TEXT,
              address TEXT,
              defaultInterestRate REAL NOT NULL DEFAULT 2.0
            )
          ''');
        },
      ),
    );
    settingsDao = SettingsDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('SettingsRepository & DAO Pattern Tests (§4.6 & [FIX-ARCH-SETTINGS-1])', () {
    test('Empty table returns null on getSettingsEntity and initializes with H-10 defaults', () async {
      // 1. Initial table is empty
      final initialRaw = await settingsDao.getSettingsEntity();
      expect(initialRaw, isNull);

      // 2. Direct DAO getSettings initializes H-10 default row
      final settings = await settingsDao.getSettings();
      expect(settings.id, 1);
      expect(settings.name, '');
      expect(settings.phone, '');
      expect(settings.address, '');
      expect(settings.defaultInterestRate, 2.0);

      // 3. Table now contains exactly 1 row
      final rows = await db.query('settings');
      expect(rows.length, 1);
      expect(rows.first['id'], 1);
    });

    test('insertSettings uses IGNORE strategy making repeated calls safe no-ops', () async {
      const defaultSettings = SettingsEntity(
        id: 1,
        name: 'Initial Shop',
        phone: '9999999999',
        address: 'Main Market',
        defaultInterestRate: 2.0,
      );

      // First insert
      await settingsDao.insertSettings(defaultSettings);

      // Repeated insert with different data should be IGNORED (no-op)
      const ignoredSettings = SettingsEntity(
        id: 1,
        name: 'Ignored Shop Name',
        phone: '0000000000',
        address: 'Other Street',
        defaultInterestRate: 3.5,
      );
      await settingsDao.insertSettings(ignoredSettings);

      final current = await settingsDao.getSettings();
      expect(current.name, 'Initial Shop', reason: 'IGNORE strategy must make repeated insert a no-op');
      expect(current.defaultInterestRate, 2.0);
    });

    test('upsertSettings safely replaces settings and updates default interest rate', () async {
      const initial = SettingsEntity(
        id: 1,
        name: 'Byaj Shop',
        phone: '1234567890',
        address: 'Bazaar',
        defaultInterestRate: 2.0,
      );
      await settingsDao.upsertSettings(initial);

      const updated = SettingsEntity(
        id: 1,
        name: 'Byaj Shop Updated',
        phone: '9876543210',
        address: 'City Center',
        defaultInterestRate: 3.0,
      );
      await settingsDao.upsertSettings(updated);

      final current = await settingsDao.getSettings();
      expect(current.name, 'Byaj Shop Updated');
      expect(current.phone, '9876543210');
      expect(current.address, 'City Center');
      expect(current.defaultInterestRate, 3.0);
    });

    test('Settings domain model adheres to H-10 default values', () {
      const settings = Settings();
      expect(settings.id, 1);
      expect(settings.name, '');
      expect(settings.phone, '');
      expect(settings.address, '');
      expect(settings.defaultInterestRate, 2.0);
    });
  });
}
