import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/calculations/calculations.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:money_lending/features/dashboard/dashboard.dart';

void main() {
  group('CollectionAlert Sealed Hierarchy (§5.3 & [FIX-ARCH-COLLALERT-1])', () {
    test('1. Models hold required fields and compute gaps correctly', () {
      final record = LedgerRecord(
        id: 'rec-test',
        transactionId: 'TXN-000001',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      final drop = CollateralDrop(
        record: record,
        currentCollateralValue: 8000.0,
        totalDue: 10400.0,
      );
      expect(drop.gap, 2400.0);
      expect(drop.currentCollateralValue, 8000.0);
      expect(drop.totalDue, 10400.0);

      final rateMissing = RateMissing(
        record: LedgerRecord(
          id: 'rec-test',
          transactionId: 'TXN-000001',
          type: RecordType.GIVEN,
          customerId: 'c-1',
          startDate: DateTime(2026, 1, 1),
          principalAmount: 10000.0,
          interestRate: 2.0,
          status: RecordStatus.ACTIVE,
        ),
        itemCategory: 'DIAMOND',
      );
      expect(rateMissing.itemCategory, 'DIAMOND');

      final overshoot = OvershootWarning(
        record: record,
        projectedOutstanding: 12000.0,
        itemValueAtLending: 10000.0,
      );
      expect(overshoot.gap, 2000.0);
      expect(overshoot.projectedOutstanding, 12000.0);
      expect(overshoot.itemValueAtLending, 10000.0);
    });
  });

  group('computeCollectionAlerts Algorithm & 4-Group Sorting (§5.3)', () {
    final now = DateTime(2026, 5, 1);

    final rates = [
      ItemRate(
        id: 'rate-gold',
        itemCategory: 'GOLD_22K',
        ratePerUnit: 5000.0, // 5000 / g
        effectiveDate: now,
        updatedAt: now,
      ),
      ItemRate(
        id: 'rate-silver',
        itemCategory: 'SILVER',
        ratePerUnit: 70.0, // 70 / g
        effectiveDate: now,
        updatedAt: now,
      ),
    ];

    test('2. CollateralDrop triggered when live collateral <= totalDue (NOT principal)', () {
      // Loan: 10,000 principal at 2% for 4 months (Jan 1 to May 1)
      // Accrued interest = 800 -> totalDue = 10,800
      // Collateral at lending was 15,000 (3g 22k gold @ 5000 = 15,000)
      // But now gold rate is tested against drop: say collateral is 10,500
      // 10,500 is > 10,000 principal, BUT <= 10,800 totalDue!
      // This MUST trigger CollateralDrop (§5.3 requirement: test against totalDue, NOT principal)
      final recordExposedOnInterest = LedgerRecord(
        id: 'rec-exposed',
        transactionId: 'TXN-000010',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'item-1',
            recordId: 'rec-exposed',
            name: 'Gold Ring',
            itemCategory: 'GOLD_22K',
            weight: 2.1, // 2.1g * 100% * 5000 = 10,500 live value
            purity: 100.0,
            itemValue: 15000.0, // value at lending was 15,000
          ),
        ],
      );

      final alerts = computeCollectionAlerts(
        records: [recordExposedOnInterest],
        rates: rates,
        today: now,
      );
      expect(alerts.any((a) => a is CollateralDrop), isTrue);

      final dropAlert = alerts.firstWhere((a) => a is CollateralDrop) as CollateralDrop;
      expect(dropAlert.currentCollateralValue, 10500.0);
      expect(dropAlert.totalDue, 10800.0);
      expect(dropAlert.gap, 300.0);
    });

    test('3. RateMissing alert excludes unpriced item from collateral sum rather than zeroing silently', () {
      final recordWithUnknownItem = LedgerRecord(
        id: 'rec-rate-missing',
        transactionId: 'TXN-000011',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 4, 1),
        principalAmount: 5000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'item-gold',
            recordId: 'rec-rate-missing',
            name: 'Gold Ring',
            itemCategory: 'GOLD_22K',
            weight: 2.0, // 2g * 5000 = 10,000
            purity: 100.0,
            itemValue: 10000.0,
          ),
          LedgerItem(
            id: 'item-ruby',
            recordId: 'rec-rate-missing',
            name: 'Ruby Gem',
            itemCategory: 'RUBY_UNLISTED', // NO RATE ON FILE
            weight: 10.0,
            purity: 100.0,
            itemValue: 20000.0,
          ),
        ],
      );

      final alerts = computeCollectionAlerts(
        records: [recordWithUnknownItem],
        rates: rates,
        today: now,
      );
      final rateMissing = alerts.whereType<RateMissing>().toList();
      expect(rateMissing.length, 1);
      expect(rateMissing.first.itemCategory, 'RUBY_UNLISTED');
    });

    test('4. OvershootWarning triggered when 2-month projected outstanding > itemValueAtLending', () {
      // 10,000 principal at 5% monthly rate taken 8 months ago.
      // Projected interest in 2 months (10 months total) = 10 * 500 = 5,000
      // Projected outstanding = 15,000.
      // Collateral at lending was only 12,000.
      // 15,000 > 12,000 -> OvershootWarning triggers!
      final recordOvershooting = LedgerRecord(
        id: 'rec-overshoot',
        transactionId: 'TXN-000012',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2025, 9, 1),
        principalAmount: 10000.0,
        interestRate: 5.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'item-gold-large',
            recordId: 'rec-overshoot',
            name: 'Gold Bar',
            itemCategory: 'GOLD_22K',
            weight: 5.0, // 25,000 current value (so NO collateral drop)
            purity: 100.0,
            itemValue: 12000.0, // Snapshot at lending was 12,000
          ),
        ],
      );

      final alerts = computeCollectionAlerts(
        records: [recordOvershooting],
        rates: rates,
        today: now,
      );
      final overshootAlerts = alerts.whereType<OvershootWarning>().toList();
      expect(overshootAlerts.length, 1);
      expect(overshootAlerts.first.projectedOutstanding, 15000.0);
      expect(overshootAlerts.first.itemValueAtLending, 12000.0);
      expect(overshootAlerts.first.gap, 3000.0);
    });

    test('5. Authoritative 4-group sort order strictly enforced (§5.3)', () {
      // 1. Rec A: BOTH Overshoot and CollateralDrop (Group 1)
      final recBoth = LedgerRecord(
        id: 'rec-both',
        transactionId: 'TXN-000001',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2025, 1, 1),
        principalAmount: 10000.0,
        interestRate: 5.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-both',
            recordId: 'rec-both',
            name: 'Gold Chain',
            itemCategory: 'GOLD_22K',
            weight: 1.0, // 5000 current collateral (drop gap = 18000 - 5000 = 13000)
            purity: 100.0,
            itemValue: 6000.0, // overshoot gap = 19000 - 6000 = 13000
          ),
        ],
      );

      // 2. Rec B: Overshoot Only (Group 2)
      final recOvershootOnly = LedgerRecord(
        id: 'rec-overshoot-only',
        transactionId: 'TXN-000002',
        type: RecordType.GIVEN,
        customerId: 'c-2',
        startDate: DateTime(2025, 9, 1),
        principalAmount: 10000.0,
        interestRate: 5.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-over',
            recordId: 'rec-overshoot-only',
            name: 'Heavy Gold',
            itemCategory: 'GOLD_22K',
            weight: 10.0, // 50,000 collateral (NO drop)
            purity: 100.0,
            itemValue: 12000.0, // overshoot gap = 15000 - 12000 = 3000
          ),
        ],
      );

      // 3. Rec C: Collateral Drop Only (Group 3)
      final recDropOnly = LedgerRecord(
        id: 'rec-drop-only',
        transactionId: 'TXN-000003',
        type: RecordType.GIVEN,
        customerId: 'c-3',
        startDate: DateTime(2026, 4, 1), // only 1 month old (NO overshoot)
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-drop',
            recordId: 'rec-drop-only',
            name: 'Silver plate',
            itemCategory: 'SILVER',
            weight: 100.0, // 7000 live collateral (totalDue = 10,200 -> drop gap = 3200)
            purity: 100.0,
            itemValue: 15000.0,
          ),
        ],
      );

      // 4. Rec D: RateMissing only (Group 4)
      final recMissingOnly = LedgerRecord(
        id: 'rec-missing-only',
        transactionId: 'TXN-000004',
        type: RecordType.GIVEN,
        customerId: 'c-4',
        startDate: DateTime(2026, 4, 1),
        principalAmount: 1000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-missing',
            recordId: 'rec-missing-only',
            name: 'Rare Pearl',
            itemCategory: 'PEARL_UNLISTED',
            itemValue: 5000.0,
          ),
        ],
      );

      // 5. Rec Safe: No alerts
      final recSafe = LedgerRecord(
        id: 'rec-safe',
        transactionId: 'TXN-000005',
        type: RecordType.GIVEN,
        customerId: 'c-5',
        startDate: DateTime(2026, 4, 1),
        principalAmount: 1000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-safe',
            recordId: 'rec-safe',
            name: 'Gold Ring',
            itemCategory: 'GOLD_22K',
            weight: 5.0, // 25,000 collateral >> 1020 totalDue
            purity: 100.0,
            itemValue: 25000.0,
          ),
        ],
      );

      final alerts = computeCollectionAlerts(
        records: [recSafe, recMissingOnly, recDropOnly, recOvershootOnly, recBoth],
        rates: rates,
        today: now,
      );

      // Verify safe record is NOT included in alert list
      expect(alerts.any((a) => a.record.id == 'rec-safe'), isFalse);

      // Authoritative order:
      // Group 1 (rec-both) comes FIRST
      expect(alerts[0].record.id, 'rec-both');
      expect(alerts[1].record.id, 'rec-both');

      // Group 2 (rec-overshoot-only) comes SECOND
      expect(alerts[2], isA<OvershootWarning>());
      expect(alerts[2].record.id, 'rec-overshoot-only');

      // Group 3 (rec-drop-only) comes THIRD
      expect(alerts[3], isA<CollateralDrop>());
      expect(alerts[3].record.id, 'rec-drop-only');

      // Group 4 (rec-missing-only) comes LAST
      expect(alerts[4], isA<RateMissing>());
      expect(alerts[4].record.id, 'rec-missing-only');
    });

    test('6. [FIX-COLLALERT-TOTALPAID-1] Real totalPaidMap prevents false overshoot warnings', () {
      // Record has high accrued interest, but customer already paid 8,000!
      final recordWithBigPayments = LedgerRecord(
        id: 'rec-paid-customer',
        transactionId: 'TXN-000020',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2025, 9, 1),
        principalAmount: 10000.0,
        interestRate: 5.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-1',
            recordId: 'rec-paid-customer',
            name: 'Gold Bar',
            itemCategory: 'GOLD_22K',
            weight: 10.0,
            purity: 100.0,
            itemValue: 12000.0,
          ),
        ],
      );

      // Case A: Default empty map -> treats totalPaid as 0 -> falsely triggers OvershootWarning!
      final falseAlerts = computeCollectionAlerts(
        records: [recordWithBigPayments],
        rates: rates,
        today: now,
      );
      expect(falseAlerts.any((a) => a is OvershootWarning), isTrue);

      // Case B: Real totalPaidMap with 8000 paid -> projected outstanding = 15000 - 8000 = 7000 <= 12000 -> NO overshoot!
      final trueAlerts = computeCollectionAlerts(
        records: [recordWithBigPayments],
        rates: rates,
        totalPaidMap: {'rec-paid-customer': 8000.0},
        today: now,
      );
      expect(trueAlerts.any((a) => a is OvershootWarning), isFalse);
    });
  });

  group('RecordRisk and computeRecordRisks 5-group sorting ([FIX-RISK-VIEWMODEL-1] & [FIX-RATE-USABLE-1])', () {
    final testDate = DateTime(2026, 6, 1);
    final testRates = [
      ItemRate(
        id: 'r-1',
        itemCategory: 'GOLD_22K',
        ratePerUnit: 5000.0,
        effectiveDate: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      ItemRate(
        id: 'r-2',
        itemCategory: 'SILVER',
        ratePerUnit: 0.0, // [FIX-RATE-USABLE-1] Unpriced category placeholder
        effectiveDate: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    ];

    test('usableRate returns positive rates and returns null for missing or zero/negative rates', () {
      expect(usableRate(testRates, 'GOLD_22K'), 5000.0);
      expect(usableRate(testRates, 'gold_22k'), 5000.0);
      expect(usableRate(testRates, ' SILVER '), isNull, reason: 'ratePerUnit == 0.0 is not usable');
      expect(usableRate(testRates, 'DIAMOND'), isNull, reason: 'category not found');
    });

    test('RecordRisk calculates getters correctly and flags atRisk', () {
      final rec = LedgerRecord(
        id: 'rec-test',
        transactionId: 'TXN-001',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-1',
            recordId: 'rec-test',
            name: 'Gold Ring',
            itemCategory: 'GOLD_22K',
            weight: 2.0,
            purity: 100.0,
            itemValue: 12000.0,
          ),
        ],
      );

      final riskDrop = RecordRisk(
        record: rec,
        currentCollateralValue: 9000.0,
        missingRateCategories: const {},
        totalDue: 10000.0,
        projectedOutstanding: 10500.0,
        itemValueAtLending: 12000.0,
      );
      expect(riskDrop.hasCollateral, isTrue);
      expect(riskDrop.collateralDrop, isTrue);
      expect(riskDrop.overshoot, isFalse);
      expect(riskDrop.atRisk, isTrue);

      final riskOvershoot = RecordRisk(
        record: rec,
        currentCollateralValue: 15000.0,
        missingRateCategories: const {},
        totalDue: 10000.0,
        projectedOutstanding: 13000.0,
        itemValueAtLending: 12000.0,
      );
      expect(riskOvershoot.collateralDrop, isFalse);
      expect(riskOvershoot.overshoot, isTrue);
      expect(riskOvershoot.atRisk, isTrue);

      final riskSafe = RecordRisk(
        record: rec,
        currentCollateralValue: 15000.0,
        missingRateCategories: const {},
        totalDue: 10000.0,
        projectedOutstanding: 11000.0,
        itemValueAtLending: 12000.0,
      );
      expect(riskSafe.collateralDrop, isFalse);
      expect(riskSafe.overshoot, isFalse);
      expect(riskSafe.atRisk, isFalse);
    });

    test('computeRecordRisks produces authoritative 5-group sort order and alertsFromRisks projects it', () {
      // 1. recBoth: Group 1 (both drop and overshoot)
      final recBoth = LedgerRecord(
        id: 'rec-both',
        transactionId: 'TXN-001',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2025, 1, 1),
        principalAmount: 10000.0,
        interestRate: 5.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-both',
            recordId: 'rec-both',
            name: 'Gold Ring',
            itemCategory: 'GOLD_22K',
            weight: 1.5, // 1.5 * 5000 = 7500 < totalDue (~18500) -> drop
            purity: 100.0,
            itemValue: 8000.0, // projected > itemValue -> overshoot
          ),
        ],
      );

      // 2. recOvershoot: Group 2 (overshoot only, no drop)
      final recOvershoot = LedgerRecord(
        id: 'rec-overshoot',
        transactionId: 'TXN-002',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2025, 9, 1),
        principalAmount: 10000.0,
        interestRate: 5.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-overshoot',
            recordId: 'rec-overshoot',
            name: 'Gold Bar',
            itemCategory: 'GOLD_22K',
            weight: 5.0, // 25,000 live value (no drop)
            purity: 100.0,
            itemValue: 12000.0, // projected 15000 > 12000 -> overshoot
          ),
        ],
      );

      // 3. recDrop: Group 3 (drop only, no overshoot)
      final recDrop = LedgerRecord(
        id: 'rec-drop',
        transactionId: 'TXN-003',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 4, 1),
        principalAmount: 10000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-drop',
            recordId: 'rec-drop',
            name: 'Gold Item',
            itemCategory: 'GOLD_22K',
            weight: 2.0, // 10,000 live value < 10,400 totalDue -> drop
            purity: 100.0,
            itemValue: 20000.0, // 20,000 > projected (~10800) -> no overshoot
          ),
        ],
      );

      // 4. recMissingRate: Group 4 (missing rate category)
      final recMissingRate = LedgerRecord(
        id: 'rec-missing',
        transactionId: 'TXN-004',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 5, 1),
        principalAmount: 5000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-missing',
            recordId: 'rec-missing',
            name: 'Silver Coin',
            itemCategory: 'SILVER', // rate is 0.0 -> usableRate returns null
            weight: 10.0,
            purity: 100.0,
            itemValue: 10000.0,
          ),
        ],
      );

      // 5. recSafeB & recSafeA: Group 5 (safe records ordered by transactionId)
      final recSafeB = LedgerRecord(
        id: 'rec-safe-b',
        transactionId: 'TXN-010',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 5, 1),
        principalAmount: 5000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-safe-b',
            recordId: 'rec-safe-b',
            name: 'Gold Coin',
            itemCategory: 'GOLD_22K',
            weight: 10.0,
            purity: 100.0,
            itemValue: 60000.0,
          ),
        ],
      );

      final recSafeA = LedgerRecord(
        id: 'rec-safe-a',
        transactionId: 'TXN-005',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 5, 1),
        principalAmount: 5000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
        items: const [
          LedgerItem(
            id: 'i-safe-a',
            recordId: 'rec-safe-a',
            name: 'Gold Coin',
            itemCategory: 'GOLD_22K',
            weight: 10.0,
            purity: 100.0,
            itemValue: 60000.0,
          ),
        ],
      );

      final risks = computeRecordRisks(
        records: [recSafeB, recMissingRate, recDrop, recOvershoot, recBoth, recSafeA],
        rates: testRates,
        today: testDate,
      );

      expect(risks.length, 6);
      // Group 1: recBoth
      expect(risks[0].record.id, 'rec-both');
      // Group 2: recOvershoot
      expect(risks[1].record.id, 'rec-overshoot');
      // Group 3: recDrop
      expect(risks[2].record.id, 'rec-drop');
      // Group 4: recMissing (currentCollateralValue is null)
      expect(risks[3].record.id, 'rec-missing');
      expect(risks[3].currentCollateralValue, isNull);
      expect(risks[3].missingRateCategories, contains('SILVER'));
      // Group 5: Safe records sorted by transactionId (TXN-005 before TXN-010)
      expect(risks[4].record.id, 'rec-safe-a');
      expect(risks[5].record.id, 'rec-safe-b');

      final alerts = alertsFromRisks(risks);
      // Safe records omitted from alerts
      expect(alerts.any((a) => a.record.id == 'rec-safe-a'), isFalse);
      expect(alerts.any((a) => a.record.id == 'rec-safe-b'), isFalse);
      // Missing rate alert present
      expect(alerts.any((a) => a is RateMissing && a.record.id == 'rec-missing'), isTrue);
    });
  });

  group('DashboardViewModel Combine Pipeline ([FIX-DEV-DEBOUNCE-1] & H-4 FIX)', () {
    test('7. alertsLoaded is false initially and flips to true upon first emission (H-4 FIX)', () async {
      final recordsController = StreamController<List<LedgerRecord>>.broadcast();
      final ratesController = StreamController<List<ItemRate>>.broadcast();
      final totalsController = StreamController<List<RecordPaymentTotal>>.broadcast();

      final fakeRecordRepo = _FakeRecordRepo(
        activeGivenRecordsStream: recordsController.stream,
        totalPaidStream: totalsController.stream,
      );
      final fakeRateRepo = _FakeRateRepo(
        ratesStream: ratesController.stream,
      );

      final viewModel = DashboardViewModel(
        recordRepository: fakeRecordRepo,
        itemRateRepository: fakeRateRepo,
        debounceDuration: const Duration(milliseconds: 10), // short debounce for test
      );

      expect(viewModel.isAlertsLoaded, isFalse, reason: 'H-4 FIX: Must not be loaded initially');

      final emittedAlerts = <List<CollectionAlert>>[];
      final loadedEvents = <bool>[];

      viewModel.collectionAlerts.listen(emittedAlerts.add);
      viewModel.alertsLoaded.listen(loadedEvents.add);

      // Emit inputs
      recordsController.add([]);
      totalsController.add([]);
      ratesController.add([]);

      // Wait for 10ms debounce to fire
      await Future.delayed(const Duration(milliseconds: 50));

      expect(viewModel.isAlertsLoaded, isTrue, reason: 'H-4 FIX: Flips to true after first emission');
      expect(loadedEvents, [true]);
      expect(emittedAlerts.length, 1);

      viewModel.dispose();
      await recordsController.close();
      await ratesController.close();
      await totalsController.close();
    });

    test('8. Stream debounce absorbs rapid edits within debounce window ([FIX-DEV-DEBOUNCE-1])', () async {
      final ratesController = StreamController<List<ItemRate>>.broadcast();
      final debouncedStream = ratesController.stream.debounce(const Duration(milliseconds: 50));

      final emitted = <List<ItemRate>>[];
      final sub = debouncedStream.listen(emitted.add);

      final rate1 = [ItemRate(id: '1', itemCategory: 'G', ratePerUnit: 100, effectiveDate: DateTime.now(), updatedAt: DateTime.now())];
      final rate2 = [ItemRate(id: '1', itemCategory: 'G', ratePerUnit: 200, effectiveDate: DateTime.now(), updatedAt: DateTime.now())];
      final rate3 = [ItemRate(id: '1', itemCategory: 'G', ratePerUnit: 300, effectiveDate: DateTime.now(), updatedAt: DateTime.now())];

      // Rapid keystrokes within 20ms of each other
      ratesController.add(rate1);
      await Future.delayed(const Duration(milliseconds: 10));
      ratesController.add(rate2);
      await Future.delayed(const Duration(milliseconds: 10));
      ratesController.add(rate3);

      // Wait for debounce period (50ms) to elapse
      await Future.delayed(const Duration(milliseconds: 80));

      // Only the last value (rate3) should have been emitted!
      expect(emitted.length, 1);
      expect(emitted.first.first.ratePerUnit, 300);

      await sub.cancel();
      await ratesController.close();
    });
  });
}

