import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/data/data.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ItemRateDao itemRateDao;

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
            CREATE TABLE item_rates (
              id TEXT PRIMARY KEY,
              itemCategory TEXT NOT NULL,
              ratePerUnit REAL NOT NULL,
              effectiveDate TEXT NOT NULL,
              updatedAt TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE UNIQUE INDEX idx_item_rates_cat_date ON item_rates(itemCategory, effectiveDate)',
          );
        },
      ),
    );
    itemRateDao = ItemRateDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('ItemRateRepository & DAO Pattern Tests (§4.5 & [FIX-ARCH-ITEMRATE-1])', () {
    test('upsertRate matches on (itemCategory, effectiveDate) NOT on id and preserves existing id', () async {
      const initialRate = ItemRateEntity(
        id: 'rate-uuid-001',
        itemCategory: 'GOLD_22K',
        ratePerUnit: 6000.0,
        effectiveDate: '2026-09-10',
        updatedAt: '2026-09-10T10:00:00',
      );

      // 1. Initial insert
      await itemRateDao.upsert(initialRate);

      final row1 = await itemRateDao.getByItemCategoryAndDate('GOLD_22K', '2026-09-10');
      expect(row1, isNotNull);
      expect(row1!.id, 'rate-uuid-001');
      expect(row1.ratePerUnit, 6000.0);

      // 2. Subsequent update with DIFFERENT ID passed in, but SAME (category, date)
      const updatedRate = ItemRateEntity(
        id: 'different-uuid-999', // Should NOT overwrite existing UUID id
        itemCategory: 'GOLD_22K',
        ratePerUnit: 6250.0,
        effectiveDate: '2026-09-10',
        updatedAt: '2026-09-10T15:30:00',
      );

      await itemRateDao.upsert(updatedRate);

      final row2 = await itemRateDao.getByItemCategoryAndDate('GOLD_22K', '2026-09-10');
      expect(row2, isNotNull);
      // Mandated by §4.5: preserves existing id on update for correct historical audit trails
      expect(row2!.id, 'rate-uuid-001', reason: 'Existing UUID id MUST be preserved on update');
      expect(row2.ratePerUnit, 6250.0);
      expect(row2.updatedAt, '2026-09-10T15:30:00');

      // Table should only have 1 row
      final allRows = await itemRateDao.getAll();
      expect(allRows.length, 1);
    });

    test('getLatestForEveryCategory returns the newest rate per category', () async {
      // Rates for GOLD_22K across 2 dates
      await itemRateDao.upsert(const ItemRateEntity(
        id: 'gold-old',
        itemCategory: 'GOLD_22K',
        ratePerUnit: 5800.0,
        effectiveDate: '2026-09-01',
        updatedAt: '2026-09-01T10:00:00',
      ));
      await itemRateDao.upsert(const ItemRateEntity(
        id: 'gold-new',
        itemCategory: 'GOLD_22K',
        ratePerUnit: 6100.0,
        effectiveDate: '2026-09-10',
        updatedAt: '2026-09-10T10:00:00',
      ));

      // Rate for SILVER
      await itemRateDao.upsert(const ItemRateEntity(
        id: 'silver-1',
        itemCategory: 'SILVER',
        ratePerUnit: 85.0,
        effectiveDate: '2026-09-05',
        updatedAt: '2026-09-05T10:00:00',
      ));

      final latestRates = await itemRateDao.getLatestForEveryCategory();
      expect(latestRates.length, 2);

      final gold = latestRates.firstWhere((r) => r.itemCategory == 'GOLD_22K');
      expect(gold.ratePerUnit, 6100.0);
      expect(gold.effectiveDate, '2026-09-10');

      final silver = latestRates.firstWhere((r) => r.itemCategory == 'SILVER');
      expect(silver.ratePerUnit, 85.0);
      expect(silver.effectiveDate, '2026-09-05');
    });

    test('getRatesForDate returns all rates matching the ISO date', () async {
      await itemRateDao.upsert(const ItemRateEntity(
        id: 'gold-date',
        itemCategory: 'GOLD_22K',
        ratePerUnit: 6000.0,
        effectiveDate: '2026-09-10',
        updatedAt: '2026-09-10T10:00:00',
      ));
      await itemRateDao.upsert(const ItemRateEntity(
        id: 'silver-date',
        itemCategory: 'SILVER',
        ratePerUnit: 90.0,
        effectiveDate: '2026-09-10',
        updatedAt: '2026-09-10T10:00:00',
      ));
      await itemRateDao.upsert(const ItemRateEntity(
        id: 'gold-other-date',
        itemCategory: 'GOLD_22K',
        ratePerUnit: 5900.0,
        effectiveDate: '2026-09-09',
        updatedAt: '2026-09-09T10:00:00',
      ));

      final ratesFor10th = await itemRateDao.getRatesForDate('2026-09-10');
      expect(ratesFor10th.length, 2);
      expect(ratesFor10th.map((r) => r.itemCategory).toList(), containsAll(['GOLD_22K', 'SILVER']));

      final ratesFor9th = await itemRateDao.getRatesForDate('2026-09-09');
      expect(ratesFor9th.length, 1);
      expect(ratesFor9th.first.itemCategory, 'GOLD_22K');
    });

    test('Concurrent upserts on same (itemCategory, effectiveDate) are safe [FIX-DEVCONCURRENCY-1]', () async {
      // Simulate concurrent coroutines writing to the same category and date
      final futures = List.generate(10, (index) {
        return itemRateDao.upsert(ItemRateEntity(
          id: 'concurrent-$index',
          itemCategory: 'PLATINUM',
          ratePerUnit: 3000.0 + index,
          effectiveDate: '2026-09-10',
          updatedAt: '2026-09-10T12:00:0$index',
        ));
      });

      await Future.wait(futures);

      final rows = await db.query(
        'item_rates',
        where: 'itemCategory = ? AND effectiveDate = ?',
        whereArgs: ['PLATINUM', '2026-09-10'],
      );

      // Exactly 1 row must exist due to check-then-branch & unique index
      expect(rows.length, 1);
    });

    test('ItemRate domain model formats dates correctly', () {
      final rate = ItemRate(
        id: 'rate-fmt',
        itemCategory: 'GOLD_24K',
        ratePerUnit: 7000.0,
        effectiveDate: DateTime(2026, 9, 10),
        updatedAt: DateTime(2026, 9, 10, 14, 30),
      );

      expect(rate.formattedEffectiveDate, '10 September 2026');
      expect(rate.formattedUpdatedAt, '10 September 2026, 02:30 PM');
    });
  });
}
