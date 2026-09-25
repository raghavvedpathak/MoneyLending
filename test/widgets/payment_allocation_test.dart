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

  group('Interest-First Payment Allocation (§5.2.4 & [FIX-STEP3-GATE-1])', () {
    test('1. (Case 2) Partial payment less than outstanding interest: all goes to interest', () {
      // Outstanding interest = 500, customer pays 200
      final allocation = allocatePayment(paymentAmount: 200.0, outstandingInterest: 500.0);

      expect(allocation.interestPaid, 200.0);
      expect(allocation.principalPaid, 0.0);
      expect(allocation.first, 200.0);
      expect(allocation.second, 0.0);

      final (interestPaid, principalPaid) = allocation.asRecord;
      expect(interestPaid, 200.0);
      expect(principalPaid, 0.0);
    });

    test('2. (Case 4) Payment exactly equal to outstanding interest: extinguishes interest, principalPaid == 0.0', () {
      // Outstanding interest = 400, customer pays 400
      final allocation = allocatePayment(paymentAmount: 400.0, outstandingInterest: 400.0);

      expect(allocation.interestPaid, 400.0);
      expect(allocation.principalPaid, 0.0);
    });

    test('3. (Case 1) Payment exceeds outstanding interest: extinguishes interest, remainder reduces principal', () {
      // Outstanding interest = 400, customer pays 1500
      final allocation = allocatePayment(paymentAmount: 1500.0, outstandingInterest: 400.0);

      expect(allocation.interestPaid, 400.0);
      expect(allocation.principalPaid, 1100.0); // 1500 - 400
    });

    test('4. (Case 3) Zero outstanding interest: 100% of payment reduces principal', () {
      // Outstanding interest = 0, customer pays 1000
      final allocation = allocatePayment(paymentAmount: 1000.0, outstandingInterest: 0.0);

      expect(allocation.interestPaid, 0.0);
      expect(allocation.principalPaid, 1000.0);
    });

    test('5. (Case 5) [FIX-ALLOCATE-NEGATIVE-1] Negative payment amount (refund) reduces principal, interest untouched', () {
      // Customer refund / payback of overpayment
      final negAlloc = allocatePayment(paymentAmount: -100.0, outstandingInterest: 500.0);
      expect(negAlloc.interestPaid, 0.0);
      expect(negAlloc.principalPaid, -100.0);

      final zeroAlloc = allocatePayment(paymentAmount: 0.0, outstandingInterest: 500.0);
      expect(zeroAlloc.interestPaid, 0.0);
      expect(zeroAlloc.principalPaid, 0.0);
    });

    test('6. (Case 6) [FIX-MONEY-1] Rounding: 500.10 with 154.32 outstandingInterest returns (154.32, 345.78)', () {
      final alloc = allocatePayment(paymentAmount: 500.10, outstandingInterest: 154.32);
      expect(alloc.interestPaid, 154.32);
      expect(alloc.principalPaid, 345.78);
    });

    test('7. Financials isPrincipalFullyPaid and LedgerRecord canBeSettled helpers', () {
      const activeFinUnderpaid = Financials(
        principal: 10000.0,
        totalInterest: 400.0,
        totalPaid: 2000.0,
        interestPaid: 400.0,
        principalPaid: 1600.0, // < 10000
        outstandingInterest: 0.0,
        outstandingPrincipal: 8400.0,
        totalDue: 8400.0,
      );
      expect(activeFinUnderpaid.isPrincipalFullyPaid, isFalse);

      const activeFinFullyPaid = Financials(
        principal: 10000.0,
        totalInterest: 400.0,
        totalPaid: 10400.0,
        interestPaid: 400.0,
        principalPaid: 10000.0, // == 10000
        outstandingInterest: 0.0,
        outstandingPrincipal: 0.0,
        totalDue: 0.0,
      );
      expect(activeFinFullyPaid.isPrincipalFullyPaid, isTrue);

      final activeRecord = LedgerRecord(
        id: 'rec-can-settle',
        transactionId: 'TXN-000001',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );
      expect(activeRecord.canBeSettled, isTrue);

      final settledRecord = activeRecord.copyWith(status: RecordStatus.SETTLED);
      expect(settledRecord.canBeSettled, isFalse);
    });
  });

  group('[FIX-DEV-FRESHFETCH-1] Stale Record Guard & Payment Recording Integration', () {
    late Database db;
    late DatabaseHelper dbHelper;
    late RecordRepositoryImpl recordRepo;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE customers (
              id TEXT PRIMARY KEY NOT NULL,
              displayId TEXT NOT NULL UNIQUE,
              name TEXT NOT NULL,
              phone TEXT NOT NULL,
              address TEXT NOT NULL,
              createdAt TEXT NOT NULL
            );
          ''');
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
              principalPaid REAL NOT NULL,
              paymentId TEXT
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

    test('Fresh fetch immediately before payment allocation accurately splits interest and principal', () async {
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 60)); // ~2 months ago

      final insertedRecord = await recordRepo.insertRecord(LedgerRecord(
        id: 'rec-test-alloc',
        transactionId: '',
        type: RecordType.GIVEN,
        customerId: 'c-test',
        startDate: startDate,
        principalAmount: 10000.0,
        interestRate: 2.0, // 200 per month -> 400 for 2 months
        status: RecordStatus.ACTIVE,
      ));

      // 1. Simulate Fresh Fetch in PaymentViewModel.recordPayment() [FIX-DEV-FRESHFETCH-1]
      final freshRecord1 = await recordRepo.getRecordById(insertedRecord.id);
      expect(freshRecord1, isNotNull);
      expect(freshRecord1!.payments, isEmpty);

      // 2. Compute outstanding interest with fresh record
      final fin1 = calculateRecordFinancials(freshRecord1, now, now);
      expect(fin1.totalInterest, 400.0);
      expect(fin1.outstandingInterest, 400.0);

      // 3. User pays 500: interest-first allocation
      final alloc1 = allocatePayment(paymentAmount: 500.0, outstandingInterest: fin1.outstandingInterest);
      expect(alloc1.interestPaid, 400.0); // full interest extinguished
      expect(alloc1.principalPaid, 100.0); // 100 off principal

      // 4. Record payment in repository
      await recordRepo.addPayment(Payment(
        id: 'pay-1',
        recordId: insertedRecord.id,
        amount: 500.0,
        date: now,
        notes: 'First payment',
        interestPaid: alloc1.interestPaid,
        principalPaid: alloc1.principalPaid,
      ));

      // 5. Fresh fetch immediately for second payment — must see eagerly-loaded pay-1!
      final freshRecord2 = await recordRepo.getRecordById(insertedRecord.id);
      expect(freshRecord2, isNotNull);
      expect(freshRecord2!.payments.length, 1);
      expect(freshRecord2.payments.first.interestPaid, 400.0);
      expect(freshRecord2.payments.first.principalPaid, 100.0);

      // 6. Compute outstanding interest for second payment on same day
      final fin2 = calculateRecordFinancials(freshRecord2, now, now);
      expect(fin2.totalInterest, 400.0);
      expect(fin2.interestPaid, 400.0);
      expect(fin2.outstandingInterest, 0.0); // all accrued interest is already paid!
      expect(fin2.outstandingPrincipal, 9900.0); // 10000 - 100

      // 7. Second payment of 9900: with outstandingInterest == 0.0, 100% goes to principal
      final alloc2 = allocatePayment(paymentAmount: 9900.0, outstandingInterest: fin2.outstandingInterest);
      expect(alloc2.interestPaid, 0.0);
      expect(alloc2.principalPaid, 9900.0);

      await recordRepo.addPayment(Payment(
        id: 'pay-2',
        recordId: insertedRecord.id,
        amount: 9900.0,
        date: now,
        notes: 'Final payoff',
        interestPaid: alloc2.interestPaid,
        principalPaid: alloc2.principalPaid,
      ));

      // 8. Fresh fetch after second payment — principal is fully paid!
      final freshRecord3 = await recordRepo.getRecordById(insertedRecord.id);
      final fin3 = calculateRecordFinancials(freshRecord3!, now, now);
      expect(fin3.principalPaid, 10000.0);
      expect(fin3.outstandingPrincipal, 0.0);
      expect(fin3.isPrincipalFullyPaid, isTrue);

      // 9. Mark as Settled confirmation trigger (§5.2.4)
      expect(freshRecord3.canBeSettled, isTrue);
      await recordRepo.settleRecord(freshRecord3.id, fin3.totalInterest);

      final settledRecord = await recordRepo.getRecordById(insertedRecord.id);
      expect(settledRecord!.status, RecordStatus.SETTLED);
      expect(settledRecord.settledDate, isNotNull);
      expect(settledRecord.calculatedInterest, 400.0);
      expect(settledRecord.canBeSettled, isFalse);
    });
  });
}