class _FakeRecordRepo implements RecordRepository {
  final Stream<List<LedgerRecord>> activeGivenRecordsStream;
  final Stream<List<RecordPaymentTotal>> totalPaidStream;

  _FakeRecordRepo({
    required this.activeGivenRecordsStream,
    required this.totalPaidStream,
  });

  @override
  Stream<List<LedgerRecord>> getActiveGivenRecords() => activeGivenRecordsStream;

  @override
  Stream<List<RecordPaymentTotal>> getTotalPaidFlow() => totalPaidStream;

  @override
  Stream<List<RecordPaymentTotal>> watchTotalPaidFlow() => totalPaidStream;

  @override
  Future<void> addPayment(Payment payment) => throw UnimplementedError();
  @override
  Future<void> deleteRecord(String id) => throw UnimplementedError();
  @override
  Future<void> forceDeleteRecord(String id) => throw UnimplementedError();
  @override
  Future<Map<String, DateTime?>> getActiveRecordLastActivityMap() => throw UnimplementedError();
  @override
  Stream<List<LedgerRecord>> getAllActiveRecords() => throw UnimplementedError();
  @override
  Future<List<LedgerRecord>> getAllActiveRecordsOnce() async => [];
  @override
  Future<List<LedgerRecord>> getAllRecordsOnce() async => [];
  @override
  Future<void> refresh() async {}
  @override
  Future<LedgerRecord?> getRecordById(String id) => throw UnimplementedError();
  @override
  Stream<List<LedgerRecord>> getRecordsByCustomer(String customerId) => throw UnimplementedError();
  @override
  Future<List<RecordPaymentTotal>> getTotalPaidByRecordIds(List<String> recordIds) => throw UnimplementedError();
  @override
  Future<void> importRecordsTransactionally(List<LedgerRecord> records) => throw UnimplementedError();
  @override
  Future<void> restoreBackupTransactionally({
    required List<Map<String, dynamic>> customers,
    required List<Map<String, dynamic>> records,
    required List<Map<String, dynamic>> ledgerItems,
    required List<Map<String, dynamic>> payments,
    List<Map<String, dynamic>> retiredIds = const [],
  }) => throw UnimplementedError();
  @override
  Future<LedgerRecord> insertRecord(LedgerRecord record) => throw UnimplementedError();
  @override
  Future<void> settleRecord(String id, double calculatedInterest) => throw UnimplementedError();
  @override
  Future<void> updateRecord(LedgerRecord record) => throw UnimplementedError();
}

class _FakeRateRepo implements ItemRateRepository {
  final Stream<List<ItemRate>> ratesStream;

  _FakeRateRepo({required this.ratesStream});

  @override
  Stream<List<ItemRate>> getCurrentRates() => ratesStream;

  @override
  Stream<List<ItemRate>> watchCurrentRates() => ratesStream;

  @override
  Stream<ItemRate?> watchCurrentRate(String category) => throw UnimplementedError();

  @override
  Stream<List<ItemRate>> watchRatesForDate(DateTime date) => throw UnimplementedError();

  @override
  Stream<ItemRate?> getCurrentRate(String category) => throw UnimplementedError();
  @override
  Future<ItemRate?> getCurrentRateOnce(String category) => throw UnimplementedError();
  @override
  Future<List<ItemRate>> getCurrentRatesOnce() => throw UnimplementedError();
  @override
  Stream<List<ItemRate>> getRatesForDate(String date) => throw UnimplementedError();
  @override
  Future<List<ItemRate>> getRatesForDateOnce(String date) => throw UnimplementedError();
  @override
  Stream<List<ItemRate>> getRatesStream() => ratesStream;
  @override
  Future<void> upsertRate(ItemRate rate) => throw UnimplementedError();
}
