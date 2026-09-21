/// Date extensions for calculations (:core:calculations/util/date_extensions.dart).
///
/// Mandated by Business Logic Spec §5.2 & [FIX-DEV-SAFEDATE-1]:
/// Safe past date resolution for string and DateTime values.
/// Parses a nullable/blank ISO date string, returning null if:
/// - the string is null or blank (handles legacy endDate="" records)
/// - the string fails to parse as a date
/// - the parsed date is in the future (not a valid past targetDate)
///
/// Use for legacy String? fields (e.g. backup import):
/// dateString.toSafePastDate(today) ?? today
/// For DateTime? domain fields use accrualEndDate(record, today) instead.
extension SafePastDate on String? {
  DateTime? toSafePastDate(DateTime today) { // [FIX-CLOCK-1] today injected, no hidden clock
    final s = this;
    if (s == null || s.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(s)?.dateOnly;
    if (parsed == null) return null;
    if (parsed.isAfter(today)) return null;
    return parsed;
  }
}

extension SafePastDateTimeExtension on DateTime? {
  /// Inline domain helper: returns null if date is in the future.
  DateTime? toSafePastDate(DateTime today) {
    if (this == null) return null;
    final parsedDate = this!.dateOnly;
    if (parsedDate.isAfter(today.dateOnly)) return null;
    return parsedDate;
  }
}

/// Pure Dart equivalent of java.time.temporal.ChronoUnit.DAYS.between(start, end) (§5.2.3).
///
/// Strips time-of-day components and normalizes to UTC calendar midnight to prevent
/// daylight saving time (DST) skew, leap second artifacts, and time truncation.
/// Exactly calculates the signed calendar day difference: (end - start).
int daysBetween(DateTime start, DateTime end) {
  final s = DateTime.utc(start.year, start.month, start.day);
  final e = DateTime.utc(end.year, end.month, end.day);
  return e.difference(s).inDays;
}

/// Extension methods on DateTime for ChronoUnit.DAYS equivalent operations (§5.2.3).
extension DateTimeChronoUnitExtension on DateTime {
  /// Equivalent to ChronoUnit.DAYS.between(this, other) (§5.2.3).
  int daysUntil(DateTime other) => daysBetween(this, other);

  /// Calendar days elapsed since [other]: ChronoUnit.DAYS.between(other, this).
  int daysSince(DateTime other) => daysBetween(other, this);
}

/// Date convention extension mandated by §4.2:
/// Every field marked "date-only" (createdAt, endDate, settledDate, effectiveDate)
/// is represented in the domain layer as a Dart DateTime whose time-of-day is always 00:00:00.000.
extension DateOnly on DateTime {
  /// Truncates to midnight, local time. Use for every "date-only" field
  /// (createdAt, endDate, settledDate, effectiveDate) at every read/write
  /// boundary. Never compare a "date-only" DateTime to a "datetime" DateTime
  /// without calling .dateOnly on the datetime side first.
  DateTime get dateOnly => DateTime(year, month, day);
}
