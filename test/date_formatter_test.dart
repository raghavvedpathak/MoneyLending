import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/core.dart';

void main() {
  group('AppDateFormatter tests', () {
    test('formats DateTime as "10 September 2026"', () {
      final date = DateTime(2026, 9, 10);
      expect(formatDate(date), '10 September 2026');
    });

    test('formats DateTime with time', () {
      final dateTime = DateTime(2026, 9, 10, 14, 30);
      expect(formatDateTime(dateTime), '10 September 2026, 02:30 PM');
    });

    test('formats ISO date string as "10 September 2026"', () {
      expect(formatDateString('2026-09-10'), '10 September 2026');
      expect(formatDateString('2026-09-10T14:30:00'), '10 September 2026');
    });

    test('formats DateTime for PDF exact timestamp mandated by [FIX-TIMESTAMP-PDF-1]', () {
      final dateTime = DateTime(2026, 4, 23, 14, 30);
      expect(formatPdfTimestamp(dateTime), '23/04/2026, 14:30');
    });

    test('handles null or empty fallback gracefully', () {
      expect(formatDateString(null), '—');
      expect(formatDateString(''), '—');
      expect(formatDateTimeString(null, fallback: 'N/A'), 'N/A');
    });
  });
}
