import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/calculations/calculations.dart';
import 'package:money_lending/domain/domain.dart';

void main() {
  group('Financials Data Class & calculateRecordFinancials Full Algorithm (§5.2.2)', () {
    test('1. Financials data class contains all 7 canonical fields', () {
      const financials = Financials(
        totalInterest: 500.0,
        totalPaid: 200.0,
        interestPaid: 200.0,
        principalPaid: 0.0,
        outstandingInterest: 300.0,
        outstandingPrincipal: 10000.0,
        totalDue: 10300.0,
      );

      expect(financials.totalInterest, 500.0);
      expect(financials.totalPaid, 200.0);
      expect(financials.interestPaid, 200.0);
      expect(financials.principalPaid, 0.0);
      expect(financials.outstandingInterest, 300.0);
      expect(financials.outstandingPrincipal, 10000.0);
      expect(financials.totalDue, 10300.0);
      // Semantic backward-compatible getters
      expect(financials.remainingInterest, 300.0);
      expect(financials.remainingPrincipal, 10000.0);
    });

    test('2. Step 1: Effective target date capped at past endDate', () {
      final recordWithPastEndDate = LedgerRecord(
        id: 'rec-end-past',
        transactionId: 'TXN-000001',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1, 10, 0),
        endDate: DateTime(2026, 3, 1), // 2 months loan agreed to end on March 1
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      final today = DateTime(2026, 6, 1); // 5 months after startDate
      // Effective target date should be capped at endDate (2026-03-01 = 2 months)
      final fin = calculateRecordFinancials(recordWithPastEndDate, today, today);

      // 10000 * 2% * 2 months = 400 (NOT 5 months = 1000)
      expect(fin.totalInterest, 400.0);
      expect(fin.outstandingInterest, 400.0);
      expect(fin.outstandingPrincipal, 10000.0);
      expect(fin.totalDue, 10400.0);
      expect(fin.months, 2.0);
    });

    test('3. Step 1: Future endDate does not cap targetDate', () {
      final recordWithFutureEndDate = LedgerRecord(
        id: 'rec-end-future',
        transactionId: 'TXN-000002',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31), // Future loan end date
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      final today = DateTime(2026, 3, 1); // 2 months
      // Future endDate is ignored, targetDate (2026-03-01) is used
      final fin = calculateRecordFinancials(recordWithFutureEndDate, today, today);

      expect(fin.totalInterest, 400.0); // 2 months
      expect(fin.totalDue, 10400.0);
      expect(fin.months, 2.0);
    });

    test('4. Step 2-4: Full ledger calculation with payments and floored balances', () {
      final recordWithPayments = LedgerRecord(
        id: 'rec-with-payments',
        transactionId: 'TXN-000003',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1, 14, 30), // [FIX-TIMESTAMP-CALC-1] DateTime with time
        principalAmount: 20000.0,
        interestRate: 2.0, // 400 per month
        status: RecordStatus.ACTIVE,
        payments: [
          Payment(
            id: 'p-1',
            recordId: 'rec-with-payments',
            amount: 500.0,
            date: DateTime(2026, 2, 1, 11, 0),
            notes: '400 interest + 100 principal',
            interestPaid: 400.0,
            principalPaid: 100.0,
          ),
          Payment(
            id: 'p-2',
            recordId: 'rec-with-payments',
            amount: 1000.0,
            date: DateTime(2026, 3, 1, 16, 0),
            notes: '400 interest + 600 principal',
            interestPaid: 400.0,
            principalPaid: 600.0,
          ),
        ],
      );

      final target = DateTime(2026, 4, 1); // 3 months from Jan 1
      final fin = calculateRecordFinancials(recordWithPayments, target, target);

      // Total interest accrued: 20000 * 2% * 3 months = 1200
      expect(fin.totalInterest, 1200.0);
      // Total paid: 500 + 1000 = 1500
      expect(fin.totalPaid, 1500.0);
      // Interest paid: 400 + 400 = 800
      expect(fin.interestPaid, 800.0);
      // Principal paid: 100 + 600 = 700
      expect(fin.principalPaid, 700.0);
      // Outstanding interest: 1200 - 800 = 400
      expect(fin.outstandingInterest, 400.0);
      // Outstanding principal: 20000 - 700 = 19300
      expect(fin.outstandingPrincipal, 19300.0);
      // Total due: 19300 + 400 = 19700
      expect(fin.totalDue, 19700.0);
      expect(fin.months, 3.0);
    });

    test('5. Balances are floored at 0.0 (never negative)', () {
      final recordOverpaid = LedgerRecord(
        id: 'rec-overpaid',
        transactionId: 'TXN-000004',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 1000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        payments: [
          Payment(
            id: 'p-large',
            recordId: 'rec-overpaid',
            amount: 2000.0,
            date: DateTime(2026, 1, 15),
            interestPaid: 100.0,
            principalPaid: 1900.0, // > 1000 principal
          ),
        ],
      );

      final target = DateTime(2026, 1, 15);
      final fin = calculateRecordFinancials(recordOverpaid, target, target);

      expect(fin.outstandingPrincipal, 0.0, reason: 'Must floor at 0.0');
      expect(fin.outstandingInterest, 0.0);
      expect(fin.totalDue, 0.0);
      expect(fin.overpaymentAmount, 990.0); // 2000 totalPaid - (1000 principal + 10 interest accrued)
    });

    test('6. [FIX-ACCRUAL-END-1] accrualEndDate pure helper respects min(endDate, target) with no clock', () {
      final recordWithEndDate = LedgerRecord(
        id: 'rec-accrual-1',
        transactionId: 'TXN-000005',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 3, 1),
        principalAmount: 1000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      // Target after endDate -> returns endDate
      final targetAfter = DateTime(2026, 5, 1);
      expect(accrualEndDate(recordWithEndDate, targetAfter), DateTime(2026, 3, 1));

      // Target before endDate -> returns target
      final targetBefore = DateTime(2026, 2, 1);
      expect(accrualEndDate(recordWithEndDate, targetBefore), DateTime(2026, 2, 1));

      // Record with no endDate -> returns target
      final recordNoEndDate = LedgerRecord(
        id: 'rec-accrual-2',
        transactionId: 'TXN-000006',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        endDate: null,
        principalAmount: 1000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );
      expect(accrualEndDate(recordNoEndDate, targetAfter), targetAfter);
    });

    test('7. [FIX-FINANCIALS-NET-1] Worked Example: interest paid in excess credits against principal in totalDue', () {
      // Worked example: ₹10,000 at 3%/month, 2 months elapsed, customer pays ₹600 (all interest).
      // Record is then edited to 2%/month.
      // totalInterest = 400, rawOutstandingInterest = -200, rawOutstandingPrincipal = 10,000.
      // totalDue = 9,800 (10000 + 400 - 600 = 9800).
      // outstandingInterest = 0 (floored), outstandingPrincipal = 10000 (floored).
      // overpaymentAmount = max(0, -(-200 + 10000)) = 0.
      final editedRecord = LedgerRecord(
        id: 'rec-netted-1',
        transactionId: 'TXN-000007',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 10000.0,
        interestRate: 2.0, // Edited down to 2%
        status: RecordStatus.ACTIVE,
        payments: [
          Payment(
            id: 'pay-net-1',
            recordId: 'rec-netted-1',
            amount: 600.0,
            date: DateTime(2026, 3, 1),
            interestPaid: 600.0, // Paid under previous 3% rate
            principalPaid: 0.0,
          ),
        ],
      );

      final fin = calculateRecordFinancials(editedRecord, DateTime(2026, 3, 1));

      expect(fin.totalInterest, 400.0); // 10000 * 2% * 2 months
      expect(fin.interestPaid, 600.0);
      expect(fin.principalPaid, 0.0);
      expect(fin.outstandingInterest, 0.0); // Individually floored for display
      expect(fin.outstandingPrincipal, 10000.0); // Individually floored for display
      expect(fin.totalDue, 9800.0); // Netted before flooring: -200 + 10000 = 9800
      expect(fin.overpaymentAmount, 0.0);
    });
  });
}
