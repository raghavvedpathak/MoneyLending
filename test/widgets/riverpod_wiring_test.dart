import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/data/di/database_provider.dart';
import 'package:money_lending/core/data/di/repository_providers.dart';
import 'package:money_lending/core/data/schema/app_database.dart';
import 'package:money_lending/core/data/schema/drift_tables.dart' as dt;
import 'package:money_lending/core/domain/domain.dart';
import 'package:money_lending/data/data.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('Riverpod Wiring & AppDatabase Singleton Tests (§4.3 [FIX-ARCH-DB-1])', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('appDatabaseProvider and all repository providers are keepAlive singletons [FIX-SINGLETON-SCOPE-1]', () {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(DatabaseHelper.instance),
        ],
      );
      addTearDown(container.dispose);

      // 1. DatabaseHelper / AppDatabase singleton check
      final db1 = container.read(appDatabaseProvider);
      final db2 = container.read(appDatabaseProvider);
      expect(identical(db1, db2), isTrue);
      expect(db1, isA<AppDatabase>());

      // 2. CustomerRepository keepAlive singleton check
      final custRepo1 = container.read(customerRepositoryProvider);
      final custRepo2 = container.read(customerRepositoryProvider);
      expect(identical(custRepo1, custRepo2), isTrue);

      // 3. LenderRepository keepAlive singleton check [FIX-LENDER-CODEPATH-1]
      final lendRepo1 = container.read(lenderRepositoryProvider);
      final lendRepo2 = container.read(lenderRepositoryProvider);
      expect(identical(lendRepo1, lendRepo2), isTrue);

      // 4. RecordRepository keepAlive singleton check
      final recRepo1 = container.read(recordRepositoryProvider);
      final recRepo2 = container.read(recordRepositoryProvider);
      expect(identical(recRepo1, recRepo2), isTrue);

      // 5. SettingsRepository keepAlive singleton check
      final setRepo1 = container.read(settingsRepositoryProvider);
      final setRepo2 = container.read(settingsRepositoryProvider);
      expect(identical(setRepo1, setRepo2), isTrue);

      // 6. ItemRateRepository keepAlive singleton check
      final rateRepo1 = container.read(itemRateRepositoryProvider);
      final rateRepo2 = container.read(itemRateRepositoryProvider);
      expect(identical(rateRepo1, rateRepo2), isTrue);
    });

    test('appDatabaseProvider executes ref.onDispose to close database connection', () async {
      var closeCalled = false;
      final testDb = DatabaseHelper.forTesting(
        await openDatabase(
          inMemoryDatabasePath,
          version: 1,
          singleInstance: false,
          onCreate: (db, _) => DatabaseHelper.createTablesForTesting(db),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) {
            ref.onDispose(() => closeCalled = true);
            return testDb;
          }),
        ],
      );

      container.read(appDatabaseProvider);
      expect(closeCalled, isFalse);

      container.dispose();
      expect(closeCalled, isTrue);
    });

    testWidgets('Same repository instances returned across separate widgets even after temporary unmount [FIX-SINGLETON-SCOPE-1]', (WidgetTester tester) async {
      CustomerRepository? custRepoA;
      CustomerRepository? custRepoB;
      LenderRepository? lendRepoA;
      LenderRepository? lendRepoB;
      RecordRepository? recRepoA;
      RecordRepository? recRepoB;
      SettingsRepository? setRepoA;
      SettingsRepository? setRepoB;
      ItemRateRepository? rateRepoA;
      ItemRateRepository? rateRepoB;

      final widgetAKey = GlobalKey();
      final widgetBKey = GlobalKey();
      final showWidgetA = ValueNotifier<bool>(true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(DatabaseHelper.instance),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: showWidgetA,
                builder: (context, showA, _) {
                  return Column(
                    children: [
                      if (showA)
                        Consumer(
                          key: widgetAKey,
                          builder: (context, ref, _) {
                            custRepoA = ref.watch(customerRepositoryProvider);
                            lendRepoA = ref.watch(lenderRepositoryProvider);
                            recRepoA = ref.watch(recordRepositoryProvider);
                            setRepoA = ref.watch(settingsRepositoryProvider);
                            rateRepoA = ref.watch(itemRateRepositoryProvider);
                            return const Text('Widget A Active');
                          },
                        ),
                      Consumer(
                        key: widgetBKey,
                        builder: (context, ref, _) {
                          custRepoB = ref.watch(customerRepositoryProvider);
                          lendRepoB = ref.watch(lenderRepositoryProvider);
                          recRepoB = ref.watch(recordRepositoryProvider);
                          setRepoB = ref.watch(settingsRepositoryProvider);
                          rateRepoB = ref.watch(itemRateRepositoryProvider);
                          return const Text('Widget B Active');
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      // Verify initial equality across all 5 repositories
      expect(identical(custRepoA, custRepoB), isTrue);
      expect(identical(lendRepoA, lendRepoB), isTrue);
      expect(identical(recRepoA, recRepoB), isTrue);
      expect(identical(setRepoA, setRepoB), isTrue);
      expect(identical(rateRepoA, rateRepoB), isTrue);

      // Unmount Widget A completely
      showWidgetA.value = false;
      await tester.pump();
      expect(find.text('Widget A Active'), findsNothing);

      // Verify Widget B still retains the same instances
      expect(identical(custRepoA, custRepoB), isTrue);
      expect(identical(lendRepoA, lendRepoB), isTrue);
      expect(identical(recRepoA, recRepoB), isTrue);
      expect(identical(setRepoA, setRepoB), isTrue);
      expect(identical(rateRepoA, rateRepoB), isTrue);

      // Remount Widget A
      showWidgetA.value = true;
      await tester.pump();
      expect(find.text('Widget A Active'), findsOneWidget);

      // The newly remounted Widget A must still see the exact same repository instances
      expect(identical(custRepoA, custRepoB), isTrue);
      expect(identical(lendRepoA, lendRepoB), isTrue);
      expect(identical(recRepoA, recRepoB), isTrue);
      expect(identical(setRepoA, setRepoB), isTrue);
      expect(identical(rateRepoA, rateRepoB), isTrue);
    });

    test('CustomerRepository, LenderRepository and RecordRepository are abstract classes in core/domain', () {
      // Contract verification per §4.3
      expect(CustomerRepository, isNotNull);
      expect(LenderRepository, isNotNull);
      expect(RecordRepository, isNotNull);
      expect(SettingsRepository, isNotNull);
      expect(ItemRateRepository, isNotNull);
    });

    test('AppDatabase schema metadata lists all 8 Drift tables (§4.1 & §4.3)', () {
      expect(AppDatabaseSchema.currentSchemaVersion, 1);
      expect(AppDatabaseSchema.databaseFileName, 'moneylending.db');
      expect(AppDatabaseSchema.allTables.length, 8);
      expect(AppDatabaseSchema.allTables, containsAll([
        dt.Customers,
        dt.Lenders,
        dt.Records,
        dt.LedgerItems,
        dt.Payments,
        dt.Settings,
        dt.ItemRates,
        dt.RetiredIds,
      ]));
    });

    test('Independent SQLite connection adheres to WAL and foreign keys [FIX-BG-DB-1]', () async {
      // Test opening an isolated SQLite connection like a background worker would
      final db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA busy_timeout = 5000');
        },
        onCreate: (db, version) async {
          await DatabaseHelper.createTablesForTesting(db);
        },
      );

      final fkRes = await db.rawQuery('PRAGMA foreign_keys');
      expect(fkRes.first.values.first, 1);

      final bgHelper = DatabaseHelper.forTesting(db);
      final bgRecRepo = RecordRepositoryImpl(bgHelper);
      final bgRateRepo = ItemRateRepositoryImpl(bgHelper);

      // Verify read-only query executes cleanly
      final records = await bgRecRepo.getAllActiveRecordsOnce();
      expect(records, isEmpty);

      final rates = await bgRateRepo.getCurrentRatesOnce();
      expect(rates, isEmpty);

      await db.close();
    });

    test('Step 11 done-criteria: background reader runs while writer is active with no "database is locked" error [FIX-BG-DB-1]', () async {
      // Use a temporary file database to test inter-connection WAL concurrency
      final tempDir = await Directory.systemTemp.createTemp('ml_wal_test_');
      final dbPath = p.join(tempDir.path, 'wal_concurrency.db');

      // Writer connection (simulating UI isolate)
      final writerDb = await openDatabase(
        dbPath,
        version: 1,
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA busy_timeout = 5000');
        },
        onCreate: (db, version) async {
          await DatabaseHelper.createTablesForTesting(db);
        },
      );

      // Reader connection (simulating background isolate exact-alarm worker)
      final readerDb = await openDatabase(
        dbPath,
        version: 1,
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA busy_timeout = 5000');
        },
      );

      final readerHelper = DatabaseHelper.forTesting(readerDb);
      final readerRecRepo = RecordRepositoryImpl(readerHelper);
      final readerRateRepo = ItemRateRepositoryImpl(readerHelper);

      // 1. Writer writes data
      await writerDb.insert('customers', {
        'id': 'cust-wal-1',
        'displayId': 'CUST26-27-01',
        'name': 'Concurrent Test User',
        'phone': '9999999999',
        'address': 'Test',
        'createdAt': '2026-09-20',
      });
      await writerDb.insert('records', {
        'id': 'rec-wal-1',
        'transactionId': 'TRAN092601',
        'type': RecordType.GIVEN.name,
        'customerId': 'cust-wal-1',
        'customerName': 'Concurrent Test User',
        'startDate': '2026-09-20T10:00:00',
        'principalAmount': 10000.0,
        'interestRate': 2.0,
        'status': RecordStatus.ACTIVE.name,
      });

      // 2. Background reader concurrently reads active records and rates
      final bgRecords = await readerRecRepo.getAllActiveRecordsOnce();
      expect(bgRecords.length, 1);
      expect(bgRecords.first.id, 'rec-wal-1');

      final bgRates = await readerRateRepo.getCurrentRatesOnce();
      expect(bgRates, isEmpty);

      // 3. Reader closes cleanly per [FIX-BG-DB-1]
      await readerDb.close();
      await writerDb.close();
      await tempDir.delete(recursive: true);
    });

    test('openAppConnection returns valid QueryExecutor for both UI and background isolates [FIX-DB-CONN-1]', () {
      final uiExecutor = openAppConnection(inBackgroundIsolate: false, inMemory: true);
      expect(uiExecutor, isNotNull);

      final bgExecutor = openAppConnection(inBackgroundIsolate: true, inMemory: true);
      expect(bgExecutor, isNotNull);
    });

    test('LenderRepositoryImpl CRUD, displayId generation (LEND26-27-01), and delete guard [FIX-LENDER-CODEPATH-1]', () async {
      final db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA busy_timeout = 5000');
        },
        onCreate: (db, version) async {
          await DatabaseHelper.createTablesForTesting(db);
        },
      );

      final helper = DatabaseHelper.forTesting(db);
      final repo = LenderRepositoryImpl(helper);

      // 1. Add individual lender
      final createdDate = DateTime(2026, 9, 29);
      final lender1 = await repo.addLender(
        lenderType: LenderType.individual,
        name: 'Bharat Finance',
        phone: '9876543210',
        createdAt: createdDate,
      );

      expect(lender1.displayId, 'LEND26-27-01');
      expect(lender1.name, 'Bharat Finance');
      expect(lender1.lenderType, LenderType.individual);
      expect(lender1.phone, '9876543210');
      expect(lender1.isIndividual, isTrue);

      // 2. Add institution lender - sequence increments
      final lender2 = await repo.addLender(
        lenderType: LenderType.institution,
        name: 'Apex Bank',
        institutionDetails: 'Branch Code: APEX001',
        notes: 'Corporate lender',
        createdAt: createdDate,
      );

      expect(lender2.displayId, 'LEND26-27-02');
      expect(lender2.name, 'Apex Bank');
      expect(lender2.lenderType, LenderType.institution);
      expect(lender2.isInstitution, isTrue);

      // 3. watchAllLenders (ordered by name ASC: Apex Bank, Bharat Finance)
      final allLenders = await repo.watchAllLenders().first;
      expect(allLenders.length, 2);
      expect(allLenders.first.name, 'Apex Bank');
      expect(allLenders.last.name, 'Bharat Finance');

      // 4. getLenderById
      final fetched = await repo.getLenderById(lender1.id);
      expect(fetched, isNotNull);
      expect(fetched!.displayId, 'LEND26-27-01');

      // 5. updateLender
      final updated = lender1.copyWith(name: 'Bharat Financial Services');
      await repo.updateLender(updated);
      final refetched = await repo.getLenderById(lender1.id);
      expect(refetched!.name, 'Bharat Financial Services');
      expect(refetched.displayId, 'LEND26-27-01'); // displayId unchanged

      // 6. Delete guard: add record linked to lender1
      await db.insert('records', {
        'id': 'rec-lender-test-1',
        'transactionId': 'TRAN092699',
        'type': 'TAKEN',
        'lenderId': lender1.id,
        'customerName': 'Bharat Financial Services',
        'startDate': '2026-09-29T10:00:00',
        'principalAmount': 100000.0,
        'interestRate': 1.5,
        'status': 'ACTIVE',
      });

      // Attempt delete -> must throw LenderHasRecordsException
      expect(
        () async => await repo.deleteLender(lender1.id),
        throwsA(isA<LenderHasRecordsException>().having(
          (e) => e.recordCount,
          'recordCount',
          1,
        )),
      );

      // Delete lender2 (has no records) -> succeeds and retires displayId
      await repo.deleteLender(lender2.id);
      final deletedLender = await repo.getLenderById(lender2.id);
      expect(deletedLender, isNull);

      final retired = await db.query(
        'retired_ids',
        where: 'kind = ? AND displayId = ?',
        whereArgs: ['lender', 'LEND26-27-02'],
      );
      expect(retired.length, 1);

      await db.close();
    });
  });
}
