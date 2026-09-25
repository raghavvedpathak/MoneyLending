import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/calculations/calculations.dart';
import 'package:money_lending/domain/domain.dart';

void main() {
  group('java.time ChronoUnit.DAYS.between Equivalent Tests (§5.2.3)', () {
    test('1. Computes exact positive day difference without time truncation', () {
      final start = DateTime(2026, 1, 1, 10, 30);
      final end = DateTime(2026, 1, 11, 8, 15);

      // In pure calendar terms: 11 - 1 = 10 days
      expect(daysBetween(start, end), 10);
      expect(start.daysUntil(end), 10);
      expect(end.daysSince(start), 10);
    });

    test('2. Same-day with different timestamps returns 0 days', () {
      final morning = DateTime(2026, 5, 10, 0, 1);
      final night = DateTime(2026, 5, 10, 23, 59);

      expect(daysBetween(morning, night), 0);
      expect(daysBetween(night, morning), 0);
      expect(morning.daysUntil(night), 0);
    });

    test('3. Negative day difference when end is before start', () {
      final start = DateTime(2026, 3, 15);
      final end = DateTime(2026, 3, 5);

      expect(daysBetween(start, end), -10);
      expect(start.daysUntil(end), -10);
      expect(end.daysSince(start), -10);
    });

    test('4. Crossing midnight within 2 minutes yields exactly 1 day (LocalDate semantics)', () {
      final lateNight = DateTime(2026, 6, 1, 23, 59);
      final earlyMorning = DateTime(2026, 6, 2, 0, 1);

      // Raw DateTime.difference(Duration) would yield 0 days (only 2 minutes difference).
      // ChronoUnit.DAYS.between operates on LocalDate semantics and must yield 1 calendar day.
      expect(daysBetween(lateNight, earlyMorning), 1);
      expect(lateNight.daysUntil(earlyMorning), 1);
    });

    test('5. Month boundary rollover (Jan 31 to Feb 1)', () {
      final jan31 = DateTime(2026, 1, 31);
      final feb1 = DateTime(2026, 2, 1);

      expect(daysBetween(jan31, feb1), 1);
      expect(jan31.daysUntil(feb1), 1);
    });

    test('6. Leap year vs Common year February handling', () {
      // Leap year 2024: Feb 28 to Mar 1 has 2 days (Feb 28 -> Feb 29 -> Mar 1)
      final leapFeb28 = DateTime(2024, 2, 28);
      final leapMar1 = DateTime(2024, 3, 1);
      expect(daysBetween(leapFeb28, leapMar1), 2);

      // Common year 2026: Feb 28 to Mar 1 has 1 day
      final commonFeb28 = DateTime(2026, 2, 28);
      final commonMar1 = DateTime(2026, 3, 1);
      expect(daysBetween(commonFeb28, commonMar1), 1);
    });

    test('7. Year boundary rollover (Dec 31 to Jan 1)', () {
      final dec31 = DateTime(2025, 12, 31, 23, 0);
      final jan1 = DateTime(2026, 1, 1, 1, 0);

      expect(daysBetween(dec31, jan1), 1);
      expect(dec31.daysUntil(jan1), 1);
    });

    test('8. Full year duration (365 days in common year)', () {
      final start = DateTime(2025, 1, 1);
      final end = DateTime(2026, 1, 1);

      expect(daysBetween(start, end), 365);
    });

    test('9. getOverdue uses daysBetween without time-of-day discrepancy', () {
      // Customer took loan on Jan 1 at 23:59
      final record = LedgerRecord(
        id: 'rec-chrono-1',
        transactionId: 'TXN-000050',
        type: RecordType.GIVEN,
        customerId: 'c-1',
        startDate: DateTime(2026, 1, 1, 23, 59),
        principalAmount: 5000.0,
        interestRate: 2.0,
        status: RecordStatus.ACTIVE,
      );

      // Check on Jan 32 (Feb 1) at 00:01 (exactly 31 calendar days later)
      final today = DateTime(2026, 2, 1, 0, 1);
      final overdueList = getOverdue(
        records: [record],
        latestPaymentDates: {'rec-chrono-1': null},
        today: today,
        thresholdDays: 30,
      );

      expect(overdueList.length, 1);
      expect(overdueList.first.daysSinceActivity, 31);
    });
  });
}
