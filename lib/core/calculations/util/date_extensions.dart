/// Date extensions for calculations (:core:calculations/util/date_extensions.dart).
///
/// Mandated by Business Logic Spec §5.2 & [FIX-DEV-SAFEDATE-1]:
/// Safe past date resolution for string and DateTime values.
extension SafePastDateExtension on String? {
  /// Parses a nullable/blank ISO date string, returning null if:
  /// - the string is null or blank (handles legacy endDate="" records)
  /// - the string fails to parse as DateTime
  /// - the parsed date is in the future (not a valid past targetDate)
  DateTime? toSafePastDate([DateTime? referenceNow]) {
    if (this == null || this!.trim().isEmpty) return null;
    try {
      final parsed = DateTime.parse(this!.trim());
      final parsedDate = DateTime(parsed.year, parsed.month, parsed.day);
      final now = referenceNow ?? DateTime.now();
      final nowDate = DateTime(now.year, now.month, now.day);
      if (parsedDate.isAfter(nowDate)) return null;
      return parsedDate;
    } catch (_) {
      return null;
    }
  }
}

extension SafePastDateTimeExtension on DateTime? {
  /// Inline domain helper: returns null if date is in the future.
  DateTime? toSafePastDate([DateTime? referenceNow]) {
    if (this == null) return null;
    final parsedDate = DateTime(this!.year, this!.month, this!.day);
    final now = referenceNow ?? DateTime.now();
    final nowDate = DateTime(now.year, now.month, now.day);
    if (parsedDate.isAfter(nowDate)) return null;
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
