import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/ui/formatters/currency_formatter.dart';

void main() {
  group('CurrencyFormatter tests [FIX-TEST-CURRENCY-1]', () {
    test('formats positive amounts with en_IN locale', () {
      expect(formatCurrency(1000), '₹1,000.00');
      expect(formatCurrency(100000), '₹1,00,000.00');
      expect(formatCurrency(1234567.89), '₹12,34,567.89');
    });

    test('formats zero amount', () {
      expect(formatCurrency(0), '₹0.00');
    });

    test('formats negative amounts', () {
      // In Dart intl en_IN, negative format is -₹500.00 or ₹-500.00
      final formattedNegative = formatCurrency(-500);
      expect(formattedNegative.contains('500.00'), isTrue);
      expect(formattedNegative.contains('₹'), isTrue);
      expect(formattedNegative.contains('-'), isTrue);
    });

    test('formats compact amounts', () {
      expect(CurrencyFormatter.formatCompact(1500), '₹1.5K');
      expect(CurrencyFormatter.formatCompact(100000), '₹1L');
    });
  });
}
