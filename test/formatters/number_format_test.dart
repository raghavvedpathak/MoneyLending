import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/domain/util/number_format.dart';

void main() {
  group('NumberFormat tests [FIX-NUMFORMAT-1]', () {
    test('formatWeight formats grams with at most 3 decimals and trailing zeros trimmed', () {
      expect(formatWeight(5), '5');
      expect(formatWeight(4.5), '4.5');
      expect(formatWeight(4.125), '4.125');
      expect(formatWeight(0), '0');
      expect(formatWeight(10.0), '10');
      expect(formatWeight(10.500), '10.5');
      expect(formatWeight(10.25), '10.25');
    });

    test('formatRate formats percentage with at most 2 decimals and trailing zeros trimmed', () {
      expect(formatRate(2.5), '2.5');
      expect(formatRate(2), '2');
      expect(formatRate(92.5), '92.5');
      expect(formatRate(0), '0');
      expect(formatRate(18.0), '18');
      expect(formatRate(18.75), '18.75');
      expect(formatRate(18.756), '18.76');
    });
  });
}
