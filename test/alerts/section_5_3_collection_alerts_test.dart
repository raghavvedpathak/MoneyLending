import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/calculations/calculations.dart';
import 'package:money_lending/domain/domain.dart';

void main() {
  group('Section 5.3 Collection Alerts & [FIX-ARCH-COLLALERT-1]', () {
    final today = DateTime(2026, 9, 23);
    final rates = [
      ItemRate(
        id: 'r-gold',
        itemCategory: 'GOLD_22K',
        ratePerUnit: 6000.0,
        effectiveDate: today,
        updatedAt: today,
      ),
      ItemRate(
        id: 'r-silver',
        itemCategory: 'SILVER',
        ratePerUnit: 80.0,
        effectiveDate: today,
        updatedAt: today,
      ),
      ItemRate(
        id: 'r-placeholder',
        itemCategory: 'PLATINUM',
        ratePerUnit: 0.0, // Unusable rate (placeholder)
        effectiveDate: today,
        updatedAt: today,
      ),
    ];

    test('1. CollectionAlert sealed class with CollateralDrop, RateMissing, OvershootWarning and RecordRisk', () {
      final rec = LedgerRecord(
        id: 'rec-1',
        transactionId: 'TRAN092601',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 8, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      final drop = CollateralDrop(
        record: rec,
        currentCollateralValue: 9000.0,
        totalDue: 10400.0,
      );
      expect(drop, isA<CollectionAlert>());
      expect(drop.record.id, 'rec-1');
      expect(drop.gap, 1400.0);

      final missing = RateMissing(
        record: rec,
        itemCategory: 'DIAMOND',
      );
      expect(missing, isA<CollectionAlert>());
      expect(missing.itemCategory, 'DIAMOND');

      final overshoot = OvershootWarning(
        record: rec,
        projectedOutstanding: 12000.0,
        itemValueAtLending: 10000.0,
      );
      expect(overshoot, isA<CollectionAlert>());
      expect(overshoot.gap, 2000.0);

      final risk = RecordRisk(
        record: rec,
        currentCollateralValue: null,
        missingRateCategories: {'DIAMOND'},
        totalDue: 10400.0,
        projectedOutstanding: 12000.0,
        itemValueAtLending: 10000.0,
      );
      expect(risk.hasCollateral, isFalse);
      expect(risk.collateralDrop, isFalse);
      expect(risk.overshoot, isFalse);
      expect(risk.atRisk, isFalse);
    });

    test('2. [FIX-RATE-USABLE-1] usableRate correctly distinguishes positive from <= 0 or missing rates', () {
      expect(usableRate(rates, 'GOLD_22K'), 6000.0);
      expect(usableRate(rates, 'SILVER'), 80.0);
      expect(usableRate(rates, 'PLATINUM'), isNull, reason: 'ratePerUnit <= 0 is unusable');
      expect(usableRate(rates, 'UNKNOWN'), isNull, reason: 'not on file');
    });

    test('3. [FIX-REMOVE-TOTALPAID-1] (v1.16) FULL record payments subtract automatically without totalPaidMap', () {
      // 10,000 principal at 2% monthly rate, started 2026-06-01.
      // Target date: 2026-09-23. Projection date: 2026-11-23 (today + 2 months).
      // Customer has already paid 5,000 principal on record.payments!
      final fullRecord = LedgerRecord(
        id: 'rec-full',
        transactionId: 'TRAN092602',
        type: RecordType.GIVEN,
        customerId: 'c-2',
        startDate: DateTime(2026, 6, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        payments: [
          Payment(
            id: 'p-1',
            recordId: 'rec-full',
            amount: 5000.0,
            date: DateTime(2026, 8, 1),
            interestPaid: 400.0,
            principalPaid: 4600.0,
          ),
        ],
        items: const [
          LedgerItem(
            id: 'i-1',
            recordId: 'rec-full',
            name: 'Gold Ring',
            itemCategory: 'GOLD_22K',
            weight: 3.0,
            purity: 100.0,
            itemValue: 8000.0,
          ),
        ],
      );

      // Call computeRecordRisks WITHOUT totalPaidMap:
      final risks = computeRecordRisks(
        records: [fullRecord],
        rates: rates,
        today: today,
      );

      expect(risks.length, 1);
      final risk = risks.first;
      // calculateRecordFinancials automatically subtracts 5,000 total paid.
      // Net projected due is significantly less than unadjusted 10,000 + interest.
      expect(risk.projectedOutstanding, lessThan(8000.0));
      // Since projectedOutstanding < itemValueAtLending (8000), overshoot is false!
      expect(risk.overshoot, isFalse);
    });

    test('4. [FIX-MONEY-1] liveItemValue and sumMoney guarantee exact currency precision for collateral', () {
      final rec = LedgerRecord(
        id: 'rec-money',
        transactionId: 'TRAN092603',
        type: RecordType.GIVEN,
        customerId: 'c-3',
        startDate: DateTime(2026, 9, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-1',
            recordId: 'rec-money',
            name: 'Item 1',
            itemCategory: 'GOLD_22K',
            weight: 1.234, // 1.234 * 1.0 * 6000 = 7404.0
            purity: 100.0,
            itemValue: 10000.0,
          ),
          LedgerItem(
            id: 'i-2',
            recordId: 'rec-money',
            name: 'Item 2',
            itemCategory: 'SILVER',
            weight: 12.5, // 12.5 * 1.0 * 80 = 1000.0
            purity: 100.0,
            itemValue: 2000.0,
          ),
        ],
      );

      final risks = computeRecordRisks(
        records: [rec],
        rates: rates,
        today: today,
      );

      expect(risks.first.currentCollateralValue, 8404.0);
    });

    test('5. [FIX-SORT-1] (Addendum J.9) Group 5 safe records sorted by startDate ascending, then numeric sequence of transactionId', () {
      // Record 1: Earlier date (2026-07-01) with higher transaction sequence
      final recEarlier = LedgerRecord(
        id: 'rec-earlier',
        transactionId: 'TRAN072699',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 7, 1),
        principalAmount: 1000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-e',
            recordId: 'rec-earlier',
            name: 'Gold',
            itemCategory: 'GOLD_22K',
            weight: 5.0,
            purity: 100.0,
            itemValue: 30000.0,
          ),
        ],
      );

      // Record 2: Later date (2026-09-01) with seq 99
      final recSeq99 = LedgerRecord(
        id: 'rec-99',
        transactionId: 'TRAN092699',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 9, 1),
        principalAmount: 1000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-99',
            recordId: 'rec-99',
            name: 'Gold',
            itemCategory: 'GOLD_22K',
            weight: 5.0,
            purity: 100.0,
            itemValue: 30000.0,
          ),
        ],
      );

      // Record 3: Same date (2026-09-01) with seq 100 — text sorting would put 'TRAN0926100' BEFORE 'TRAN092699', but numeric sequence puts 99 before 100!
      final recSeq100 = LedgerRecord(
        id: 'rec-100',
        transactionId: 'TRAN0926100',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 9, 1),
        principalAmount: 1000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-100',
            recordId: 'rec-100',
            name: 'Gold',
            itemCategory: 'GOLD_22K',
            weight: 5.0,
            purity: 100.0,
            itemValue: 30000.0,
          ),
        ],
      );

      final risks = computeRecordRisks(
        records: [recSeq100, recEarlier, recSeq99],
        rates: rates,
        today: today,
      );

      // Safe records order:
      // 1st: recEarlier (oldest startDate: 2026-07-01)
      expect(risks[0].record.id, 'rec-earlier');
      // 2nd: recSeq99 (2026-09-01, sequence 99)
      expect(risks[1].record.id, 'rec-99');
      // 3rd: recSeq100 (2026-09-01, sequence 100)
      expect(risks[2].record.id, 'rec-100');
    });

    test('6. Group 1: simultaneous triggers sorted by max(dropGap, overshootGap) descending', () {
      // Rec 1: drop gap = 12000 - 5000 = 7000; overshoot gap = 14000 - 6000 = 8000 -> maxGap = 8000
      final recA = LedgerRecord(
        id: 'rec-a',
        transactionId: 'TRAN092610',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2025, 1, 1),
        principalAmount: 10000.0,
        interestRate: 5.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-a',
            recordId: 'rec-a',
            name: 'Gold',
            itemCategory: 'GOLD_22K',
            weight: 1.0, // 6000 live collateral
            purity: 100.0,
            itemValue: 5000.0,
          ),
        ],
      );

      // Rec 2: higher max gap
      final recB = LedgerRecord(
        id: 'rec-b',
        transactionId: 'TRAN092611',
        type: RecordType.GIVEN,
        customerId: 'c-2',
        startDate: DateTime(2024, 1, 1),
        principalAmount: 20000.0,
        interestRate: 5.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-b',
            recordId: 'rec-b',
            name: 'Gold',
            itemCategory: 'GOLD_22K',
            weight: 1.0, // 6000 live collateral
            purity: 100.0,
            itemValue: 5000.0,
          ),
        ],
      );

      final risks = computeRecordRisks(
        records: [recA, recB],
        rates: rates,
        today: today,
      );

      expect(risks[0].record.id, 'rec-b');
      expect(risks[1].record.id, 'rec-a');
    });
  });
}
