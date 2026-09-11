import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/calculations/calculation_engine.dart';
import 'package:money_lending/core/pdf/pdf.dart';
import 'package:money_lending/domain/domain.dart';

void main() {
  // Fixed evaluation date for deterministic testing
  final testToday = DateTime(2026, 6, 1);

  // ===========================================================================
  // CANONICAL TEST DATASET WITH KNOWN INPUTS (§5.5)
  // ===========================================================================
  final customer1 = Customer(
    id: 'c-1',
    displayId: 'CUST-0001',
    name: 'Ramesh Sharma',
    phone: '9876543210',
    address: '12 Market Road',
    createdAt: DateTime(2026, 1, 1),
  );

  final customer2 = Customer(
    id: 'c-2',
    displayId: 'CUST-0002',
    name: 'Suresh Verma',
    phone: '9123456780',
    createdAt: DateTime(2026, 1, 15),
  );

  final customer3 = Customer(
    id: 'c-3',
    displayId: 'CUST-0003',
    name: 'Priya Patel',
    createdAt: DateTime(2026, 2, 1),
  );

  final itemGold = const LedgerItem(
    id: 'item-gold-1',
    recordId: 'rec-given-1',
    name: 'Gold Chain',
    itemCategory: 'GOLD_22K',
    weight: 10.0,
    purity: 91.6, // 91.6%
    rate: 6000.0, // itemValue = 10 * 0.916 * 6000 = 54,960.0
    lendPercentage: 80.0,
  );

  final itemSilver = const LedgerItem(
    id: 'item-silver-1',
    recordId: 'rec-given-2',
    name: 'Silver Anklet',
    itemCategory: 'SILVER',
    weight: 100.0,
    purity: 99.9, // 99.9%
    rate: 80.0, // itemValue = 100 * 0.999 * 80 = 7,992.0
    lendPercentage: 70.0,
  );

  // Active Given record with partial payments
  // Start: 2026-01-01, Target: 2026-06-01 -> 5.0 months
  // Principal: 20,000, Rate: 2.0% -> Total Interest: 20,000 * 2% * 5 = 2,000.0
  // Payments:
  // - p1: 2026-02-01: 400.0 (interestPaid: 400.0, principalPaid: 0.0)
  // - p2: 2026-03-01: 1,400.0 (interestPaid: 400.0, principalPaid: 1,000.0)
  // Aggregates:
  // - totalPaid = 1,800.0
  // - interestPaid = 800.0
  // - principalPaid = 1,000.0
  // - outstandingInterest = 2,000 - 800 = 1,200.0
  // - outstandingPrincipal = 20,000 - 1,000 = 19,000.0
  // - totalDue = 19,000 + 1,200 = 20,200.0
  final recGivenActive1 = LedgerRecord(
    id: 'rec-given-1',
    transactionId: 'TXN-000001',
    type: RecordType.GIVEN,
    customerId: 'c-1',
    customerName: 'Ramesh Sharma',
    startDate: DateTime(2026, 1, 1),
    principalAmount: 20000.0,
    interestRate: 2.0,
    status: RecordStatus.ACTIVE,
    items: [itemGold],
    payments: [
      Payment(
        id: 'p-1',
        recordId: 'rec-given-1',
        amount: 400.0,
        date: DateTime(2026, 2, 1, 10, 0),
        interestPaid: 400.0,
        principalPaid: 0.0,
      ),
      Payment(
        id: 'p-2',
        recordId: 'rec-given-1',
        amount: 1400.0,
        date: DateTime(2026, 3, 1, 11, 30),
        interestPaid: 400.0,
        principalPaid: 1000.0,
      ),
    ],
  );

  // Active Given record with ZERO payments and past endDate (capped!)
  // Start: 2026-03-01, endDate: 2026-05-01 (<= today 2026-06-01 -> capped at 2.0 months!)
  // Principal: 10,000, Rate: 1.5% -> Total Interest: 10,000 * 1.5% * 2 = 300.0
  // Payments: ZERO
  // Aggregates:
  // - totalPaid = 0.0, interestPaid = 0.0, principalPaid = 0.0
  // - outstandingInterest = 300.0
  // - outstandingPrincipal = 10,000.0
  // - totalDue = 10,300.0
  final recGivenActive2 = LedgerRecord(
    id: 'rec-given-2',
    transactionId: 'TXN-000002',
    type: RecordType.GIVEN,
    customerId: 'c-2',
    customerName: 'Suresh Verma',
    startDate: DateTime(2026, 3, 1),
    endDate: DateTime(2026, 5, 1),
    principalAmount: 10000.0,
    interestRate: 1.5,
    status: RecordStatus.ACTIVE,
    items: [itemSilver],
    payments: const [],
  );

  // Active Taken record
  // Start: 2026-02-01, Target: 2026-06-01 -> 4.0 months
  // Principal: 15,000, Rate: 1.0% -> Total Interest: 15,000 * 1% * 4 = 600.0
  // Total Due: 15,600.0
  final recTakenActive = LedgerRecord(
    id: 'rec-taken-1',
    transactionId: 'TXN-000003',
    type: RecordType.TAKEN,
    customerId: 'c-1',
    startDate: DateTime(2026, 2, 1),
    principalAmount: 15000.0,
    interestRate: 1.0,
    status: RecordStatus.ACTIVE,
  );

  // Settled Given record with calculatedInterest snapshotted (§5.2.1)
  final recSettled = LedgerRecord(
    id: 'rec-settled-1',
    transactionId: 'TXN-000004',
    type: RecordType.GIVEN,
    customerId: 'c-2',
    startDate: DateTime(2026, 1, 1),
    settledDate: DateTime(2026, 3, 1),
    status: RecordStatus.SETTLED,
    principalAmount: 5000.0,
    interestRate: 2.0,
    calculatedInterest: 200.0,
    payments: [
      Payment(
        id: 'p-settle',
        recordId: 'rec-settled-1',
        amount: 5200.0,
        date: DateTime(2026, 3, 1),
        interestPaid: 200.0,
        principalPaid: 5000.0,
      ),
    ],
  );

  final allCustomers = [customer1, customer2, customer3];
  final allRecords = [recGivenActive1, recGivenActive2, recTakenActive, recSettled];

  group('5.5 Testing Strategy: Known Dataset Outputs & Every Calculation Function', () {
    test('1. calculateItemValue & calculateTotalItemValue verified manually', () {
      // itemGold: 10 * (91.6 / 100) * 6000 = 54960.0
      expect(calculateItemValue(itemGold), closeTo(54960.0, 0.001));

      // itemSilver: 100 * (99.9 / 100) * 80 = 7992.0
      expect(calculateItemValue(itemSilver), closeTo(7992.0, 0.001));

      // Total across both: 54960 + 7992 = 62952.0
      expect(calculateTotalItemValue([itemGold, itemSilver]), closeTo(62952.0, 0.001));

      // Item with explicit itemValue override uses stored snapshot
      const itemExplicit = LedgerItem(
        id: 'i-exp',
        recordId: 'r-1',
        name: 'Diamond Watch',
        itemCategory: 'GOLD_18K',
        itemValue: 75000.0,
      );
      expect(calculateItemValue(itemExplicit), 75000.0);
    });

    test('2. getMonthsBetween two-branch half-month rounding manually verified', () {
      // Same date -> 0.0
      expect(getMonthsBetween(DateTime(2026, 1, 1), DateTime(2026, 1, 1)), 0.0);

      // Branch 1: endDay >= startDay (15 days -> +0.5 month)
      expect(getMonthsBetween(DateTime(2026, 1, 1), DateTime(2026, 1, 16)), 0.5);

      // Branch 1: endDay >= startDay (16 days -> +1.0 month)
      expect(getMonthsBetween(DateTime(2026, 1, 1), DateTime(2026, 1, 17)), 1.0);

      // Branch 2: endDay < startDay (month rollover)
      // Jan 31 -> Feb 28: decrement to 0. Days in Jan=31. 31 - 31 + 28 = 28 (>15) -> 1.0 month
      expect(getMonthsBetween(DateTime(2026, 1, 31), DateTime(2026, 2, 28)), 1.0);

      // End before start returns 0.0 floor
      expect(getMonthsBetween(DateTime(2026, 6, 1), DateTime(2026, 1, 1)), 0.0);
    });

    test('3. calculateInterestForPeriod simple interest formula verified', () {
      // 20,000 at 2% for 5.0 months = (20000 * 2 * 5) / 100 = 2000.0
      final interest = calculateInterestForPeriod(20000.0, 2.0, DateTime(2026, 1, 1), DateTime(2026, 6, 1));
      expect(interest, 2000.0);
    });

    test('4. allocatePayment interest-first rule verified', () {
      // Outstanding interest = 500
      // Payment 300 (<500) -> 300 interest, 0 principal
      final alloc1 = allocatePayment(300.0, 500.0);
      expect(alloc1.interestPaid, 300.0);
      expect(alloc1.principalPaid, 0.0);

      // Payment 800 (>500) -> 500 interest, 300 principal
      final alloc2 = allocatePayment(800.0, 500.0);
      expect(alloc2.interestPaid, 500.0);
      expect(alloc2.principalPaid, 300.0);

      // Zero outstanding interest -> 100% principal
      final alloc3 = allocatePayment(400.0, 0.0);
      expect(alloc3.interestPaid, 0.0);
      expect(alloc3.principalPaid, 400.0);
    });

    test('5. getDashboard aggregates match exact manual figures', () {
      final dashboard = getDashboard(allRecords, testToday);

      // GIVEN: recGivenActive1 (20k principal, 2k interest, 20.2k due) +
      //        recGivenActive2 (10k principal, 300 interest, 10.3k due)
      // Note: recSettled is excluded because it is SETTLED.
      expect(dashboard.totalPrincipalGiven, 30000.0);
      expect(dashboard.totalInterestAccruedGiven, 2300.0);
      expect(dashboard.totalDueGiven, 30500.0);

      // TAKEN: recTakenActive (15k principal, 600 interest, 15.6k due)
      expect(dashboard.totalPrincipalTaken, 15000.0);
      expect(dashboard.totalInterestAccruedTaken, 600.0);
      expect(dashboard.totalDueTaken, 15600.0);
    });

    test('6. getCustomerReport aggregates match per-customer figures', () {
      final reports = getCustomerReport(allCustomers, allRecords, testToday);
      expect(reports.length, 3);

      // Customer 1: recGivenActive1 (recTakenActive excluded from customer lending overview)
      final rep1 = reports.firstWhere((r) => r.customer.id == 'c-1');
      expect(rep1.activeRecordCount, 1);
      expect(rep1.totalPrincipal, 20000.0);
      expect(rep1.totalInterestAccrued, 2000.0);
      expect(rep1.totalDue, 20200.0);

      // Customer 2: recGivenActive2 (recSettled excluded from active)
      final rep2 = reports.firstWhere((r) => r.customer.id == 'c-2');
      expect(rep2.activeRecordCount, 1);
      expect(rep2.totalPrincipal, 10000.0);
      expect(rep2.totalInterestAccrued, 300.0);
      expect(rep2.totalDue, 10300.0);

      // Customer 3: No records -> All zeroes
      final rep3 = reports.firstWhere((r) => r.customer.id == 'c-3');
      expect(rep3.activeRecordCount, 0);
      expect(rep3.totalPrincipal, 0.0);
      expect(rep3.totalInterestAccrued, 0.0);
      expect(rep3.totalDue, 0.0);
    });

    test('7. getOverdue detects inactive records with threshold verification', () {
      // Activity dates:
      // recGivenActive1 latest payment is 2026-03-01. Days from 2026-03-01 to 2026-06-01 = 92 days (>30) -> OVERDUE
      // recGivenActive2 has no payments -> uses startDate 2026-03-01. Days to 2026-06-01 = 92 days (>30) -> OVERDUE
      final latestPaymentDates = <String, DateTime?>{
        'rec-given-1': DateTime(2026, 3, 1),
        'rec-given-2': null,
      };

      final overdue = getOverdue(allRecords, latestPaymentDates, testToday, thresholdDays: 30);
      // Both active given records are overdue
      expect(overdue.length, 3); // recGivenActive1, recGivenActive2, recTakenActive (start 2026-02-01 = 120 days)
      expect(overdue.first.daysSinceActivity, 120); // recTakenActive is most inactive
    });

    test('8. computeCollectionAlerts & computeCollectionAlertCards evaluations', () {
      final rates = [
        ItemRate(
          id: 'r-1',
          itemCategory: 'GOLD_22K',
          ratePerUnit: 6200.0,
          effectiveDate: DateTime(2026, 6, 1),
          updatedAt: DateTime(2026, 6, 1),
        ),
        ItemRate(
          id: 'r-2',
          itemCategory: 'SILVER',
          ratePerUnit: 85.0,
          effectiveDate: DateTime(2026, 6, 1),
          updatedAt: DateTime(2026, 6, 1),
        ),
      ];

      final totalPaidMap = {
        'rec-given-1': 1800.0,
        'rec-given-2': 0.0,
      };

      final alerts = computeCollectionAlerts(allRecords, rates, totalPaidMap, testToday);
      expect(alerts, isNotNull);

      final cards = computeCollectionAlertCards(allRecords, rates, totalPaidMap, testToday);
      expect(cards.length, 2); // 2 active given records
      expect(cards.any((c) => c.record.id == 'rec-given-1'), isTrue);
      expect(cards.any((c) => c.record.id == 'rec-given-2'), isTrue);
    });
  });

  // ===========================================================================
  // calculateRecordFinancials COMPLEX TEST MATRIX (§5.5)
  // ===========================================================================
  group('5.5 calculateRecordFinancials Complex Matrix', () {
    test('Zero payments: full principal and interest remain outstanding', () {
      final record = LedgerRecord(
        id: 'rec-zero-pay',
        transactionId: 'TXN-001',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        payments: const [],
      );

      // Target: 3 months later (2026-04-01) -> Total interest = 600
      final fin = calculateRecordFinancials(record, DateTime(2026, 4, 1));
      expect(fin.principal, 10000.0);
      expect(fin.totalPaid, 0.0);
      expect(fin.interestPaid, 0.0);
      expect(fin.principalPaid, 0.0);
      expect(fin.totalInterest, 600.0);
      expect(fin.outstandingInterest, 600.0);
      expect(fin.outstandingPrincipal, 10000.0);
      expect(fin.totalDue, 10600.0);
      expect(fin.months, 3.0);
    });

    test('Partial payments: interest-first allocation reduces interest before principal', () {
      final record = LedgerRecord(
        id: 'rec-part-pay',
        transactionId: 'TXN-002',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        payments: [
          Payment(
            id: 'p-1',
            recordId: 'rec-part-pay',
            amount: 300.0,
            date: DateTime(2026, 2, 1),
            interestPaid: 300.0,
            principalPaid: 0.0,
          ),
        ],
      );

      // Target: 2 months later (2026-03-01) -> Total interest = 400
      final fin = calculateRecordFinancials(record, DateTime(2026, 3, 1));
      expect(fin.totalInterest, 400.0);
      expect(fin.interestPaid, 300.0);
      expect(fin.principalPaid, 0.0);
      expect(fin.totalPaid, 300.0);
      expect(fin.outstandingInterest, 100.0); // 400 - 300
      expect(fin.outstandingPrincipal, 10000.0);
      expect(fin.totalDue, 10100.0);
    });

    test('Overpayments: balances are floored at 0.0 without negative dues', () {
      final record = LedgerRecord(
        id: 'rec-overpay',
        transactionId: 'TXN-003',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 5000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        payments: [
          Payment(
            id: 'p-over',
            recordId: 'rec-overpay',
            amount: 6000.0, // Overpayment
            date: DateTime(2026, 2, 1),
            interestPaid: 200.0,
            principalPaid: 5800.0, // Exceeds principal
          ),
        ],
      );

      final fin = calculateRecordFinancials(record, DateTime(2026, 2, 1));
      expect(fin.totalPaid, 6000.0);
      expect(fin.outstandingInterest, 0.0);
      expect(fin.outstandingPrincipal, 0.0); // Floored at 0
      expect(fin.totalDue, 0.0); // Floored at 0
    });

    test('Settled record with calculatedInterest populated returns snapshotted fast-path', () {
      final settled = LedgerRecord(
        id: 'rec-settled-fast',
        transactionId: 'TXN-004',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        settledDate: DateTime(2026, 3, 1),
        status: RecordStatus.SETTLED,
        principalAmount: 10000.0,
        interestRate: 2.0,
        calculatedInterest: 350.0, // Snapshotted custom rate/waiver
        payments: [
          Payment(
            id: 'p-set',
            recordId: 'rec-settled-fast',
            amount: 10350.0,
            date: DateTime(2026, 3, 1),
            interestPaid: 350.0,
            principalPaid: 10000.0,
          ),
        ],
      );

      // Target is today in September: Must NOT recalculate!
      final fin = calculateRecordFinancials(settled, DateTime(2026, 9, 1));
      expect(fin.totalInterest, 350.0); // Retains snapshot
      expect(fin.totalDue, 0.0);
      expect(fin.outstandingInterest, 0.0);
      expect(fin.outstandingPrincipal, 0.0);
      expect(fin.months, 2.0); // Months up to settledDate
    });

    test('Settled record with calculatedInterest null must use settledDate (never DateTime.now())', () {
      final settledLegacy = LedgerRecord(
        id: 'rec-settled-legacy',
        transactionId: 'TXN-005',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        settledDate: DateTime(2026, 4, 1), // 3 months
        status: RecordStatus.SETTLED,
        principalAmount: 10000.0,
        interestRate: 2.0,
        calculatedInterest: null, // Legacy import
        payments: [
          Payment(
            id: 'p-legacy',
            recordId: 'rec-settled-legacy',
            amount: 10600.0,
            date: DateTime(2026, 4, 1),
            interestPaid: 600.0,
            principalPaid: 10000.0,
          ),
        ],
      );

      // Target is December 2026: MUST use settledDate (2026-04-01) -> 3 months = 600 interest
      final fin = calculateRecordFinancials(settledLegacy, DateTime(2026, 12, 1));
      expect(fin.totalInterest, 600.0);
      expect(fin.months, 3.0);
      expect(fin.totalDue, 0.0);
      expect(fin.outstandingInterest, 0.0);
      expect(fin.outstandingPrincipal, 0.0);
    });

    test('Settled record with BOTH calculatedInterest and settledDate null returns zeroed snapshot fallback', () {
      final settledCorrupt = LedgerRecord(
        id: 'rec-settled-corrupt',
        transactionId: 'TXN-006',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        settledDate: null,
        status: RecordStatus.SETTLED,
        principalAmount: 10000.0,
        interestRate: 2.0,
        calculatedInterest: null,
        payments: const [],
      );

      final fin = calculateRecordFinancials(settledCorrupt, DateTime(2026, 12, 1));
      expect(fin.totalInterest, 0.0);
      expect(fin.outstandingInterest, 0.0);
      expect(fin.months, 0.0);
      expect(fin.outstandingPrincipal, 10000.0);
      expect(fin.totalDue, 10000.0);
    });

    test('Record with multiple collateral items calculates valuation correctly', () {
      const item1 = LedgerItem(
        id: 'it-1',
        recordId: 'rec-multi',
        name: 'Gold Ring',
        itemCategory: 'GOLD_22K',
        weight: 5.0,
        purity: 91.6,
        rate: 6000.0, // 5 * 0.916 * 6000 = 27,480.0
      );

      const item2 = LedgerItem(
        id: 'it-2',
        recordId: 'rec-multi',
        name: 'Silver Bar',
        itemCategory: 'SILVER',
        weight: 200.0,
        purity: 99.9,
        rate: 80.0, // 200 * 0.999 * 80 = 15,984.0
      );

      const item3 = LedgerItem(
        id: 'it-3',
        recordId: 'rec-multi',
        name: 'Diamond Pendant',
        itemCategory: 'DIAMOND',
        itemValue: 50000.0, // Explicit snapshot
      );

      final record = LedgerRecord(
        id: 'rec-multi',
        transactionId: 'TXN-007',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 50000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: [item1, item2, item3],
      );

      // Total collateral valuation: 27480 + 15984 + 50000 = 93464.0
      expect(calculateTotalItemValue(record.items), closeTo(93464.0, 0.001));

      // Financials remain independent of item valuation: 50,000 at 2% for 2 months = 2,000
      final fin = calculateRecordFinancials(record, DateTime(2026, 3, 1));
      expect(fin.principal, 50000.0);
      expect(fin.totalInterest, 2000.0);
      expect(fin.totalDue, 52000.0);
    });
  });

  // ===========================================================================
  // getMonthlyInterest CASH-BASIS VERIFICATION (§5.5)
  // ===========================================================================
  group('5.5 getMonthlyInterest Cash-Basis Rule', () {
    test('Record active for 12 months with NO payments contributes ZERO to monthly totals', () {
      final activeLongTermNoPayments = LedgerRecord(
        id: 'rec-no-pay-12m',
        transactionId: 'TXN-008',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2025, 1, 1), // Active for over a year
        principalAmount: 50000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        payments: const [], // Zero payments!
      );

      final monthly = getMonthlyInterest([activeLongTermNoPayments]);
      // CASH BASIS: Zero payments must produce an empty list (contributes ZERO to all months)
      expect(monthly, isEmpty);
    });

    test('Cash-basis only counts payments where interestPaid > 0 and groups by calendar month', () {
      final recWithMixedPayments = LedgerRecord(
        id: 'rec-mixed-pay',
        transactionId: 'TXN-009',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 20000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        payments: [
          // Feb payment 1: interest = 200
          Payment(
            id: 'p-feb-1',
            recordId: 'rec-mixed-pay',
            amount: 200.0,
            date: DateTime(2026, 2, 5),
            interestPaid: 200.0,
            principalPaid: 0.0,
          ),
          // Feb payment 2: interest = 150
          Payment(
            id: 'p-feb-2',
            recordId: 'rec-mixed-pay',
            amount: 150.0,
            date: DateTime(2026, 2, 20),
            interestPaid: 150.0,
            principalPaid: 0.0,
          ),
          // March payment: principal-only (interestPaid = 0) -> Should NOT appear
          Payment(
            id: 'p-mar-prin',
            recordId: 'rec-mixed-pay',
            amount: 1000.0,
            date: DateTime(2026, 3, 10),
            interestPaid: 0.0,
            principalPaid: 1000.0,
          ),
          // April payment: interest = 400
          Payment(
            id: 'p-apr-1',
            recordId: 'rec-mixed-pay',
            amount: 400.0,
            date: DateTime(2026, 4, 15),
            interestPaid: 400.0,
            principalPaid: 0.0,
          ),
        ],
      );

      final recZeroPay = LedgerRecord(
        id: 'rec-zero-pay-coexist',
        transactionId: 'TXN-010',
        type: RecordType.GIVEN,
        customerId: 'c-2',
        startDate: DateTime(2025, 6, 1),
        principalAmount: 100000.0,
        interestRate: 3.0,
        status: RecordStatus.ACTIVE,
        payments: const [], // Zero payments
      );

      final monthly = getMonthlyInterest([recWithMixedPayments, recZeroPay]);

      // Only Feb 2026 and April 2026 should exist (March had 0 interestPaid, recZeroPay had 0 payments)
      expect(monthly.length, 2);

      expect(monthly[0].year, 2026);
      expect(monthly[0].month, 2);
      expect(monthly[0].interestReceived, 350.0); // 200 + 150

      expect(monthly[1].year, 2026);
      expect(monthly[1].month, 4);
      expect(monthly[1].interestReceived, 400.0);
    });
  });

  // ===========================================================================
  // [FIX-ARCH-PDFTEST-1] AUTOMATED ASSERTION TEST: getDashboard() vs generateAllCustomersReport()
  // ===========================================================================
  group('[FIX-ARCH-PDFTEST-1] Automated Drift Assertion Test', () {
    test('getDashboard() and generateAllCustomersReport() monetary totals match exactly', () async {
      // 1. Run getDashboard on canonical test dataset
      final dashboard = getDashboard(allRecords, testToday);

      // 2. Run generateAllCustomersReport on identical dataset
      final report = generateAllCustomersReport(allCustomers, allRecords, testToday);

      // 3. Exact monetary assertions preventing UI / PDF drift
      expect(
        report.totalPrincipal,
        equals(dashboard.totalPrincipalGiven),
        reason: 'Total Principal in PDF Report must match Dashboard totalPrincipalGiven',
      );

      expect(
        report.totalInterestAccrued,
        equals(dashboard.totalInterestAccruedGiven),
        reason: 'Total Accrued Interest in PDF Report must match Dashboard totalInterestAccruedGiven',
      );

      expect(
        report.totalDue,
        equals(dashboard.totalDueGiven),
        reason: 'Total Due in PDF Report must match Dashboard totalDueGiven',
      );

      // Active records count assertion
      final expectedActiveGivenCount = allRecords.where((r) => r.isActive && r.isGiven).length;
      expect(report.totalActiveRecords, equals(expectedActiveGivenCount));

      // 4. Offline PDF Generation assertion: buildPdf() generates valid non-empty PDF bytes
      final pdfBytes = await report.buildPdf();
      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(500));

      // Assert standard PDF signature "%PDF" (ASCII 0x25, 0x50, 0x44, 0x46)
      expect(pdfBytes[0], 0x25); // '%'
      expect(pdfBytes[1], 0x50); // 'P'
      expect(pdfBytes[2], 0x44); // 'D'
      expect(pdfBytes[3], 0x46); // 'F'
    });
  });
}
