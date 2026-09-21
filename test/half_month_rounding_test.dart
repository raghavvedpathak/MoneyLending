import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/calculations/calculations.dart';

void main() {
  group('Half-Month Rounding Logic & Safe Date Tests (§5.2)', () {
    // -------------------------------------------------------------------------
    // 10 MANDATORY UNIT TESTS FOR getMonthsBetween
    // -------------------------------------------------------------------------
    test('1. Jan-31 -> Mar-5 gives 1.5 (rollover: dayDiff=-26, adjustedDays=2)', () {
      final start = DateTime(2026, 1, 31);
      final end = DateTime(2026, 3, 5);
      expect(getMonthsBetween(start, end), 1.5);
    });

    test('2. Jan-1 -> Jan-1 gives 0.0 (same-day, dayDiff=0)', () {
      final start = DateTime(2026, 1, 1);
      final end = DateTime(2026, 1, 1);
      expect(getMonthsBetween(start, end), 0.0);
    });

    test('3. Jan-1 -> Jan-16 gives 0.5 (positive branch: dayDiff=15, fails >15, passes >0)', () {
      final start = DateTime(2026, 1, 1);
      final end = DateTime(2026, 1, 16);
      expect(getMonthsBetween(start, end), 0.5);
    });

    test('4. Jan-1 -> Jan-17 gives 1.0 (positive branch, dayDiff=16, >15)', () {
      final start = DateTime(2026, 1, 1);
      final end = DateTime(2026, 1, 17);
      expect(getMonthsBetween(start, end), 1.0);
    });

    test('5. Jan-1 -> Feb-1 gives 1.0 (positive branch, dayDiff=0 after month increment)', () {
      final start = DateTime(2026, 1, 1);
      final end = DateTime(2026, 2, 1);
      expect(getMonthsBetween(start, end), 1.0);
    });

    test('6. Jan-31 -> Feb-28 gives 1.0 (rollover: dayDiff=-3, adjustedDays=28, 28>15)', () {
      final start = DateTime(2026, 1, 31);
      final end = DateTime(2026, 2, 28);
      expect(getMonthsBetween(start, end), 1.0);
    });

    test('7. Dec-15 -> Jan-1 gives 1.0 (cross-year rollover: dayDiff=-14, adjustedDays=17, 17>15)', () {
      final start = DateTime(2025, 12, 15);
      final end = DateTime(2026, 1, 1);
      expect(getMonthsBetween(start, end), 1.0);
    });

    test('8. Jan-1 -> Jan-1 next year gives 12.0 (full year, dayDiff=0)', () {
      final start = DateTime(2025, 1, 1);
      final end = DateTime(2026, 1, 1);
      expect(getMonthsBetween(start, end), 12.0);
    });

    test('9. Mar-5 -> Mar-5 gives 0.0 (same-day, same month)', () {
      final start = DateTime(2026, 3, 5);
      final end = DateTime(2026, 3, 5);
      expect(getMonthsBetween(start, end), 0.0);
    });

    test('10. Jan-15 -> Jan-1 gives 0.0 (end before start — maxOf(0.0, ...) floor)', () {
      final start = DateTime(2026, 1, 15);
      final end = DateTime(2026, 1, 1);
      expect(getMonthsBetween(start, end), 0.0);
    });

    // -------------------------------------------------------------------------
    // toSafePastDate() TESTS [FIX-DEV-SAFEDATE-1]
    // -------------------------------------------------------------------------
    test('toSafePastDate parses valid past ISO string', () {
      final ref = DateTime(2026, 9, 11);
      final result = '2026-04-10'.toSafePastDate(ref);
      expect(result, isNotNull);
      expect(result!.year, 2026);
      expect(result.month, 4);
      expect(result.day, 10);
    });

    test('toSafePastDate returns null for null or blank string', () {
      final ref = DateTime(2026, 9, 11);
      expect((null as String?).toSafePastDate(ref), isNull);
      expect(''.toSafePastDate(ref), isNull);
      expect('   '.toSafePastDate(ref), isNull);
    });

    test('toSafePastDate returns null for invalid format', () {
      final ref = DateTime(2026, 9, 11);
      expect('invalid-date'.toSafePastDate(ref), isNull);
    });

    test('toSafePastDate returns null for future dates', () {
      final ref = DateTime(2026, 9, 11);
      expect('2026-09-12'.toSafePastDate(ref), isNull);
      expect('2027-01-01'.toSafePastDate(ref), isNull);
    });

    test('toSafePastDate on DateTime returns null for future date and date-only for past date', () {
      final ref = DateTime(2026, 9, 11);
      final past = DateTime(2026, 4, 10, 15, 30);
      final future = DateTime(2026, 9, 12, 10, 00);

      expect(past.toSafePastDate(ref), DateTime(2026, 4, 10));
      expect(future.toSafePastDate(ref), isNull);
      expect((null as DateTime?).toSafePastDate(ref), isNull);
    });

    // -------------------------------------------------------------------------
    // addMonths() TESTS [FIX-ADDMONTHS-1]
    // -------------------------------------------------------------------------
    group('[FIX-ADDMONTHS-1] addMonths()', () {
      test('2026-09-20 + 2 -> 2026-11-20', () {
        final result = addMonths(DateTime(2026, 9, 20), 2);
        expect(result, DateTime(2026, 11, 20));
      });

      test('2026-12-31 + 2 -> 2027-02-28 (common year clamping)', () {
        final result = addMonths(DateTime(2026, 12, 31), 2);
        expect(result, DateTime(2027, 2, 28));
      });

      test('2027-12-31 + 2 -> 2028-02-29 (leap year clamping)', () {
        final result = addMonths(DateTime(2027, 12, 31), 2);
        expect(result, DateTime(2028, 2, 29));
      });

      test('2026-01-31 + 1 -> 2026-02-28', () {
        final result = addMonths(DateTime(2026, 1, 31), 1);
        expect(result, DateTime(2026, 2, 28));
      });

      test('2026-03-15 + (-4) -> 2025-11-15 (negative floor division)', () {
        final result = addMonths(DateTime(2026, 3, 15), -4);
        expect(result, DateTime(2025, 11, 15));
      });
    });
  });
}

