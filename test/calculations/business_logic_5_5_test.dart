import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/calculations/calculations.dart';
import 'package:money_lending/core/pdf/pdf.dart';
import 'package:money_lending/domain/domain.dart';

void main() {
  group('Section 5.5 Testing Strategy: Pure Unit Tests & Calculation Verification', () {
    final today = DateTime(2026, 9, 20);

    // =========================================================================
    // 1. calculateRecordFinancials COMPLEX TEST MATRIX
    // =========================================================================
    group('1. calculateRecordFinancials Matrix', () {
      test('Zero payments: full principal and interest remain outstanding', () {
        final record = LedgerRecord(
          id: 'rec-zero',
          transactionId: 'TRAN092601',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 6, 20),
          principalAmount: 10000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          payments: const [],
        );

        final fin = calculateRecordFinancials(record, today);
        expect(fin.totalInterest, 600.0); // 3 months * 2% * 10,000
        expect(fin.totalPaid, 0.0);
        expect(fin.interestPaid, 0.0);
        expect(fin.principalPaid, 0.0);
        expect(fin.outstandingInterest, 600.0);
        expect(fin.outstandingPrincipal, 10000.0);
        expect(fin.totalDue, 10600.0);
        expect(fin.overpaymentAmount, 0.0);
      });

      test('Partial payments: interest-first allocation reduces interest before principal', () {
        final record = LedgerRecord(
          id: 'rec-partial',
          transactionId: 'TRAN092602',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 6, 20),
          principalAmount: 10000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          payments: [
            Payment(
              id: 'p-1',
              recordId: 'rec-partial',
              amount: 500.0,
              date: DateTime(2026, 7, 20),
              interestPaid: 400.0,
              principalPaid: 100.0,
            ),
          ],
        );

        final fin = calculateRecordFinancials(record, today);
        expect(fin.totalInterest, 600.0);
        expect(fin.totalPaid, 500.0);
        expect(fin.interestPaid, 400.0);
        expect(fin.principalPaid, 100.0);
        expect(fin.outstandingInterest, 200.0); // 600 - 400
        expect(fin.outstandingPrincipal, 9900.0); // 10,000 - 100
        expect(fin.totalDue, 10100.0);
        expect(fin.overpaymentAmount, 0.0);
      });

      test('Overpayments: balances floored at zero and overpaymentAmount calculated', () {
        final record = LedgerRecord(
          id: 'rec-over',
          transactionId: 'TRAN092603',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 8, 20),
          principalAmount: 5000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          payments: [
            Payment(
              id: 'p-over',
              recordId: 'rec-over',
              amount: 6000.0,
              date: DateTime(2026, 9, 20),
              interestPaid: 100.0,
              principalPaid: 5900.0, // Overpaid principal
            ),
          ],
        );

        final fin = calculateRecordFinancials(record, today);
        expect(fin.totalInterest, 100.0); // 1 month = 100
        expect(fin.totalPaid, 6000.0);
        expect(fin.outstandingInterest, 0.0);
        expect(fin.outstandingPrincipal, 0.0); // Floored at 0
        expect(fin.totalDue, 0.0); // Floored at 0
        expect(fin.overpaymentAmount, 900.0); // 6000 - (5000 + 100) = 900
      });

      test('Settled record with calculatedInterest populated uses stored snapshot and bypasses recalculation', () {
        final settledRecord = LedgerRecord(
          id: 'rec-settled-stored',
          transactionId: 'TRAN092604',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2025, 1, 1),
          settledDate: DateTime(2025, 6, 1),
          status: RecordStatus.SETTLED,
          principalAmount: 10000.0,
          interestRate: 2.0,
          calculatedInterest: 350.0, // Snapshotted negotiated interest
          payments: [
            Payment(
              id: 'p-set',
              recordId: 'rec-settled-stored',
              amount: 10350.0,
              date: DateTime(2025, 6, 1),
              interestPaid: 350.0,
              principalPaid: 10000.0,
            ),
          ],
        );

        // Even when evaluated at today (2026-09-20), it bypasses recalculation!
        final fin = calculateRecordFinancials(settledRecord, today);
        expect(fin.totalInterest, 350.0);
        expect(fin.interestPaid, 350.0);
        expect(fin.principalPaid, 10000.0);
        expect(fin.outstandingInterest, 0.0);
        expect(fin.outstandingPrincipal, 0.0);
        expect(fin.totalDue, 0.0);
        expect(fin.overpaymentAmount, 0.0);
      });

      test('Settled record with calculatedInterest null uses settledDate as target date', () {
        final settledLegacy = LedgerRecord(
          id: 'rec-settled-null',
          transactionId: 'TRAN092605',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 1, 1),
          settledDate: DateTime(2026, 3, 1), // 2 months
          status: RecordStatus.SETTLED,
          principalAmount: 10000.0,
          interestRate: 2.0,
          calculatedInterest: null, // Null calculatedInterest
          payments: [
            Payment(
              id: 'p-leg',
              recordId: 'rec-settled-null',
              amount: 10400.0,
              date: DateTime(2026, 3, 1),
              interestPaid: 400.0,
              principalPaid: 10000.0,
            ),
          ],
        );

        final fin = calculateRecordFinancials(settledLegacy, today);
        // Uses settledDate (2026-03-01) -> 2 months interest = 400
        expect(fin.totalInterest, 400.0);
        expect(fin.totalDue, 0.0);
        expect(fin.overpaymentAmount, 0.0);
      });

      test('Records with multiple items compute accurately', () {
        final multiItemRecord = LedgerRecord(
          id: 'rec-multi',
          transactionId: 'TRAN092606',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 8, 20),
          principalAmount: 15000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          items: const [
            LedgerItem(
              id: 'i-1',
              recordId: 'rec-multi',
              name: 'Gold Ring',
              itemCategory: 'GOLD_22K',
              weight: 5.0,
              purity: 100.0,
              itemValue: 30000.0,
            ),
            LedgerItem(
              id: 'i-2',
              recordId: 'rec-multi',
              name: 'Silver Bracelet',
              itemCategory: 'SILVER',
              weight: 100.0,
              purity: 100.0,
              itemValue: 8000.0,
            ),
          ],
        );

        final fin = calculateRecordFinancials(multiItemRecord, today);
        expect(fin.totalInterest, 300.0); // 1 month * 2% * 15,000
        expect(fin.totalDue, 15300.0);
      });
    });

    // =========================================================================
    // 2. [FIX-FINANCIALS-NET-1] WORKED EXAMPLE & [FIX-ACCRUAL-END-1]
    // =========================================================================
    group('2. [FIX-FINANCIALS-NET-1] & [FIX-ACCRUAL-END-1] Mandatory Tests', () {
      test('[FIX-FINANCIALS-NET-1] Test: ₹10,000 at 3%/month, 2 months elapsed, ₹600 paid, rate edited to 2%', () {
        // ₹10,000 at 3%/month, 2 months elapsed, ₹600 paid (all interest under 3% rate).
        // Rate is then edited to 2%:
        // -> totalInterest 400, outstandingInterest 0, outstandingPrincipal 10,000, totalDue 9,800, overpaymentAmount 0
        final editedRecord = LedgerRecord(
          id: 'rec-worked-ex',
          transactionId: 'TRAN092607',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 7, 20),
          principalAmount: 10000.0,
          interestRate: 2.0, // Edited down to 2%
          status: RecordStatus.ACTIVE,
          payments: [
            Payment(
              id: 'p-worked',
              recordId: 'rec-worked-ex',
              amount: 600.0,
              date: DateTime(2026, 9, 20),
              interestPaid: 600.0, // Paid under previous 3% rate
              principalPaid: 0.0,
            ),
          ],
        );

        final fin = calculateRecordFinancials(editedRecord, today);
        expect(fin.totalInterest, 400.0);
        expect(fin.outstandingInterest, 0.0);
        expect(fin.outstandingPrincipal, 10000.0);
        expect(fin.totalDue, 9800.0);
        expect(fin.overpaymentAmount, 0.0);
      });

      test('[FIX-FINANCIALS-NET-1] Test: payment set that exceeds principal + interest -> overpaymentAmount > 0 and totalDue 0', () {
        final overpaidRecord = LedgerRecord(
          id: 'rec-net-over',
          transactionId: 'TRAN092608',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 8, 20),
          principalAmount: 10000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          payments: [
            Payment(
              id: 'p-large',
              recordId: 'rec-net-over',
              amount: 11000.0, // Exceeds principal (10,000) + interest (200)
              date: DateTime(2026, 9, 20),
              interestPaid: 200.0,
              principalPaid: 10800.0,
            ),
          ],
        );

        final fin = calculateRecordFinancials(overpaidRecord, today);
        expect(fin.totalDue, 0.0);
        expect(fin.overpaymentAmount, 800.0);
      });

      test('[FIX-ACCRUAL-END-1] Test: endDate before targetDate accrues only to endDate, and after targetDate accrues to targetDate', () {
        // Case A: endDate before targetDate (2 months vs 5 months)
        final recEndBefore = LedgerRecord(
          id: 'rec-end-before',
          transactionId: 'TRAN092609',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 4, 20),
          endDate: DateTime(2026, 6, 20), // 2 months
          principalAmount: 10000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
        );
        final finBefore = calculateRecordFinancials(recEndBefore, today);
        expect(finBefore.totalInterest, 400.0); // Capped at 2 months

        // Case B: endDate after targetDate (future endDate)
        final recEndAfter = LedgerRecord(
          id: 'rec-end-after',
          transactionId: 'TRAN092610',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 7, 20),
          endDate: DateTime(2026, 12, 20), // Future endDate
          principalAmount: 10000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
        );
        final finAfter = calculateRecordFinancials(recEndAfter, today);
        expect(finAfter.totalInterest, 400.0); // Accrues to targetDate (2026-09-20 = 2 months)
      });
    });

    // =========================================================================
    // 3. computeRecordRisks() TESTS (a) THROUGH (h)
    // =========================================================================
    group('3. computeRecordRisks() Verification: Cases (a) through (h)', () {
      final rates = [
        ItemRate(
          id: 'r-gold',
          itemCategory: 'GOLD_22K',
          ratePerUnit: 6000.0,
          effectiveDate: today,
          updatedAt: today,
        ),
        ItemRate(
          id: 'r-zero',
          itemCategory: 'SILVER',
          ratePerUnit: 0.0, // rate of 0.0
          effectiveDate: today,
          updatedAt: today,
        ),
      ];

      test('(a) a record with no items raises no alert and gets a "No collateral" state', () {
        final recNoItems = LedgerRecord(
          id: 'rec-no-items',
          transactionId: 'TRAN092611',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 8, 20),
          principalAmount: 5000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          items: const [],
        );

        final risks = computeRecordRisks(records: [recNoItems], rates: rates, today: today);
        final risk = risks.first;
        expect(risk.hasCollateral, isFalse);
        expect(risk.collateralDrop, isFalse);
        expect(risk.overshoot, isFalse);
        expect(risk.atRisk, isFalse);

        final alerts = alertsFromRisks(risks);
        expect(alerts, isEmpty);
      });

      test('(b) an item whose category has no rate -> currentCollateralValue is null, RateMissing emitted, no CollateralDrop', () {
        final recMissingRate = LedgerRecord(
          id: 'rec-missing-rate',
          transactionId: 'TRAN092612',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 8, 20),
          principalAmount: 5000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          items: const [
            LedgerItem(
              id: 'i-plat',
              recordId: 'rec-missing-rate',
              name: 'Platinum Ring',
              itemCategory: 'PLATINUM', // No rate on file
              weight: 5.0,
              purity: 100.0,
              itemValue: 20000.0,
            ),
          ],
        );

        final risks = computeRecordRisks(records: [recMissingRate], rates: rates, today: today);
        final risk = risks.first;
        expect(risk.currentCollateralValue, isNull);
        expect(risk.missingRateCategories, contains('PLATINUM'));
        expect(risk.collateralDrop, isFalse);

        final alerts = alertsFromRisks(risks);
        expect(alerts.any((a) => a is RateMissing && a.itemCategory == 'PLATINUM'), isTrue);
        expect(alerts.any((a) => a is CollateralDrop), isFalse);
      });

      test('(c) a rate of 0.0 is treated exactly like a missing rate', () {
        final recZeroRate = LedgerRecord(
          id: 'rec-zero-rate',
          transactionId: 'TRAN092613',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 8, 20),
          principalAmount: 5000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          items: const [
            LedgerItem(
              id: 'i-sil',
              recordId: 'rec-zero-rate',
              name: 'Silver Bar',
              itemCategory: 'SILVER', // SILVER rate is 0.0
              weight: 50.0,
              purity: 100.0,
              itemValue: 5000.0,
            ),
          ],
        );

        final risks = computeRecordRisks(records: [recZeroRate], rates: rates, today: today);
        final risk = risks.first;
        expect(risk.currentCollateralValue, isNull);
        expect(risk.missingRateCategories, contains('SILVER'));
        expect(risk.collateralDrop, isFalse);

        final alerts = alertsFromRisks(risks);
        expect(alerts.any((a) => a is RateMissing && a.itemCategory == 'SILVER'), isTrue);
      });

      test('(d) with today = 20 Sep the projection date is 20 Nov, not 1 Nov', () {
        final projection = addMonths(today, 2);
        expect(projection.year, 2026);
        expect(projection.month, 11);
        expect(projection.day, 20);
      });

      test('(e) an endDate before the projection date caps the projected interest', () {
        // Today = 20 Sep 2026. Projection date = 20 Nov 2026 (+2 months).
        // Record endDate = 20 Oct 2026 (+1 month from today, +2 months from start).
        final recEndingBeforeProjection = LedgerRecord(
          id: 'rec-end-proj',
          transactionId: 'TRAN092614',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 8, 20),
          endDate: DateTime(2026, 10, 20),
          principalAmount: 10000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          items: const [
            LedgerItem(
              id: 'i-cap',
              recordId: 'rec-end-proj',
              name: 'Gold Ring',
              itemCategory: 'GOLD_22K',
              weight: 5.0,
              purity: 100.0,
              itemValue: 30000.0,
            ),
          ],
        );

        final risks = computeRecordRisks(records: [recEndingBeforeProjection], rates: rates, today: today);
        // Accrues only to 20 Oct 2026 = 2.0 months = 400 interest -> 10,400 projected due
        expect(risks.first.projectedOutstanding, 10400.0);
      });

      test('(f) a safe record is present in the list with atRisk == false', () {
        final recSafe = LedgerRecord(
          id: 'rec-safe',
          transactionId: 'TRAN092615',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 8, 20),
          principalAmount: 5000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          items: const [
            LedgerItem(
              id: 'i-safe',
              recordId: 'rec-safe',
              name: 'Heavy Gold',
              itemCategory: 'GOLD_22K',
              weight: 10.0, // 60,000 live value >> 5,100 totalDue
              purity: 100.0,
              itemValue: 50000.0, // 50,000 snapshot >> projected 5,300
            ),
          ],
        );

        final risks = computeRecordRisks(records: [recSafe], rates: rates, today: today);
        expect(risks.length, 1);
        final risk = risks.first;
        expect(risk.atRisk, isFalse);
        expect(risk.collateralDrop, isFalse);
        expect(risk.overshoot, isFalse);

        final alerts = alertsFromRisks(risks);
        expect(alerts, isEmpty);
      });

      test('(g) the five-group sort order strictly enforced', () {
        final recBoth = LedgerRecord(
          id: 'r-both',
          transactionId: 'TRAN092616',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2025, 1, 1),
          principalAmount: 10000.0,
          interestRate: 5.0,
          status: RecordStatus.ACTIVE,
          items: const [
            LedgerItem(
              id: 'i-b',
              recordId: 'r-both',
              name: 'Gold',
              itemCategory: 'GOLD_22K',
              weight: 1.0,
              purity: 100.0,
              itemValue: 8000.0,
            ),
          ],
        );

        final recOvershoot = LedgerRecord(
          id: 'r-overshoot',
          transactionId: 'TRAN092617',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2025, 9, 1),
          principalAmount: 10000.0,
          interestRate: 5.0,
          status: RecordStatus.ACTIVE,
          items: const [
            LedgerItem(
              id: 'i-o',
              recordId: 'r-overshoot',
              name: 'Gold',
              itemCategory: 'GOLD_22K',
              weight: 10.0,
              purity: 100.0,
              itemValue: 12000.0,
            ),
          ],
        );

        final recDrop = LedgerRecord(
          id: 'r-drop',
          transactionId: 'TRAN092618',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 8, 20),
          principalAmount: 10000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          items: const [
            LedgerItem(
              id: 'i-d',
              recordId: 'r-drop',
              name: 'Gold',
              itemCategory: 'GOLD_22K',
              weight: 1.5, // 9,000 live < 10,200 totalDue
              purity: 100.0,
              itemValue: 30000.0,
            ),
          ],
        );

        final recMissing = LedgerRecord(
          id: 'r-missing',
          transactionId: 'TRAN092619',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 8, 20),
          principalAmount: 5000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          items: const [
            LedgerItem(
              id: 'i-m',
              recordId: 'r-missing',
              name: 'Silver',
              itemCategory: 'SILVER', // rate 0.0 -> missing
              weight: 10.0,
              purity: 100.0,
              itemValue: 10000.0,
            ),
          ],
        );

        final recSafe = LedgerRecord(
          id: 'r-safe',
          transactionId: 'TRAN092620',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 8, 20),
          principalAmount: 1000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          items: const [
            LedgerItem(
              id: 'i-s',
              recordId: 'r-safe',
              name: 'Gold',
              itemCategory: 'GOLD_22K',
              weight: 5.0,
              purity: 100.0,
              itemValue: 30000.0,
            ),
          ],
        );

        final risks = computeRecordRisks(
          records: [recSafe, recMissing, recDrop, recOvershoot, recBoth],
          rates: rates,
          today: today,
        );

        expect(risks[0].record.id, 'r-both'); // Group 1
        expect(risks[1].record.id, 'r-overshoot'); // Group 2
        expect(risks[2].record.id, 'r-drop'); // Group 3
        expect(risks[3].record.id, 'r-missing'); // Group 4
        expect(risks[4].record.id, 'r-safe'); // Group 5
      });

      test('(h) the result is identical when today is injected, whatever the device clock says', () {
        final rec = LedgerRecord(
          id: 'r-clock',
          transactionId: 'TRAN092621',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 1, 1),
          principalAmount: 10000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          items: const [
            LedgerItem(
              id: 'i-c',
              recordId: 'r-clock',
              name: 'Gold',
              itemCategory: 'GOLD_22K',
              weight: 2.0,
              purity: 100.0,
              itemValue: 15000.0,
            ),
          ],
        );

        final r1 = computeRecordRisks(records: [rec], rates: rates, today: today);
        final r2 = computeRecordRisks(records: [rec], rates: rates, today: today);

        expect(r1.first.totalDue, r2.first.totalDue);
        expect(r1.first.projectedOutstanding, r2.first.projectedOutstanding);
        expect(r1.first.currentCollateralValue, r2.first.currentCollateralValue);
      });
    });

    // =========================================================================
    // 4. getMonthlyInterest CASH-BASIS RULE
    // =========================================================================
    group('4. getMonthlyInterest Cash-Basis Rule', () {
      test('Record with no payments contributes zero to monthly totals even if active for months', () {
        final activeLongTerm = LedgerRecord(
          id: 'rec-no-pay',
          transactionId: 'TRAN092622',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2025, 1, 1),
          principalAmount: 50000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          payments: const [],
        );

        final monthly = getMonthlyInterest([activeLongTerm]);
        expect(monthly, isEmpty);
      });
    });

    // =========================================================================
    // 5. [FIX-ARCH-PDFTEST-1] AUTOMATED ASSERTION TESTS
    // =========================================================================
    group('5. [FIX-ARCH-PDFTEST-1] Automated Drift Assertion Tests', () {
      test('getDashboard() and generateAllBorrowersReport() monetary totals match exactly', () {
        final cust1 = Customer(
          id: 'c-1',
          displayId: 'CUST26-27-01',
          name: 'Borrower One',
          phone: '9999999999',
          createdAt: DateTime(2026, 1, 1),
        );
        final cust2 = Customer(
          id: 'c-2',
          displayId: 'CUST26-27-02',
          name: 'Borrower Two',
          phone: '8888888888',
          createdAt: DateTime(2026, 2, 1),
        );

        final rec1 = LedgerRecord(
          id: 'rec-b-1',
          transactionId: 'TRAN092623',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 6, 20),
          principalAmount: 20000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          payments: [
            Payment(
              id: 'p-b-1',
              recordId: 'rec-b-1',
              amount: 500.0,
              date: DateTime(2026, 7, 20),
              interestPaid: 400.0,
              principalPaid: 100.0,
            ),
          ],
        );

        final rec2 = LedgerRecord(
          id: 'rec-b-2',
          transactionId: 'TRAN092624',
          type: RecordType.GIVEN,
          customerId: 'c-2',
          startDate: DateTime(2026, 7, 20),
          principalAmount: 15000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
          payments: const [],
        );

        final dashboard = CalculationEngine.getDashboard([rec1, rec2], today: today);
        final borrowersReport = generateAllBorrowersReport([cust1, cust2], [rec1, rec2], today);

        expect(borrowersReport.totalPrincipal, equals(dashboard.totalPrincipalGiven));
        expect(borrowersReport.totalInterestAccrued, equals(dashboard.totalInterestAccruedGiven));
        expect(borrowersReport.totalDue, equals(dashboard.totalDueGiven));
        expect(borrowersReport.totalActiveRecords, equals(2));
      });

      test('getDashboard() and generateAllLendersReport() monetary totals match exactly', () {
        final lender1 = Lender(
          id: 'l-1',
          displayId: 'LEND26-27-01',
          lenderType: LenderType.institution,
          name: 'Lender Capital',
          phone: '7777777777',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );
        final lender2 = Lender(
          id: 'l-2',
          displayId: 'LEND26-27-02',
          lenderType: LenderType.individual,
          name: 'Apex Finance',
          phone: '6666666666',
          createdAt: DateTime(2026, 2, 1),
          updatedAt: DateTime(2026, 2, 1),
        );

        final recTaken1 = LedgerRecord(
          id: 'rec-t-1',
          transactionId: 'TRAN092625',
          type: RecordType.TAKEN,
          lenderId: 'l-1',
          startDate: DateTime(2026, 6, 20),
          principalAmount: 50000.0,
          interestRate: 1.5,
          status: RecordStatus.ACTIVE,
          payments: [
            Payment(
              id: 'p-t-1',
              recordId: 'rec-t-1',
              amount: 1500.0,
              date: DateTime(2026, 7, 20),
              interestPaid: 750.0,
              principalPaid: 750.0,
            ),
          ],
        );

        final recTaken2 = LedgerRecord(
          id: 'rec-t-2',
          transactionId: 'TRAN092626',
          type: RecordType.TAKEN,
          lenderId: 'l-2',
          startDate: DateTime(2026, 7, 20),
          principalAmount: 30000.0,
          interestRate: 1.0,
          status: RecordStatus.ACTIVE,
          payments: const [],
        );

        final dashboard = CalculationEngine.getDashboard([recTaken1, recTaken2], today: today);
        final lendersReport = generateAllLendersReport([lender1, lender2], [recTaken1, recTaken2], today);

        expect(lendersReport.totalPrincipal, equals(dashboard.totalPrincipalTaken));
        expect(lendersReport.totalInterestAccrued, equals(dashboard.totalInterestAccruedTaken));
        expect(lendersReport.totalDue, equals(dashboard.totalDueTaken));
        expect(lendersReport.totalActiveRecords, equals(2));
      });
    });
  });
}
