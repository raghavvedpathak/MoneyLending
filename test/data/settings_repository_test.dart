import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/data/di/database_provider.dart';
import 'package:money_lending/core/data/di/repository_providers.dart';
import 'package:money_lending/data/data.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SettingsDao settingsDao;
  late DatabaseHelper dbHelper;
  late SettingsRepository settingsRepo;

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
    dbHelper = DatabaseHelper.forTesting(db);
    settingsRepo = SettingsRepositoryImpl(dbHelper);
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

    test('SettingsDao watchSettingsRow streams row and updates reactively (§4.6)', () async {
      // 1. Initially null on empty table
      final initial = await settingsDao.watchSettingsRow().first;
      expect(initial, isNull);

      // 2. Insert row
      await settingsDao.insertSettings(const SettingsEntity(
        id: 1,
        name: 'Streamed Shop',
        phone: '111',
        address: 'Addr',
        defaultInterestRate: 2.5,
      ));

      final fetched = await settingsDao.watchSettingsRow().first;
      expect(fetched, isNotNull);
      expect(fetched!.name, 'Streamed Shop');
      expect(fetched.defaultInterestRate, 2.5);
    });

    test('SettingsRepository watchSettings emits default row on first access without throwing [FIX-ARCH-SETTINGS-1]', () async {
      // Table is empty initially
      final initialSettings = await settingsRepo.watchSettings().first;
      expect(initialSettings.id, 1);
      expect(initialSettings.name, '');
      expect(initialSettings.phone, '');
      expect(initialSettings.address, '');
      expect(initialSettings.defaultInterestRate, 2.0);

      // Verify row persisted into table
      final rows = await db.query('settings');
      expect(rows.length, 1);
      expect(rows.first['defaultInterestRate'], 2.0);
    });

    test('SettingsRepository watchSettings reacts to updateSettings without requiring screen reload [FIX-ARCH-SETTINGS-1]', () async {
      // Initialize first
      await settingsRepo.watchSettings().first;

      // Update interest rate to 3.5%
      await settingsRepo.updateSettings(const Settings(
        id: 1,
        name: 'New Name',
        phone: '555',
        address: 'New Addr',
        defaultInterestRate: 3.5,
      ));

      final updatedSettings = await settingsRepo.watchSettings().first;
      expect(updatedSettings.name, 'New Name');
      expect(updatedSettings.defaultInterestRate, 3.5);
    });

    test('SettingsRepository watchSettings pushes live updates to multiple concurrent subscribers without screen reload', () async {
      final emissionsA = <Settings>[];
      final emissionsB = <Settings>[];

      final subA = settingsRepo.watchSettings().listen(emissionsA.add);
      final subB = settingsRepo.watchSettings().listen(emissionsB.add);

      // Wait for initial default emission
      await Future.delayed(const Duration(milliseconds: 50));
      expect(emissionsA.isNotEmpty, isTrue);
      expect(emissionsB.isNotEmpty, isTrue);
      expect(emissionsA.first.defaultInterestRate, 2.0);
      expect(emissionsB.first.defaultInterestRate, 2.0);

      // Update in Settings screen
      await settingsRepo.updateSettings(const Settings(
        id: 1,
        name: 'Shared Shop',
        phone: '1234567890',
        address: 'Market Yard',
        defaultInterestRate: 4.0,
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(emissionsA.last.defaultInterestRate, 4.0);
      expect(emissionsB.last.defaultInterestRate, 4.0);

      await subA.cancel();
      await subB.cancel();
    });

    test('settingsStreamProvider emits updated settings reactively via Riverpod container [FIX-ARCH-SETTINGS-1]', () async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(dbHelper),
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(settingsStreamProvider, (_, __) {});
      addTearDown(subscription.close);

      final initial = await container.read(settingsStreamProvider.future);
      expect(initial.defaultInterestRate, 2.0);

      // Update settings
      await container.read(settingsRepositoryProvider).updateSettings(
        const Settings(
          id: 1,
          name: 'Riverpod Shop',
          phone: '999',
          address: 'Main Rd',
          defaultInterestRate: 2.75,
        ),
      );

      final updated = await container.read(settingsRepositoryProvider).watchSettings().first;
      expect(updated.defaultInterestRate, 2.75);
    });
  });
}
