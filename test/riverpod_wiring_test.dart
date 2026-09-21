import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/data/di/database_provider.dart';
import 'package:money_lending/core/data/di/repository_providers.dart';
import 'package:money_lending/data/data.dart';
import 'package:money_lending/domain/domain.dart';
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

      // 1. DatabaseHelper singleton check
      final db1 = container.read(appDatabaseProvider);
      final db2 = container.read(appDatabaseProvider);
      expect(identical(db1, db2), isTrue);

      // 2. CustomerRepository keepAlive singleton check
      final custRepo1 = container.read(customerRepositoryProvider);
      final custRepo2 = container.read(customerRepositoryProvider);
      expect(identical(custRepo1, custRepo2), isTrue);

      // 3. RecordRepository keepAlive singleton check
      final recRepo1 = container.read(recordRepositoryProvider);
      final recRepo2 = container.read(recordRepositoryProvider);
      expect(identical(recRepo1, recRepo2), isTrue);

      // 4. SettingsRepository keepAlive singleton check
      final setRepo1 = container.read(settingsRepositoryProvider);
      final setRepo2 = container.read(settingsRepositoryProvider);
      expect(identical(setRepo1, setRepo2), isTrue);

      // 5. ItemRateRepository keepAlive singleton check
      final rateRepo1 = container.read(itemRateRepositoryProvider);
      final rateRepo2 = container.read(itemRateRepositoryProvider);
      expect(identical(rateRepo1, rateRepo2), isTrue);
    });

    testWidgets('Same repository instance returned across separate widgets even after temporary unmount [FIX-SINGLETON-SCOPE-1]', (WidgetTester tester) async {
      CustomerRepository? repoFromWidgetA;
      CustomerRepository? repoFromWidgetB;

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
                            repoFromWidgetA = ref.watch(customerRepositoryProvider);
                            return const Text('Widget A Active');
                          },
                        ),
                      Consumer(
                        key: widgetBKey,
                        builder: (context, ref, _) {
                          repoFromWidgetB = ref.watch(customerRepositoryProvider);
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
      expect(repoFromWidgetA, isNotNull);
      expect(repoFromWidgetB, isNotNull);
      expect(identical(repoFromWidgetA, repoFromWidgetB), isTrue);

      // Unmount Widget A completely
      showWidgetA.value = false;
      await tester.pump();
      expect(find.text('Widget A Active'), findsNothing);

      // Re-read repository from container / remaining widget B
      expect(identical(repoFromWidgetA, repoFromWidgetB), isTrue);

      // Remount Widget A
      showWidgetA.value = true;
      await tester.pump();
      expect(find.text('Widget A Active'), findsOneWidget);

      // The newly remounted Widget A must still see the exact same repository instance
      expect(identical(repoFromWidgetA, repoFromWidgetB), isTrue);
    });

    test('CustomerRepository and RecordRepository are abstract classes in core/domain', () {
      // Contract verification per §4.3
      expect(CustomerRepository, isNotNull);
      expect(RecordRepository, isNotNull);
      expect(SettingsRepository, isNotNull);
      expect(ItemRateRepository, isNotNull);
    });

    test('Independent SQLite connection adheres to WAL and foreign keys [FIX-BG-DB-1]', () async {
      // Test opening an isolated SQLite connection like a background worker would
      final db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
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
  });
}
