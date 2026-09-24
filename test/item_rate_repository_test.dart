import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/data/data.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ItemRateDao itemRateDao;
  late DatabaseHelper dbHelper;
  late ItemRateRepository itemRateRepo;

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
    dbHelper = DatabaseHelper.forTesting(db);
    itemRateRepo = ItemRateRepositoryImpl(dbHelper);
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

    test('ItemRateRepository watchCurrentRate streams latest rate for category or null (§4.5)', () async {
      // Initially null
      final initial = await itemRateRepo.watchCurrentRate('GOLD_22K').first;
      expect(initial, isNull);

      // Upsert a rate
      await itemRateRepo.upsertRate(ItemRate(
        id: 'r-1',
        itemCategory: 'GOLD_22K',
        ratePerUnit: 6500.0,
        effectiveDate: DateTime(2026, 9, 20),
        updatedAt: DateTime.now(),
      ));

      final fetched = await itemRateRepo.watchCurrentRate('GOLD_22K').first;
      expect(fetched, isNotNull);
      expect(fetched!.ratePerUnit, 6500.0);
    });

    test('ItemRateRepository watchCurrentRates streams latest rates for Rate Management Card (§4.5)', () async {
      await itemRateRepo.upsertRate(ItemRate(
        id: 'r-g',
        itemCategory: 'GOLD_22K',
        ratePerUnit: 6600.0,
        effectiveDate: DateTime(2026, 9, 20),
        updatedAt: DateTime.now(),
      ));
      await itemRateRepo.upsertRate(ItemRate(
        id: 'r-s',
        itemCategory: 'SILVER',
        ratePerUnit: 95.0,
        effectiveDate: DateTime(2026, 9, 20),
        updatedAt: DateTime.now(),
      ));

      final allRates = await itemRateRepo.watchCurrentRates().first;
      expect(allRates.length, 2);
      expect(allRates.any((r) => r.itemCategory == 'GOLD_22K'), isTrue);
      expect(allRates.any((r) => r.itemCategory == 'SILVER'), isTrue);
    });

    test('ItemRateRepository getCurrentRatesOnce executes one-shot fetch for background isolate [FIX-OVERDUECOLLATERAL-1]', () async {
      await itemRateRepo.upsertRate(ItemRate(
        id: 'r-bg',
        itemCategory: 'DIAMOND',
        ratePerUnit: 50000.0,
        effectiveDate: DateTime(2026, 9, 20),
        updatedAt: DateTime.now(),
      ));

      // Must be a Future<List<ItemRate>>, NOT a Stream
      final futureRates = await itemRateRepo.getCurrentRatesOnce();
      expect(futureRates, isA<List<ItemRate>>());
      expect(futureRates.any((r) => r.itemCategory == 'DIAMOND'), isTrue);
    });

    test('ItemRateRepository watchRatesForDate filters by DateTime date (§4.5)', () async {
      final date1 = DateTime(2026, 9, 15);
      final date2 = DateTime(2026, 9, 20);

      await itemRateRepo.upsertRate(ItemRate(
        id: 'r-hist-1',
        itemCategory: 'GOLD_18K',
        ratePerUnit: 4800.0,
        effectiveDate: date1,
        updatedAt: DateTime.now(),
      ));
      await itemRateRepo.upsertRate(ItemRate(
        id: 'r-hist-2',
        itemCategory: 'GOLD_18K',
        ratePerUnit: 5000.0,
        effectiveDate: date2,
        updatedAt: DateTime.now(),
      ));

      final ratesDate1 = await itemRateRepo.watchRatesForDate(date1).first;
      expect(ratesDate1.length, 1);
      expect(ratesDate1.first.ratePerUnit, 4800.0);

      final ratesDate2 = await itemRateRepo.watchRatesForDate(date2).first;
      expect(ratesDate2.length, 1);
      expect(ratesDate2.first.ratePerUnit, 5000.0);
    });

    test('ItemRateRepository upsertRate preserves existing UUID id and never reassigns it (§4.5)', () async {
      final initial = ItemRate(
        id: 'fixed-uuid-12345',
        itemCategory: 'BRONZE',
        ratePerUnit: 500.0,
        effectiveDate: DateTime(2026, 9, 20),
        updatedAt: DateTime.now(),
      );
      await itemRateRepo.upsertRate(initial);

      // Second upsert with different ID passed in
      final updated = ItemRate(
        id: 'new-unwanted-id',
        itemCategory: 'BRONZE',
        ratePerUnit: 550.0,
        effectiveDate: DateTime(2026, 9, 20),
        updatedAt: DateTime.now(),
      );
      await itemRateRepo.upsertRate(updated);

      final current = await itemRateRepo.getCurrentRateOnce('BRONZE');
      expect(current, isNotNull);
      expect(current!.id, 'fixed-uuid-12345', reason: 'Existing UUID id must be preserved across upserts');
      expect(current.ratePerUnit, 550.0);
    });

    test('getRateAsOf returns latest usable rate on or before target date [FIX-RATE-ASOF-1]', () async {
      // Historical rate on 2026-09-01
      await itemRateRepo.upsertRate(ItemRate(
        id: 'gold-sep01',
        itemCategory: 'GOLD_22K',
        ratePerUnit: 6000.0,
        effectiveDate: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1, 10, 0),
      ));

      // Intermediate rate on 2026-09-10
      await itemRateRepo.upsertRate(ItemRate(
        id: 'gold-sep10',
        itemCategory: 'GOLD_22K',
        ratePerUnit: 6200.0,
        effectiveDate: DateTime(2026, 9, 10),
        updatedAt: DateTime(2026, 9, 10, 10, 0),
      ));

      // Later rate on 2026-09-20
      await itemRateRepo.upsertRate(ItemRate(
        id: 'gold-sep20',
        itemCategory: 'GOLD_22K',
        ratePerUnit: 6500.0,
        effectiveDate: DateTime(2026, 9, 20),
        updatedAt: DateTime(2026, 9, 20, 10, 0),
      ));

      // Query as of 2026-09-15: should pick 2026-09-10 (6200.0)
      final rateAsOf15 = await itemRateRepo.getRateAsOf('GOLD_22K', DateTime(2026, 9, 15, 14, 30));
      expect(rateAsOf15, isNotNull);
      expect(rateAsOf15!.ratePerUnit, 6200.0);
      expect(rateAsOf15.effectiveDate, DateTime(2026, 9, 10));

      // Query as of exact date 2026-09-10: should match 2026-09-10 (6200.0)
      final rateAsOf10 = await itemRateRepo.getRateAsOf('GOLD_22K', DateTime(2026, 9, 10));
      expect(rateAsOf10, isNotNull);
      expect(rateAsOf10!.ratePerUnit, 6200.0);

      // Query as of before earliest date (2026-08-31): should be null
      final rateBefore = await itemRateRepo.getRateAsOf('GOLD_22K', DateTime(2026, 8, 31));
      expect(rateBefore, isNull);

      // Query for non-existent category: should be null
      final nonExistent = await itemRateRepo.getRateAsOf('PLATINUM', DateTime(2026, 9, 15));
      expect(nonExistent, isNull);
    });

    test('getRateAsOf ignores rates with ratePerUnit <= 0 [FIX-RATE-ASOF-1]', () async {
      // Valid earlier rate
      await itemRateRepo.upsertRate(ItemRate(
        id: 'silver-valid',
        itemCategory: 'SILVER',
        ratePerUnit: 80.0,
        effectiveDate: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1, 10, 0),
      ));

      // Zero-rate entry on 2026-09-05 (e.g. rate unset / invalid)
      await itemRateRepo.upsertRate(ItemRate(
        id: 'silver-zero',
        itemCategory: 'SILVER',
        ratePerUnit: 0.0,
        effectiveDate: DateTime(2026, 9, 5),
        updatedAt: DateTime(2026, 9, 5, 10, 0),
      ));

      // Negative-rate entry on 2026-09-08
      await itemRateRepo.upsertRate(ItemRate(
        id: 'silver-negative',
        itemCategory: 'SILVER',
        ratePerUnit: -10.0,
        effectiveDate: DateTime(2026, 9, 8),
        updatedAt: DateTime(2026, 9, 8, 10, 0),
      ));

      // Query as of 2026-09-09: should skip 0 and negative rates and return the 80.0 rate from 2026-09-01
      final rate = await itemRateRepo.getRateAsOf('SILVER', DateTime(2026, 9, 9));
      expect(rate, isNotNull);
      expect(rate!.ratePerUnit, 80.0);
      expect(rate.effectiveDate, DateTime(2026, 9, 1));
    });
  });
}
