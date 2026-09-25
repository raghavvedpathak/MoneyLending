import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/ui/formatters/currency_formatter.dart';

void main() {
  group('CurrencyFormatter tests [FIX-TEST-CURRENCY-1] & [FIX-MONEY-1]', () {
    test('formats exact spec examples: ₹154.32, ₹2,45,000.00, -₹500.00, ₹0.00', () {
      expect(formatCurrency(154.32), '₹154.32');
      expect(formatCurrency(245000.0), '₹2,45,000.00');
      expect(formatCurrency(-500.0), '-₹500.00');
      expect(formatCurrency(0.0), '₹0.00');
      expect(formatCurrency(1000), '₹1,000.00');
      expect(formatCurrency(100000), '₹1,00,000.00');
      expect(formatCurrency(1234567.89), '₹12,34,567.89');
    });

    test('roundMoney rounds half away from zero and never produces -0.0', () {
      expect(roundMoney(154.325), 154.33);
      expect(roundMoney(-154.325), -154.33);
      expect(roundMoney(154.324), 154.32);
      expect(roundMoney(-0.0), 0.0);
      expect(roundMoney(0.0), 0.0);
    });

    test('sumMoney re-rounds sum accurately', () {
      expect(sumMoney([0.1, 0.2]), 0.30);
      expect(sumMoney([100.05, 200.05]), 300.10);
    });

    test('parseMoney parses up to 2 decimal digits and rejects 3 decimals or negative', () {
      expect(parseMoney('154.32'), 154.32);
      expect(parseMoney('100'), 100.0);
      expect(parseMoney('0.5'), 0.5);
      expect(parseMoney('154.325'), isNull); // 3 decimals -> null
      expect(parseMoney('-500'), isNull); // negative -> null
      expect(parseMoney('abc'), isNull);
      expect(parseMoney(''), isNull);
    });

    test('formats compact amounts', () {
      expect(CurrencyFormatter.formatCompact(1500), '₹1.5K');
      expect(CurrencyFormatter.formatCompact(100000), '₹1L');
    });
  });
}
