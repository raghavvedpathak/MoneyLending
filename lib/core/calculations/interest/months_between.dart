// lib/core/calculations/interest/months_between.dart
import 'dart:math' as math;

/// Both [start] and [end] MUST already be date-only (midnight-truncated) — see §4.2.
/// Do not pass a raw record.startDate or payment.date without calling .dateOnly first.
double getMonthsBetween(DateTime start, DateTime end) {
  final years = end.year - start.year;
  final months = end.month - start.month;
  var totalMonths = (years * 12 + months).toDouble();
  final startDay = start.day;
  final endDay = end.day;
  final dayDiff = endDay - startDay;

  if (dayDiff < 0) {
    totalMonths -= 1;
    // ⚠️ Compute daysInPrevMonth AFTER the decrement above, using the already-
    // decremented totalMonths — this mirrors Kotlin's
    // start.plusMonths(totalMonths.toLong()).lengthOfMonth() exactly.
    final prevMonthDate = addMonths(start, totalMonths.toInt());
    final daysInPrevMonth = daysInMonth(prevMonthDate.year, prevMonthDate.month);
    final adjustedDays = daysInPrevMonth - startDay + endDay;
    if (adjustedDays > 15) {
      totalMonths += 1.0;
    } else if (adjustedDays > 0) {
      totalMonths += 0.5;
    }
    // else: += 0.0 (no-op)
  } else {
    if (dayDiff > 15) {
      totalMonths += 1.0;
    } else if (dayDiff > 0) {
      totalMonths += 0.5;
    }
    // else: += 0.0 (no-op)
  }
  return totalMonths < 0.0 ? 0.0 : totalMonths;
}

/// [FIX-ADDMONTHS-1] (v1.14) PUBLIC (no leading underscore: §5.4 and Addendum F call it
/// from other files). Adds whole months and KEEPS the day-of-month, clamped to the length
/// of the target month: 20 Sep + 2 = 20 Nov; 31 Jan + 1 = 28/29 Feb. (The v1.13 version
/// returned day 1, which cut every 2-month projection short by up to 30 days.)
DateTime addMonths(DateTime date, int months) {
  final totalMonthIndex = date.month - 1 + months;
  final year = date.year + (totalMonthIndex / 12).floor(); // floor: correct for negatives
  final month = totalMonthIndex % 12 + 1; // Dart % is non-negative for a positive divisor
  final day = math.min(date.day, daysInMonth(year, month));
  return DateTime(year, month, day);
}

int daysInMonth(int year, int month) {
  final firstOfNextMonth =
      month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
  return firstOfNextMonth.subtract(const Duration(days: 1)).day;
}
