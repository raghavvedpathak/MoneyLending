import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/calculations/calculations.dart';
import 'package:money_lending/core/domain/domain.dart';

void main() {
  group('Section 5.1 Business Logic — Pure Dart Calculations', () {
    final fixedToday = DateTime(2026, 9, 29); // Injected date, no clock reads [FIX-CLOCK-1]

    test('1. calculateItemValue and calculateTotalItemValue snapshot formula', () {
      const item1 = LedgerItem(
        id: 'item-1',
        recordId: 'rec-1',
        name: 'Gold Ring 22k',
        itemCategory: 'GOLD',
        weight: 10.0,
        purity: 91.6,
        rate: 7000.0,
        itemValue: 64120.0,
        lendPercentage: 80.0,
        lendableAmount: 51296.0,
      );

      const item2 = LedgerItem(
        id: 'item-2',
        recordId: 'rec-1',
        name: 'Silver Coin',
        itemCategory: 'SILVER',
        weight: 100.0,
        purity: 99.9,
        rate: 90.0,
        itemValue: 8991.0,
        lendPercentage: 70.0,
        lendableAmount: 6293.7,
      );

      expect(calculateItemValue(item1), 64120.0);
      expect(calculateItemValue(item2), 8991.0);
      expect(calculateTotalItemValue([item1, item2]), 73111.0);
      expect(liveItemValue(item1, 7500.0), roundMoney(10.0 * 0.916 * 7500.0));
    });

    test('2. calculateInterestForPeriod enforces 2-decimal rounding [FIX-MONEY-1]', () {
      // Spec example: 12,345.67 at 2.5%/month for 0.5 month is 154.32, not 154.320875
      final start = DateTime(2026, 4, 1);
      final end = DateTime(2026, 4, 16); // 15 days = 0.5 months under half-month rounding
      expect(getMonthsBetween(start, end), 0.5);

      final interest = calculateInterestForPeriod(
        principal: 12345.67,
        rate: 2.5,
        start: start,
        end: end,
      );
      expect(interest, 154.32); // Must be exactly 2-decimal rounded
    });

    test('3. LedgerRecord domain model supports GIVEN and TAKEN party fields', () {
      final givenRecord = LedgerRecord(
        id: 'rec-given',
        transactionId: 'TRAN092601',
        type: RecordType.given,
        status: RecordStatus.active,
        customerId: 'cust-1',
        lenderId: null,
        startDate: DateTime(2026, 5, 1, 14, 30),
        principalAmount: 50000.0,
        interestRate: 2.0,
        items: const [],
        payments: const [],
      );

      final takenRecord = LedgerRecord(
        id: 'rec-taken',
        transactionId: 'TRAN092602',
        type: RecordType.taken,
        status: RecordStatus.active,
        customerId: null,
        lenderId: 'lend-1',
        linkedRecordId: 'rec-given',
        startDate: DateTime(2026, 5, 2, 10, 15),
        principalAmount: 40000.0,
        interestRate: 1.5,
        items: const [],
        payments: const [],
      );

      expect(givenRecord.isGiven, isTrue);
      expect(givenRecord.customerId, 'cust-1');
      expect(givenRecord.lenderId, isNull);

      expect(takenRecord.isTaken, isTrue);
      expect(takenRecord.customerId, isNull);
      expect(takenRecord.lenderId, 'lend-1');
      expect(takenRecord.linkedRecordId, 'rec-given');

      // Test copyWith
      final updatedTaken = takenRecord.copyWith(principalAmount: 45000.0);
      expect(updatedTaken.principalAmount, 45000.0);
      expect(updatedTaken.lenderId, 'lend-1');
    });

    test('4. Payment.draft factory creates unsaved payment [FIX-CHECKPAYMENT-DRAFT-1]', () {
      final draft = Payment.draft(amount: 5000.0, date: DateTime(2026, 9, 29, 15, 0));
      expect(draft.id, '~draft');
      expect(draft.amount, 5000.0);
      expect(draft.date, DateTime(2026, 9, 29, 15, 0));
      expect(draft.paymentId, '');
      expect(draft.interestPaid, 0.0);
      expect(draft.principalPaid, 0.0);
    });

    test('5. getBorrowerReports rolls up active GIVEN records per Customer', () {
      final customerA = Customer(
        id: 'c-a',
        displayId: 'CUST26-27-01',
        name: 'Alice',
        phone: '9876543210',
        address: 'MG Road',
        createdAt: DateTime(2026, 4, 1),
      );
      final customerB = Customer(
        id: 'c-b',
        displayId: 'CUST26-27-02',
        name: 'Bob',
        phone: '9876543211',
        address: 'Brigade Road',
        createdAt: DateTime(2026, 4, 2),
      );

      final recA1 = LedgerRecord(
        id: 'r-a1',
        transactionId: 'TRAN092601',
        type: RecordType.given,
        status: RecordStatus.active,
        customerId: 'c-a',
        startDate: DateTime(2026, 7, 29), // exactly 2 months before fixedToday
        principalAmount: 20000.0,
        interestRate: 2.0, // 2% per mo = 400/mo = 800 total interest
      );

      final recA2 = LedgerRecord(
        id: 'r-a2',
        transactionId: 'TRAN092602',
        type: RecordType.given,
        status: RecordStatus.active,
        customerId: 'c-a',
        startDate: DateTime(2026, 8, 29), // 1 month before fixedToday
        principalAmount: 30000.0,
        interestRate: 2.0, // 2% per mo = 600 total interest
      );

      final recSettled = LedgerRecord(
        id: 'r-a-settled',
        transactionId: 'TRAN092603',
        type: RecordType.given,
        status: RecordStatus.settled,
        customerId: 'c-a',
        startDate: DateTime(2026, 5, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
      );

      final reports = getBorrowerReports(
        customers: [customerA, customerB],
        records: [recA1, recA2, recSettled],
        today: fixedToday,
      );

      expect(reports.length, 2);

      final repA = reports.firstWhere((r) => r.customer.id == 'c-a');
      expect(repA.activeRecordCount, 2); // Excludes settled record
      expect(repA.totalPrincipalOut, 50000.0);
      expect(repA.totalInterestAccrued, 1400.0); // 800 + 600
      expect(repA.totalDue, 51400.0);
      expect(repA.totalPrincipal, 50000.0); // Compatibility getter

      final repB = reports.firstWhere((r) => r.customer.id == 'c-b');
      expect(repB.activeRecordCount, 0);
      expect(repB.totalPrincipalOut, 0.0);
      expect(repB.totalInterestAccrued, 0.0);
      expect(repB.totalDue, 0.0);
    });

    test('6. getLenderReports rolls up active TAKEN records per Lender', () {
      final lender1 = Lender(
        id: 'l-1',
        displayId: 'LEND26-27-01',
        name: 'State Bank',
        lenderType: LenderType.institution,
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 1),
      );

      final recL1 = LedgerRecord(
        id: 'r-l1',
        transactionId: 'TRAN092604',
        type: RecordType.taken,
        status: RecordStatus.active,
        lenderId: 'l-1',
        startDate: DateTime(2026, 7, 29), // 2 months
        principalAmount: 100000.0,
        interestRate: 1.0, // 1% per mo = 1000/mo = 2000 total interest
      );

      final reports = getLenderReports(
        lenders: [lender1],
        records: [recL1],
        today: fixedToday,
      );

      expect(reports.length, 1);
      final repL = reports.first;
      expect(repL.activeRecordCount, 1);
      expect(repL.totalPrincipalTaken, 100000.0);
      expect(repL.totalInterestPayable, 2000.0);
      expect(repL.totalDueToLender, 102000.0);
    });

    test('7. getDashboard aggregates totals across GIVEN and TAKEN records', () {
      final givenRec = LedgerRecord(
        id: 'g-1',
        transactionId: 'TRAN092605',
        type: RecordType.given,
        status: RecordStatus.active,
        customerId: 'c-1',
        startDate: DateTime(2026, 7, 29),
        principalAmount: 50000.0,
        interestRate: 2.0, // 2 months = 2000
      );

      final takenRec = LedgerRecord(
        id: 't-1',
        transactionId: 'TRAN092606',
        type: RecordType.taken,
        status: RecordStatus.active,
        lenderId: 'l-1',
        startDate: DateTime(2026, 7, 29),
        principalAmount: 30000.0,
        interestRate: 1.5, // 2 months = 900
      );

      final stats = getDashboard([givenRec, takenRec], today: fixedToday);

      expect(stats.totalPrincipalGiven, 50000.0);
      expect(stats.totalInterestAccruedGiven, 2000.0);
      expect(stats.totalDueGiven, 52000.0);

      expect(stats.totalPrincipalTaken, 30000.0);
      expect(stats.totalInterestAccruedTaken, 900.0);
      expect(stats.totalDueTaken, 30900.0);
    });

    test('8. lastActivityDate computes latest payment date or start date [FIX-LASTACTIVITY-1]', () {
      final recordWithoutPayments = LedgerRecord(
        id: 'rec-no-pay',
        transactionId: 'TRAN092607',
        type: RecordType.given,
        status: RecordStatus.active,
        startDate: DateTime(2026, 5, 10, 11, 0),
        principalAmount: 10000.0,
        interestRate: 2.0,
        payments: const [],
      );

      expect(lastActivityDate(recordWithoutPayments), DateTime(2026, 5, 10));

      final recordWithPayments = LedgerRecord(
        id: 'rec-with-pay',
        transactionId: 'TRAN092608',
        type: RecordType.given,
        status: RecordStatus.active,
        startDate: DateTime(2026, 5, 10, 11, 0),
        principalAmount: 10000.0,
        interestRate: 2.0,
        payments: [
          Payment(
            id: 'p-1',
            paymentId: 'PAY092601',
            recordId: 'rec-with-pay',
            amount: 500.0,
            date: DateTime(2026, 6, 15, 14, 0),
            notes: '',
            interestPaid: 500.0,
            principalPaid: 0.0,
          ),
          Payment(
            id: 'p-2',
            paymentId: 'PAY092602',
            recordId: 'rec-with-pay',
            amount: 600.0,
            date: DateTime(2026, 8, 20, 16, 0),
            notes: '',
            interestPaid: 600.0,
            principalPaid: 0.0,
          ),
        ],
      );

      expect(lastActivityDate(recordWithPayments), DateTime(2026, 8, 20));
    });

    test('9. checkPaymentInsert validates payments and refunds dry-run', () {
      final activeRecord = LedgerRecord(
        id: 'rec-chk',
        transactionId: 'TRAN092609',
        type: RecordType.given,
        status: RecordStatus.active,
        startDate: DateTime(2026, 5, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        payments: [
          Payment(
            id: 'p-orig',
            paymentId: 'PAY092601',
            recordId: 'rec-chk',
            amount: 2000.0,
            date: DateTime(2026, 6, 1),
            notes: '',
            interestPaid: 200.0,
            principalPaid: 1800.0,
          ),
        ],
      );

      // Valid payment
      final (valid, err) = checkPaymentInsert(
        record: activeRecord,
        amount: 1000.0,
        date: DateTime(2026, 7, 1),
      );
      expect(valid, isTrue);
      expect(err, isNull);

      // Zero amount error
      final (zeroValid, zeroErr) = checkPaymentInsert(
        record: activeRecord,
        amount: 0.0,
        date: DateTime(2026, 7, 1),
      );
      expect(zeroValid, isFalse);
      expect(zeroErr, contains('zero'));

      // Date before record start error
      final (beforeValid, beforeErr) = checkPaymentInsert(
        record: activeRecord,
        amount: 1000.0,
        date: DateTime(2026, 4, 15),
      );
      expect(beforeValid, isFalse);
      expect(beforeErr, contains('before record start date'));

      // Valid refund
      final (refundValid, refundErr) = checkPaymentInsert(
        record: activeRecord,
        amount: -500.0,
        date: DateTime(2026, 6, 15),
      );
      expect(refundValid, isTrue);
      expect(refundErr, isNull);

      // Refund exceeding total paid
      final (excessRefundValid, excessRefundErr) = checkPaymentInsert(
        record: activeRecord,
        amount: -3000.0,
        date: DateTime(2026, 6, 15),
      );
      expect(excessRefundValid, isFalse);
      expect(excessRefundErr, contains('exceed'));
    });

    test('10. mergeOverdueRecords unions reasons per record ID', () {
      final rec = LedgerRecord(
        id: 'rec-merge-1',
        transactionId: 'TRAN092610',
        type: RecordType.given,
        status: RecordStatus.active,
        startDate: DateTime(2026, 5, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
      );

      final activityOverdue = [
        OverdueRecord(
          record: rec,
          reasons: const {OverdueReason.noActivity},
          daysSinceActivity: 45,
          lastActivityDate: DateTime(2026, 8, 15),
        ),
      ];

      final collateralOverdue = [
        OverdueRecord(
          record: rec,
          reasons: const {OverdueReason.collateralBreachedNow},
          currentCollateralValue: 8000.0,
          currentObligation: 10800.0,
        ),
      ];

      final merged = mergeOverdueRecords(activityOverdue, collateralOverdue);
      expect(merged.length, 1);
      expect(merged.first.reasons, {
        OverdueReason.noActivity,
        OverdueReason.collateralBreachedNow,
      });
      expect(merged.first.daysSinceActivity, 45);
      expect(merged.first.currentCollateralValue, 8000.0);
    });
  });
}
