import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/calculations/calculations.dart';
import 'package:money_lending/data/data.dart';
import 'package:money_lending/domain/domain.dart';

void main() {
  group('Business Logic Calculations (§5.1)', () {
    test('calculateItemValue computes collateral and lendable snapshot', () {
      const item = LedgerItem(
        id: 'item-1',
        recordId: 'rec-1',
        name: 'Gold Chain',
        itemCategory: 'GOLD_22K',
        weight: 10.0,
        purity: 91.6, // 91.6%
        rate: 6000.0,
        lendPercentage: 80.0,
      );

      final val = calculateItemValue(item);
      // 10.0 * 0.916 * 6000.0 = 54960.0
      expect(val, closeTo(54960.0, 0.001));

      final items = [
        item,
        const LedgerItem(
          id: 'item-2',
          recordId: 'rec-1',
          name: 'Silver Coin',
          itemCategory: 'SILVER',
          weight: 100.0,
          purity: 99.9,
          rate: 80.0,
        ),
      ];
      // 54960 + (100 * 0.999 * 80 = 7992) = 62952.0
      expect(calculateTotalItemValue(items), closeTo(62952.0, 0.001));
    });

    test('getMonthsBetween computes two-branch half-month rounding accurately', () {
      // 1. Exact whole months: 10 April 2026 to 10 June 2026 -> 2.0 months
      expect(
        getMonthsBetween(DateTime(2026, 4, 10), DateTime(2026, 6, 10)),
        2.0,
      );

      // 2. Branch 1: 1 to 15 days -> +0.5 month
      // 10 April 2026 to 22 April 2026 = 12 days -> 0.5 month
      expect(
        getMonthsBetween(DateTime(2026, 4, 10), DateTime(2026, 4, 22)),
        0.5,
      );

      // 10 April 2026 to 25 April 2026 = 15 days -> 0.5 month
      expect(
        getMonthsBetween(DateTime(2026, 4, 10), DateTime(2026, 4, 25)),
        0.5,
      );

      // 3. Branch 2: > 15 days -> +1.0 month
      // 10 April 2026 to 26 April 2026 = 16 days -> 1.0 month
      expect(
        getMonthsBetween(DateTime(2026, 4, 10), DateTime(2026, 4, 26)),
        1.0,
      );

      // 4. Whole month + half month: 10 April 2026 to 20 May 2026 = 1 month + 10 days -> 1.5 months
      expect(
        getMonthsBetween(DateTime(2026, 4, 10), DateTime(2026, 5, 20)),
        1.5,
      );

      // 5. Whole month + full month: 10 April 2026 to 28 May 2026 = 1 month + 18 days -> 2.0 months
      expect(
        getMonthsBetween(DateTime(2026, 4, 10), DateTime(2026, 5, 28)),
        2.0,
      );

      // 6. Zero days difference -> 0.0
      expect(
        getMonthsBetween(DateTime(2026, 4, 10), DateTime(2026, 4, 10)),
        0.0,
      );
    });

    test('calculateInterestForPeriod computes simple monthly interest', () {
      // 10,000 at 2% for 2 months = 400
      final interest = calculateInterestForPeriod(
        principal: 10000.0,
        rate: 2.0,
        start: DateTime(2026, 4, 10),
        end: DateTime(2026, 6, 10),
      );
      expect(interest, 400.0);
    });

    test('calculateRecordFinancials handles settled fast-path (§5.2.1)', () {
      final settledRecord = LedgerRecord(
        id: 'rec-settled',
        transactionId: 'TXN-000010',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        status: RecordStatus.SETTLED,
        settledDate: DateTime(2026, 3, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        calculatedInterest: 400.0, // snapshotted at settle time
        payments: [
          Payment(
            id: 'p-1',
            recordId: 'rec-settled',
            amount: 10400.0,
            date: DateTime(2026, 3, 1),
            notes: 'Settled in full',
            interestPaid: 400.0,
            principalPaid: 10000.0,
          ),
        ],
      );

      final financials = calculateRecordFinancials(settledRecord, DateTime(2026, 9, 10));
      expect(financials.principal, 10000.0);
      expect(financials.totalInterest, 400.0);
      expect(financials.totalPaid, 10400.0);
      expect(financials.remainingPrincipal, 0.0);
      expect(financials.remainingInterest, 0.0);
      expect(financials.totalDue, 0.0);
      expect(financials.months, 2.0);
    });

    test('calculateRecordFinancials computes active record with partial payment', () {
      final activeRecord = LedgerRecord(
        id: 'rec-active',
        transactionId: 'TXN-000011',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        status: RecordStatus.ACTIVE,
        principalAmount: 10000.0,
        interestRate: 2.0,
        payments: [
          Payment(
            id: 'p-part',
            recordId: 'rec-active',
            amount: 200.0,
            date: DateTime(2026, 2, 1),
            notes: 'Interest payment',
            interestPaid: 200.0,
            principalPaid: 0.0,
          ),
        ],
      );

      // Target: 2 months later (1 March 2026) -> Total interest = 400
      final fin = calculateRecordFinancials(activeRecord, DateTime(2026, 3, 1));
      expect(fin.principal, 10000.0);
      expect(fin.totalInterest, 400.0);
      expect(fin.totalPaid, 200.0);
      expect(fin.remainingInterest, 200.0); // 400 - 200
      expect(fin.remainingPrincipal, 10000.0);
      expect(fin.totalDue, 10200.0); // 10000 principal + 200 interest
    });

    test('getDashboard aggregates GIVEN and TAKEN summary cards with targetDate future guard', () {
      final records = [
        LedgerRecord(
          id: 'rec-g1',
          transactionId: 'TXN-000001',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 1, 1),
          principalAmount: 20000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
        ),
        LedgerRecord(
          id: 'rec-t1',
          transactionId: 'TXN-000002',
          type: RecordType.TAKEN,
          customerId: 'c-2',
          startDate: DateTime(2026, 1, 1),
          principalAmount: 10000.0,
          interestRate: 1.5,
          status: RecordStatus.ACTIVE,
        ),
      ];

      // 2 months later (1 March 2026)
      final stats = getDashboard(records, today: DateTime(2026, 3, 1));

      expect(stats.totalPrincipalGiven, 20000.0);
      expect(stats.totalInterestAccruedGiven, 800.0); // 20000 * 2% * 2m = 800
      expect(stats.totalDueGiven, 20800.0);

      expect(stats.totalPrincipalTaken, 10000.0);
      expect(stats.totalInterestAccruedTaken, 300.0); // 10000 * 1.5% * 2m = 300
      expect(stats.totalDueTaken, 10300.0);
    });

    test('getMonthlyInterest produces cash-basis earnings grouped by YearMonth', () {
      final records = [
        LedgerRecord(
          id: 'rec-1',
          transactionId: 'TXN-000001',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 1, 1),
          principalAmount: 10000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          payments: [
            Payment(
              id: 'p-1',
              recordId: 'rec-1',
              amount: 200.0,
              date: DateTime(2026, 2, 15, 10, 30),
              interestPaid: 200.0,
              principalPaid: 0.0,
            ),
            Payment(
              id: 'p-2',
              recordId: 'rec-1',
              amount: 300.0,
              date: DateTime(2026, 2, 28, 16, 00),
              interestPaid: 300.0,
              principalPaid: 0.0,
            ),
            Payment(
              id: 'p-3',
              recordId: 'rec-1',
              amount: 250.0,
              date: DateTime(2026, 3, 10, 11, 00),
              interestPaid: 250.0,
              principalPaid: 0.0,
            ),
          ],
        ),
      ];

      final monthly = getMonthlyInterest(records);
      expect(monthly.length, 2);

      expect(monthly.first.year, 2026);
      expect(monthly.first.monthNumber, 2);
      expect(monthly.first.interestReceived, 500.0); // 200 + 300 in Feb

      expect(monthly.last.year, 2026);
      expect(monthly.last.monthNumber, 3);
      expect(monthly.last.interestReceived, 250.0); // 250 in Mar
    });

    test('getOverdue identifies records exceeding activity threshold', () {
      final today = DateTime(2026, 4, 1);

      final recActiveOld = LedgerRecord(
        id: 'rec-overdue',
        transactionId: 'TXN-000001',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1), // 90 days ago
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      final recActiveRecent = LedgerRecord(
        id: 'rec-recent',
        transactionId: 'TXN-000002',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 3, 25), // 7 days ago
        principalAmount: 5000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      // Latest payment map: rec-overdue has no payments (null), rec-recent has no payments (null)
      final latestPaymentDates = <String, DateTime?>{
        'rec-overdue': null,
        'rec-recent': null,
      };

      final overdue = getOverdue(
        records: [recActiveOld, recActiveRecent],
        latestPaymentDates: latestPaymentDates,
        today: today,
        thresholdDays: 30,
      );

      expect(overdue.length, 1);
      expect(overdue.first.record.id, 'rec-overdue');
      expect(overdue.first.daysSinceActivity, 90);
    });

    test('[FIX-PERF-EAGERLOAD-1] RecordRepositoryImpl toSummaryRecord and toFullRecord work as specified', () {
      final repo = RecordRepositoryImpl();

      const entity = RecordEntity(
        id: 'rec-perf-1',
        transactionId: 'TXN-000099',
        type: 'GIVEN',
        customerId: 'c-1',
        startDate: '2026-04-01T10:00:00',
        principalAmount: 50000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
      );

      // 1. toSummaryRecord must return empty lists for items and payments
      final summaryRecord = repo.toSummaryRecord(entity);
      expect(summaryRecord.items, isEmpty);
      expect(summaryRecord.payments, isEmpty);
      expect(summaryRecord.id, 'rec-perf-1');
      expect(summaryRecord.principalAmount, 50000.0);

      // 2. toFullRecord must return eager-loaded lists
      const itemEntity = LedgerItemEntity(
        id: 'item-perf-1',
        recordId: 'rec-perf-1',
        name: 'Diamond Ring',
        itemCategory: 'DIAMOND',
      );

      const paymentEntity = PaymentEntity(
        id: 'pay-perf-1',
        recordId: 'rec-perf-1',
        amount: 1000.0,
        date: '2026-04-15T12:00:00',
        interestPaid: 1000.0,
        principalPaid: 0.0,
      );

      final fullRecord = repo.toFullRecord(entity, [itemEntity], [paymentEntity]);
      expect(fullRecord.items.length, 1);
      expect(fullRecord.items.first.name, 'Diamond Ring');
      expect(fullRecord.payments.length, 1);
      expect(fullRecord.payments.first.amount, 1000.0);
    });

    test('§5.1 LedgerItem fineWeight and sourceItemId verification', () {
      const item = LedgerItem(
        id: 'item-1',
        recordId: 'rec-1',
        name: 'Gold Ring',
        itemCategory: 'GOLD',
        weight: 10.0,
        purity: 91.6, // 22k
        rate: 6000.0,
        itemValue: 54960.0,
        lendPercentage: 75.0,
        lendableAmount: 41220.0,
        sourceItemId: 'src-item-99',
      );

      // fineWeight = weight * (purity / 100) = 10.0 * 0.916 = 9.16
      expect(item.fineWeight, closeTo(9.16, 0.001));
      expect(item.sourceItemId, 'src-item-99');
    });

    test('§5.1 computeCollateralOverdue and mergeOverdueRecords [FIX-OVERDUECOLLATERAL-1]', () {
      final today = DateTime(2026, 6, 1);

      // GIVEN record where collateral has dropped below current totalDue
      final recGivenBreached = LedgerRecord(
        id: 'rec-breached-1',
        transactionId: 'TXN-G-01',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 50000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'item-b1',
            recordId: 'rec-breached-1',
            name: 'Gold Chain',
            itemCategory: 'GOLD',
            weight: 10.0,
            purity: 100.0,
            rate: 6000.0,
            itemValue: 60000.0,
            lendPercentage: 80.0,
            lendableAmount: 48000.0,
          ),
        ],
      );

      // TAKEN record where collateral is safe now but breaches in 2 months
      final recTakenProjected = LedgerRecord(
        id: 'rec-proj-1',
        transactionId: 'TXN-T-01',
        type: RecordType.TAKEN,
        customerId: 'c-2',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 40000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'item-p1',
            recordId: 'rec-proj-1',
            name: 'Silver Bar',
            itemCategory: 'SILVER',
            weight: 500.0,
            purity: 100.0,
            rate: 100.0,
            itemValue: 50000.0,
            lendPercentage: 80.0,
            lendableAmount: 40000.0,
          ),
        ],
      );

      // Current live rates: Gold has dropped to 4000/g (item worth 40k, but totalDue is 50k + 5k = 55k -> breached!)
      // Silver is 90/g (item worth 45k. Current obligation = 40k + 4k = 44k -> safe now. But in 2m obligation = 45.6k -> projected breach!)
      final liveRates = [
        ItemRate(
          id: 'rate-1',
          itemCategory: 'GOLD',
          ratePerUnit: 4000.0,
          effectiveDate: today,
          updatedAt: today,
        ),
        ItemRate(
          id: 'rate-2',
          itemCategory: 'SILVER',
          ratePerUnit: 90.0,
          effectiveDate: today,
          updatedAt: today,
        ),
      ];

      final collateralOverdue = computeCollateralOverdue(
        records: [recGivenBreached, recTakenProjected],
        rates: liveRates,
        today: today,
      );

      expect(collateralOverdue.length, 2);

      final breachedRecord = collateralOverdue.firstWhere((o) => o.record.id == 'rec-breached-1');
      expect(breachedRecord.reasons.contains(OverdueReason.collateralBreachedNow), isTrue);
      expect(breachedRecord.reasons.contains(OverdueReason.collateralProjected2Months), isTrue);
      expect(breachedRecord.currentCollateralValue, 40000.0);

      final projectedRecord = collateralOverdue.firstWhere((o) => o.record.id == 'rec-proj-1');
      expect(projectedRecord.reasons.contains(OverdueReason.collateralBreachedNow), isFalse);
      expect(projectedRecord.reasons.contains(OverdueReason.collateralProjected2Months), isTrue);

      // Now test mergeOverdueRecords composition with activity-based overdue
      final activityOverdue = [
        OverdueRecord(
          record: recGivenBreached,
          reasons: const {OverdueReason.noActivity},
          daysSinceActivity: 152,
          lastActivityDate: DateTime(2026, 1, 1),
        ),
      ];

      final merged = mergeOverdueRecords(activityOverdue, collateralOverdue);
      expect(merged.length, 2);

      final mergedBreached = merged.firstWhere((m) => m.record.id == 'rec-breached-1');
      // Reasons must be unioned!
      expect(mergedBreached.reasons.contains(OverdueReason.noActivity), isTrue);
      expect(mergedBreached.reasons.contains(OverdueReason.collateralBreachedNow), isTrue);
      expect(mergedBreached.reasons.contains(OverdueReason.collateralProjected2Months), isTrue);
      expect(mergedBreached.daysSinceActivity, 152);
      expect(mergedBreached.currentCollateralValue, 40000.0);
    });

    test('Payment.withSplit returns new Payment with recalculated split ([FIX-REPLAY-1])', () {
      final p = Payment(
        id: 'p-1',
        paymentId: 'PAY092601',
        recordId: 'rec-1',
        amount: 1500.0,
        date: DateTime(2026, 9, 15, 14, 30),
        notes: 'Partial payment',
        interestPaid: 500.0,
        principalPaid: 1000.0,
      );

      final updated = p.withSplit(400.0, 1100.0);
      expect(updated.id, 'p-1');
      expect(updated.paymentId, 'PAY092601');
      expect(updated.recordId, 'rec-1');
      expect(updated.amount, 1500.0);
      expect(updated.date, DateTime(2026, 9, 15, 14, 30));
      expect(updated.notes, 'Partial payment');
      expect(updated.interestPaid, 400.0);
      expect(updated.principalPaid, 1100.0);
    });

    test('lastActivityDate derives from payments or startDate ([FIX-LASTACTIVITY-1])', () {
      final recNoPayments = LedgerRecord(
        id: 'r-no-pay',
        transactionId: 'TRAN092601',
        customerId: 'c-1',
        type: RecordType.given,
        status: RecordStatus.active,
        startDate: DateTime(2026, 1, 15, 10, 30),
        principalAmount: 10000.0,
        interestRate: 2.0,
        payments: const [],
      );
      expect(lastActivityDate(recNoPayments), DateTime(2026, 1, 15));

      final recWithPayments = LedgerRecord(
        id: 'r-with-pay',
        transactionId: 'TRAN092602',
        customerId: 'c-1',
        type: RecordType.given,
        status: RecordStatus.active,
        startDate: DateTime(2026, 1, 15, 10, 30),
        principalAmount: 10000.0,
        interestRate: 2.0,
        payments: [
          Payment(
            id: 'p-1',
            paymentId: 'PAY092601',
            recordId: 'r-with-pay',
            amount: 500.0,
            date: DateTime(2026, 2, 20, 11, 0),
            notes: '',
            interestPaid: 200.0,
            principalPaid: 300.0,
          ),
          Payment(
            id: 'p-2',
            paymentId: 'PAY092602',
            recordId: 'r-with-pay',
            amount: 800.0,
            date: DateTime(2026, 4, 10, 15, 45),
            notes: '',
            interestPaid: 200.0,
            principalPaid: 600.0,
          ),
        ],
      );
      expect(lastActivityDate(recWithPayments), DateTime(2026, 4, 10));
    });

    test('getOverdue works directly without latestPaymentDates map ([FIX-LASTACTIVITY-1])', () {
      final today = DateTime(2026, 6, 1);
      final activeRecOverdue = LedgerRecord(
        id: 'r-overdue',
        transactionId: 'TRAN092603',
        customerId: 'c-1',
        type: RecordType.given,
        status: RecordStatus.active,
        startDate: DateTime(2026, 1, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        payments: [
          Payment(
            id: 'p-old',
            paymentId: 'PAY092603',
            recordId: 'r-overdue',
            amount: 400.0,
            date: DateTime(2026, 3, 1),
            notes: '',
            interestPaid: 400.0,
            principalPaid: 0.0,
          ),
        ],
      );

      final activeRecRecent = LedgerRecord(
        id: 'r-recent',
        transactionId: 'TRAN092604',
        customerId: 'c-1',
        type: RecordType.given,
        status: RecordStatus.active,
        startDate: DateTime(2026, 1, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        payments: [
          Payment(
            id: 'p-new',
            paymentId: 'PAY092604',
            recordId: 'r-recent',
            amount: 400.0,
            date: DateTime(2026, 5, 20),
            notes: '',
            interestPaid: 400.0,
            principalPaid: 0.0,
          ),
        ],
      );

      // Calling getOverdue without latestPaymentDates map:
      final overdueList = getOverdue(
        records: [activeRecOverdue, activeRecRecent],
        today: today,
        thresholdDays: 30,
      );

      expect(overdueList.length, 1);
      expect(overdueList.first.record.id, 'r-overdue');
      expect(overdueList.first.lastActivityDate, DateTime(2026, 3, 1));
      expect(overdueList.first.daysSinceActivity, 92); // March 1 to June 1 = 92 days
    });

    test('liveItemValue computes roundMoney(fineWeight * rate) ([FIX-MONEY-1] & Addendum J.1)', () {
      const item = LedgerItem(
        id: 'it-1',
        recordId: 'r-1',
        name: 'Gold Ring',
        itemCategory: 'GOLD',
        weight: 12.345,
        purity: 91.6, // 22K
        rate: 6500.0,
        itemValue: 73500.0,
        lendPercentage: 80.0,
        lendableAmount: 58800.0,
      );

      // fineWeight = 12.345 * (91.6 / 100) = 11.30802
      // liveItemValue at 7000/g = roundMoney(11.30802 * 7000) = roundMoney(79156.14) = 79156.14
      final liveVal = liveItemValue(item, 7000.0);
      expect(liveVal, 79156.14);
    });

    test('reallocatePayments replays payments oldest-first and recalculates splits ([FIX-REPLAY-1] & J.2)', () {
      // Loan of 10,000 at 2%/month started on 1 Jan 2026
      // Payment 1 on 1 March 2026 (2 months interest = 400): pays 500 -> interest 400, principal 100
      // Payment 2 on 1 May 2026 (4 months total interest = 800, previously paid 400 -> outstanding 400): pays 1000 -> interest 400, principal 600
      final rec = LedgerRecord(
        id: 'rec-replay',
        transactionId: 'TRAN092605',
        customerId: 'c-1',
        type: RecordType.given,
        status: RecordStatus.active,
        startDate: DateTime(2026, 1, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        // Payments initially entered with inaccurate or legacy splits:
        payments: [
          Payment(
            id: 'p-2',
            paymentId: 'PAY092606',
            recordId: 'rec-replay',
            amount: 1000.0,
            date: DateTime(2026, 5, 1),
            notes: 'Second payment',
            interestPaid: 0.0, // wrong legacy split
            principalPaid: 1000.0,
          ),
          Payment(
            id: 'p-1',
            paymentId: 'PAY092605',
            recordId: 'rec-replay',
            amount: 500.0,
            date: DateTime(2026, 3, 1),
            notes: 'First payment',
            interestPaid: 0.0, // wrong legacy split
            principalPaid: 500.0,
          ),
        ],
      );

      final replayed = reallocatePayments(rec);
      expect(replayed.length, 2);

      // Replayed oldest-first: p-1 on March 1 first
      expect(replayed[0].id, 'p-1');
      expect(replayed[0].interestPaid, 400.0);
      expect(replayed[0].principalPaid, 100.0);

      // p-2 on May 1 second:
      // Total accrued up to May 1 = 800. Accumulated interest paid so far = 400. Outstanding = 400.
      expect(replayed[1].id, 'p-2');
      expect(replayed[1].interestPaid, 400.0);
      expect(replayed[1].principalPaid, 600.0);
    });

    test('checkPaymentInsert validates payment rules and backdated refund ordering (Addendum J.3)', () {
      final activeRec = LedgerRecord(
        id: 'rec-validate',
        transactionId: 'TRAN092607',
        customerId: 'c-1',
        type: RecordType.given,
        status: RecordStatus.active,
        startDate: DateTime(2026, 2, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        payments: [
          Payment(
            id: 'p-1',
            paymentId: 'PAY092607',
            recordId: 'rec-validate',
            amount: 2000.0,
            date: DateTime(2026, 3, 15),
            notes: '',
            interestPaid: 400.0,
            principalPaid: 1600.0,
          ),
        ],
      );

      // 1. Valid normal payment
      final validPay = checkPaymentInsert(
        record: activeRec,
        amount: 500.0,
        date: DateTime(2026, 4, 1),
      );
      expect(validPay.$1, isTrue);
      expect(validPay.$2, isNull);

      // 2. Cannot add payment to settled record
      final settledRec = activeRec.copyWith(status: RecordStatus.settled);
      final invalidSettled = checkPaymentInsert(
        record: settledRec,
        amount: 500.0,
        date: DateTime(2026, 4, 1),
      );
      expect(invalidSettled.$1, isFalse);
      expect(invalidSettled.$2, contains('settled'));

      // 3. Cannot add zero payment
      final zeroPay = checkPaymentInsert(
        record: activeRec,
        amount: 0.0,
        date: DateTime(2026, 4, 1),
      );
      expect(zeroPay.$1, isFalse);
      expect(zeroPay.$2, contains('zero'));

      // 4. Payment date cannot precede record start date
      final beforeStart = checkPaymentInsert(
        record: activeRec,
        amount: 500.0,
        date: DateTime(2026, 1, 15),
      );
      expect(beforeStart.$1, isFalse);
      expect(beforeStart.$2, contains('start date'));

      // 5. Valid refund
      final validRefund = checkPaymentInsert(
        record: activeRec,
        amount: -500.0,
        date: DateTime(2026, 3, 20),
      );
      expect(validRefund.$1, isTrue);

      // 6. Refund cannot exceed total payments received (totalPaid = 2000)
      final excessiveRefund = checkPaymentInsert(
        record: activeRec,
        amount: -2500.0,
        date: DateTime(2026, 3, 20),
      );
      expect(excessiveRefund.$1, isFalse);
      expect(excessiveRefund.$2, contains('exceed'));

      // 7. Backdated refund cannot be dated before the earliest payment (Addendum J.3 / v1.17 rule)
      final backdatedRefund = checkPaymentInsert(
        record: activeRec,
        amount: -500.0,
        date: DateTime(2026, 2, 15), // before 2026-03-15
      );
      expect(backdatedRefund.$1, isFalse);
      expect(backdatedRefund.$2, contains('earlier than the payment it refunds'));
    });

    test('shouldNotify enforces throttle rules (Addendum J.8)', () {
      final today = DateTime(2026, 9, 23);

      // Never notified -> true
      expect(shouldNotify(lastNotifiedDate: null, today: today), isTrue);

      // Notified today -> false (0 days gap < 1 throttleDay)
      expect(shouldNotify(lastNotifiedDate: today, today: today), isFalse);

      // Notified yesterday -> true (1 day gap >= 1 throttleDay)
      final yesterday = DateTime(2026, 9, 22);
      expect(shouldNotify(lastNotifiedDate: yesterday, today: today), isTrue);

      // Notified 2 days ago with 3 throttle days -> false (2 < 3)
      final twoDaysAgo = DateTime(2026, 9, 21);
      expect(shouldNotify(lastNotifiedDate: twoDaysAgo, today: today, throttleDays: 3), isFalse);

      // Notified 3 days ago with 3 throttle days -> true (3 >= 3)
      final threeDaysAgo = DateTime(2026, 9, 20);
      expect(shouldNotify(lastNotifiedDate: threeDaysAgo, today: today, throttleDays: 3), isTrue);
    });
  });
}

