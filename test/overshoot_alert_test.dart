import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/calculations/calculations.dart';
import 'package:money_lending/data/data.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Principal + Interest Overshoot Alert (§5.4 & [FIX-FEAT-OVERSHOOT-1])', () {
    final now = DateTime(2026, 6, 1);
    final rates = [
      ItemRate(
        id: 'rate-gold',
        itemCategory: 'GOLD_22K',
        ratePerUnit: 6000.0,
        effectiveDate: now,
        updatedAt: now,
      ),
    ];

    test('1. Exact boundary: projectedOutstanding == itemValueAtLending triggers OvershootWarning (>= condition)', () {
      // Loan: 10,000 principal at 2% monthly rate
      // 2 months in future (Aug 1) from Jun 1:
      // Start date: 2026-06-01. Projection date: 2026-08-01 (2 months)
      // Projected interest = 10000 * 2% * 2 = 400
      // Projected outstanding = 10000 + 400 - 0 = 10,400.
      // Item value snapshot at lending = 10,400.
      // Condition: 10,400 >= 10,400 -> alertNeeded == true!
      final record = LedgerRecord(
        id: 'rec-exact-boundary',
        transactionId: 'TXN-000030',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 6, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-1',
            recordId: 'rec-exact-boundary',
            name: 'Gold Ring',
            itemCategory: 'GOLD_22K',
            weight: 5.0, // Live value is 30,000 (safe collateral)
            purity: 100.0,
            itemValue: 10400.0, // Exact lending snapshot match
          ),
        ],
      );

      final alerts = computeCollectionAlerts([record], rates, {'rec-exact-boundary': 0.0}, now);
      final overshoots = alerts.whereType<OvershootWarning>().toList();
      expect(overshoots.length, 1);
      expect(overshoots.first.projectedOutstanding, 10400.0);
      expect(overshoots.first.itemValueAtLending, 10400.0);
      expect(overshoots.first.gap, 0.0);
    });

    test('2. SETTLED and TAKEN records are excluded from overshoot evaluation', () {
      final settledRecord = LedgerRecord(
        id: 'rec-settled',
        transactionId: 'TXN-000031',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2025, 1, 1),
        principalAmount: 10000.0,
        interestRate: 5.0,
        status: RecordStatus.SETTLED,
        items: const [
          LedgerItem(
            id: 'i-s',
            recordId: 'rec-settled',
            name: 'Item',
            itemCategory: 'GOLD_22K',
            itemValue: 5000.0,
          ),
        ],
      );

      final takenRecord = LedgerRecord(
        id: 'rec-taken',
        transactionId: 'TXN-000032',
        type: RecordType.TAKEN,
        customerId: 'c-2',
        startDate: DateTime(2025, 1, 1),
        principalAmount: 10000.0,
        interestRate: 5.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-t',
            recordId: 'rec-taken',
            name: 'Item',
            itemCategory: 'GOLD_22K',
            itemValue: 5000.0,
          ),
        ],
      );

      final alerts = computeCollectionAlerts([settledRecord, takenRecord], rates, {}, now);
      expect(alerts, isEmpty);
    });

    test('3. Uses snapshotted itemValue, NEVER live market rate, for overshoot calculation', () {
      // Live rate: GOLD_22K @ 6000.
      // Item: 1g gold (live market value = 6,000).
      // But snapshot at lending was set to 15,000!
      // Projected outstanding = 12,000.
      // If live rate were used (6,000), it would overshoot (12,000 > 6,000).
      // But using snapshotted itemValue (15,000): 12,000 < 15,000 -> NO OVERSHOOT!
      final record = LedgerRecord(
        id: 'rec-snapshot-check',
        transactionId: 'TXN-000033',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 10000.0,
        interestRate: 2.0, // 200/mo -> 7 months to Aug 1 = 1400 -> projected = 11,400
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-gold-1',
            recordId: 'rec-snapshot-check',
            name: 'Gold Charm',
            itemCategory: 'GOLD_22K',
            weight: 1.0, // 1g * 6000 = 6,000 live
            purity: 100.0,
            itemValue: 15000.0, // Stored snapshot at lending
          ),
        ],
      );

      final alerts = computeCollectionAlerts([record], rates, {'rec-snapshot-check': 0.0}, now);
      // Collateral drop triggers because live collateral (6,000) <= totalDue (11,000)
      expect(alerts.any((a) => a is CollateralDrop), isTrue);
      // BUT OvershootWarning MUST NOT trigger because 11,400 < 15,000 snapshot!
      expect(alerts.any((a) => a is OvershootWarning), isFalse);
    });

    test('4. Unified Collection Alert Cards compute side-by-side figures for every active given record', () {
      final recordA = LedgerRecord(
        id: 'rec-card-1',
        transactionId: 'TXN-000040',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'item-card-1',
            recordId: 'rec-card-1',
            name: 'Gold Ring',
            itemCategory: 'GOLD_22K',
            weight: 1.0, // live = 6,000 (totalDue = 11,000 -> underwater)
            purity: 100.0,
            itemValue: 20000.0, // projected = 11,400 < 20,000 (safe projection)
          ),
        ],
      );

      final recordSafe = LedgerRecord(
        id: 'rec-card-safe',
        transactionId: 'TXN-000041',
        type: RecordType.GIVEN,
        customerId: 'c-2',
        startDate: DateTime(2026, 5, 1),
        principalAmount: 5000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'item-card-2',
            recordId: 'rec-card-safe',
            name: 'Gold Bracelet',
            itemCategory: 'GOLD_22K',
            weight: 5.0, // live = 30,000 >> 5,100 (safe collateral)
            purity: 100.0,
            itemValue: 25000.0, // projected = 5,300 << 25,000 (safe projection)
          ),
        ],
      );

      final cards = computeCollectionAlertCards([recordSafe, recordA], rates, {}, now);
      expect(cards.length, 2);

      // Card 1: Triggered card sorted first
      final triggeredCard = cards.first;
      expect(triggeredCard.record.id, 'rec-card-1');
      expect(triggeredCard.isCollateralUnderwater, isTrue);
      expect(triggeredCard.isOvershoot, isFalse);
      expect(triggeredCard.isTriggered, isTrue);
      expect(triggeredCard.isSafe, isFalse);

      // Card 2: Safe card
      final safeCard = cards.last;
      expect(safeCard.record.id, 'rec-card-safe');
      expect(safeCard.isCollateralUnderwater, isFalse);
      expect(safeCard.isOvershoot, isFalse);
      expect(safeCard.isTriggered, isFalse);
      expect(safeCard.isSafe, isTrue);
    });
  });

  group('DAO Query RecordDao.getTotalPaidByRecordIds & Chunking Integration (§5.4)', () {
    late Database db;
    late DatabaseHelper dbHelper;
    late RecordRepositoryImpl recordRepo;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE records (
              id TEXT PRIMARY KEY NOT NULL,
              transactionId TEXT NOT NULL UNIQUE,
              type TEXT NOT NULL,
              customerId TEXT NOT NULL,
              customerName TEXT,
              startDate TEXT NOT NULL,
              endDate TEXT,
              principalAmount REAL NOT NULL,
              interestRate REAL NOT NULL,
              status TEXT NOT NULL,
              settledDate TEXT,
              calculatedInterest REAL,
              linkedRecordId TEXT
            );
          ''');
          await db.execute('''
            CREATE TABLE ledger_items (
              id TEXT PRIMARY KEY NOT NULL,
              recordId TEXT NOT NULL,
              name TEXT NOT NULL,
              itemCategory TEXT NOT NULL,
              description TEXT,
              weight REAL,
              purity REAL,
              rate REAL,
              itemValue REAL,
              lendPercentage REAL,
              lendableAmount REAL
            );
          ''');
          await db.execute('''
            CREATE TABLE payments (
              id TEXT PRIMARY KEY NOT NULL,
              recordId TEXT NOT NULL,
              amount REAL NOT NULL,
              date TEXT NOT NULL,
              notes TEXT,
              interestPaid REAL NOT NULL,
              principalPaid REAL NOT NULL
            );
          ''');
        },
      );

      dbHelper = DatabaseHelper.forTesting(db);
      recordRepo = RecordRepositoryImpl(dbHelper);
    });

    tearDown(() async {
      await db.close();
    });

    test('RecordDao.getTotalPaidByRecordIds returns aggregated payments for specific IDs', () async {
      final recordDao = await dbHelper.recordDao;

      // Insert payments for 2 records
      await db.insert('payments', {
        'id': 'p1',
        'recordId': 'rec-1',
        'amount': 500.0,
        'date': '2026-01-10T10:00:00',
        'interestPaid': 400.0,
        'principalPaid': 100.0,
      });
      await db.insert('payments', {
        'id': 'p2',
        'recordId': 'rec-1',
        'amount': 300.0,
        'date': '2026-02-10T10:00:00',
        'interestPaid': 300.0,
        'principalPaid': 0.0,
      });
      await db.insert('payments', {
        'id': 'p3',
        'recordId': 'rec-2',
        'amount': 1000.0,
        'date': '2026-03-10T10:00:00',
        'interestPaid': 500.0,
        'principalPaid': 500.0,
      });

      // 1. Test DAO query directly
      final daoTotals = await recordDao.getTotalPaidByRecordIds(['rec-1', 'rec-2']);
      expect(daoTotals.length, 2);
      final r1 = daoTotals.firstWhere((p) => p.recordId == 'rec-1');
      expect(r1.totalPaid, 800.0); // 500 + 300
      final r2 = daoTotals.firstWhere((p) => p.recordId == 'rec-2');
      expect(r2.totalPaid, 1000.0);

      // 2. Test RecordRepositoryImpl mapping from RecordTotalPaid -> RecordPaymentTotal
      final repoTotals = await recordRepo.getTotalPaidByRecordIds(['rec-1']);
      expect(repoTotals.length, 1);
      expect(repoTotals.first.recordId, 'rec-1');
      expect(repoTotals.first.totalPaid, 800.0);
      expect(repoTotals.first, isA<RecordPaymentTotal>());
    });
  });
}
