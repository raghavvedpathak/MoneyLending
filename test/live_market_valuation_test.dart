import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/calculations/calculation_engine.dart';
import 'package:money_lending/domain/domain.dart';

void main() {
  group('Option A: Live Market Valuation vs Historical Lending Snapshot', () {
    const goldItem = LedgerItem(
      id: 'it-gold-1',
      recordId: 'rec-1',
      name: 'Gold Chain 22K',
      itemCategory: 'GOLD',
      weight: 10.0,
      purity: 91.6,
      rate: 6000.0, // Historical rate at lending time
      itemValue: 54960.0, // 10 * 0.916 * 6000 = 54,960.00
      lendPercentage: 75.0,
      lendableAmount: 41220.0,
    );

    const silverItem = LedgerItem(
      id: 'it-silver-1',
      recordId: 'rec-1',
      name: 'Silver Anklet',
      itemCategory: 'SILVER',
      weight: 50.0,
      purity: 92.5,
      rate: 80.0, // Historical rate at lending time
      itemValue: 3700.0, // 50 * 0.925 * 80 = 3,700.00
      lendPercentage: 70.0,
      lendableAmount: 2590.0,
    );

    test('Preserves historical lending snapshot unchanged', () {
      expect(CalculationEngine.calculateItemValue(goldItem), 54960.0);
      expect(CalculationEngine.calculateItemValue(silverItem), 3700.0);
      expect(
        CalculationEngine.calculateTotalItemValue([goldItem, silverItem]),
        58660.0,
      );
    });

    test('Computes live market valuation when rates increase', () {
      final currentRates = [
        ItemRate(
          id: 'rate-gold',
          itemCategory: 'GOLD',
          ratePerUnit: 7000.0, // Gold increased to 7,000/g
          effectiveDate: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ItemRate(
          id: 'rate-silver',
          itemCategory: 'SILVER',
          ratePerUnit: 90.0, // Silver increased to 90/g
          effectiveDate: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      // Live: 10 * 0.916 * 7000 = 64,120.00
      final liveGold = CalculationEngine.calculateLiveItemValue(goldItem, currentRates);
      expect(liveGold, 64120.0);

      // Live: 50 * 0.925 * 90 = 4,162.50
      final liveSilver = CalculationEngine.calculateLiveItemValue(silverItem, currentRates);
      expect(liveSilver, 4162.50);

      // Total live: 64,120 + 4,162.50 = 68,282.50
      final totalLive = CalculationEngine.calculateTotalLiveCollateralValue(
        [goldItem, silverItem],
        currentRates,
      );
      expect(totalLive, 68282.50);

      // Verify drift calculation
      final totalLending = CalculationEngine.calculateTotalItemValue([goldItem, silverItem]);
      final drift = totalLive - totalLending; // 68,282.50 - 58,660.00 = 9,622.50
      expect(drift, 9622.50);
      final driftPct = (drift / totalLending) * 100.0;
      expect(driftPct, closeTo(16.40, 0.01));
    });

    test('Computes live market valuation when rates decrease', () {
      final currentRates = [
        ItemRate(
          id: 'rate-gold-down',
          itemCategory: 'GOLD',
          ratePerUnit: 5500.0, // Gold decreased to 5,500/g
          effectiveDate: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      // Live: 10 * 0.916 * 5500 = 50,380.00
      final liveGold = CalculationEngine.calculateLiveItemValue(goldItem, currentRates);
      expect(liveGold, 50380.0);
      expect(liveGold < goldItem.itemValue, isTrue);
    });

    test('Falls back safely to historical snapshot when category has no live rate', () {
      const diamondItem = LedgerItem(
        id: 'it-dia-1',
        recordId: 'rec-2',
        name: 'Diamond Ring',
        itemCategory: 'DIAMOND',
        weight: 3.0,
        purity: 100.0,
        rate: 50000.0,
        itemValue: 150000.0,
      );

      final currentRates = [
        ItemRate(
          id: 'rate-gold',
          itemCategory: 'GOLD',
          ratePerUnit: 7000.0,
          effectiveDate: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      // No diamond rate in list -> falls back to snapshot
      final liveVal = CalculationEngine.calculateLiveItemValue(diamondItem, currentRates);
      expect(liveVal, 150000.0);
    });
  });
}
