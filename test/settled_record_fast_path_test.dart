import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/calculations/calculations.dart';
import 'package:money_lending/domain/domain.dart';

void main() {
  group('Settled-Record Fast-Path Tests (§5.2.1)', () {
    test('1. Settled with non-null calculatedInterest returns hardcoded snapshot and 7 fields', () {
      final settledRecord = LedgerRecord(
        id: 'rec-settled-1',
        transactionId: 'TXN-000001',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        status: RecordStatus.SETTLED,
        settledDate: DateTime(2026, 3, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        calculatedInterest: 400.0, // Stored snapshot at settlement
        payments: [
          Payment(
            id: 'p-1',
            recordId: 'rec-settled-1',
            amount: 10400.0,
            date: DateTime(2026, 3, 1),
            notes: 'Settled in full',
            interestPaid: 400.0,
            principalPaid: 10000.0,
          ),
        ],
      );

      // Even when targetDate is far in the future (e.g. 2026-12-31), settled record must NOT recalculate!
      final financials = calculateRecordFinancials(settledRecord, DateTime(2026, 12, 31));

      expect(financials.totalInterest, 400.0);
      expect(financials.totalPaid, 10400.0);
      expect(financials.interestPaid, 400.0);
      expect(financials.principalPaid, 10000.0);
      expect(financials.outstandingInterest, 0.0);
      expect(financials.outstandingPrincipal, 0.0);
      expect(financials.totalDue, 0.0);
      expect(financials.overpaymentAmount, 0.0);
      expect(financials.principal, 10000.0);
      expect(financials.months, 2.0); // Jan 1 to Mar 1 = 2 months
    });

    test('2. Settled with null calculatedInterest and null settledDate returns zeroed snapshot', () {
      // Legacy backup import where both calculatedInterest and settledDate are null
      final legacySettled = LedgerRecord(
        id: 'rec-legacy-1',
        transactionId: 'TXN-000002',
        type: RecordType.GIVEN,
        customerId: 'c-2',
        startDate: DateTime(2026, 1, 1),
        status: RecordStatus.SETTLED,
        settledDate: null, // Null settledDate
        principalAmount: 5000.0,
        interestRate: 2.0,
        calculatedInterest: null, // Null calculatedInterest
        payments: [
          Payment(
            id: 'p-legacy-1',
            recordId: 'rec-legacy-1',
            amount: 2000.0,
            date: DateTime(2026, 2, 1),
            notes: 'Partial payment before settlement',
            interestPaid: 200.0,
            principalPaid: 1800.0,
          ),
        ],
      );

      final financials = calculateRecordFinancials(legacySettled, DateTime(2026, 12, 31));

      // Mandated by §5.2.1: totalInterest = 0.0, outstandingInterest = 0.0,
      // totalDue = principalAmount - principalPaid, outstandingPrincipal = principalAmount - principalPaid
      expect(financials.totalInterest, 0.0);
      expect(financials.totalPaid, 2000.0);
      expect(financials.interestPaid, 200.0);
      expect(financials.principalPaid, 1800.0);
      expect(financials.outstandingInterest, 0.0);
      expect(financials.outstandingPrincipal, 3200.0); // 5000 - 1800
      expect(financials.totalDue, 3200.0);
      expect(financials.overpaymentAmount, 0.0);
      expect(financials.months, 0.0);
      expect(financials.principal, 5000.0);
    });

    test('3. Settled with null calculatedInterest but non-null settledDate uses settledDate as target', () {
      // Legacy backup import with settledDate but no calculatedInterest
      final legacyWithSettledDate = LedgerRecord(
        id: 'rec-legacy-2',
        transactionId: 'TXN-000003',
        type: RecordType.GIVEN,
        customerId: 'c-3',
        startDate: DateTime(2026, 1, 1),
        status: RecordStatus.SETTLED,
        settledDate: DateTime(2026, 2, 1), // 1 month
        principalAmount: 10000.0,
        interestRate: 2.0,
        calculatedInterest: null,
        payments: [
          Payment(
            id: 'p-legacy-2',
            recordId: 'rec-legacy-2',
            amount: 10200.0,
            date: DateTime(2026, 2, 1),
            notes: 'Full settlement',
            interestPaid: 200.0,
            principalPaid: 10000.0,
          ),
        ],
      );

      // TargetDate passed as 2026-12-31 should be ignored in favor of settledDate (2026-02-01)
      final financials = calculateRecordFinancials(legacyWithSettledDate, DateTime(2026, 12, 31));

      expect(financials.totalInterest, 200.0); // 10000 * 2% * 1 month
      expect(financials.totalPaid, 10200.0);
      expect(financials.interestPaid, 200.0);
      expect(financials.principalPaid, 10000.0);
      expect(financials.outstandingInterest, 0.0);
      expect(financials.outstandingPrincipal, 0.0);
      expect(financials.totalDue, 0.0);
      expect(financials.overpaymentAmount, 0.0);
      expect(financials.months, 1.0);
    });

    test('4. [FIX-FINANCIALS-OVERPAY-1] Settled with non-null calculatedInterest and overpayment supplies overpaymentAmount', () {
      final settledOverpaid = LedgerRecord(
        id: 'rec-settled-overpaid',
        transactionId: 'TXN-000004',
        type: RecordType.GIVEN,
        customerId: 'c-4',
        startDate: DateTime(2026, 1, 1),
        status: RecordStatus.SETTLED,
        settledDate: DateTime(2026, 3, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        calculatedInterest: 400.0,
        payments: [
          Payment(
            id: 'p-over-1',
            recordId: 'rec-settled-overpaid',
            amount: 11400.0,
            date: DateTime(2026, 3, 1),
            notes: 'Overpaid settlement',
            interestPaid: 400.0,
            principalPaid: 11000.0, // 1000 overpaid
          ),
        ],
      );

      final financials = calculateRecordFinancials(settledOverpaid, DateTime(2026, 12, 31));

      expect(financials.totalInterest, 400.0);
      expect(financials.outstandingInterest, 0.0);
      expect(financials.outstandingPrincipal, 0.0);
      expect(financials.totalDue, 0.0);
      expect(financials.overpaymentAmount, 1000.0); // max(0.0, 11000 - 10000)
    });

    test('5. [FIX-FINANCIALS-OVERPAY-1] Legacy settled with null calculatedInterest/settledDate and overpayment derives both fields consistently', () {
      final legacyOverpaid = LedgerRecord(
        id: 'rec-legacy-overpaid',
        transactionId: 'TXN-000005',
        type: RecordType.GIVEN,
        customerId: 'c-5',
        startDate: DateTime(2026, 1, 1),
        status: RecordStatus.SETTLED,
        settledDate: null,
        principalAmount: 5000.0,
        interestRate: 2.0,
        calculatedInterest: null,
        payments: [
          Payment(
            id: 'p-leg-over-1',
            recordId: 'rec-legacy-overpaid',
            amount: 6000.0,
            date: DateTime(2026, 2, 1),
            notes: 'Overpaid legacy record',
            interestPaid: 0.0,
            principalPaid: 6000.0, // 1000 overpaid
          ),
        ],
      );

      final financials = calculateRecordFinancials(legacyOverpaid, DateTime(2026, 12, 31));

      expect(financials.totalInterest, 0.0);
      expect(financials.outstandingInterest, 0.0);
      expect(financials.outstandingPrincipal, 0.0); // max(0.0, -1000)
      expect(financials.totalDue, 0.0);
      expect(financials.overpaymentAmount, 1000.0); // max(0.0, -(-1000))
    });
  });
}
