import 'package:intl/intl.dart';
import '../domain/util/date_format.dart' as pure_date;

export '../domain/util/date_format.dart';

/// Single Authoritative Central Date Formatter for MoneyLending.
///
/// Mandated User Directive and [FIX-DATEFORMAT-1]:
/// - Single central source of truth for all date/time formatting across the entire app.
/// - Display date format: "date month year", e.g. "20 September 2026" (pure Dart, no intl).
/// - Display datetime format: "10 September 2026, 02:30 PM".
/// - Input mask format: "DD/MM/YYYY".
/// - Storage format: Standard ISO-8601 (YYYY-MM-DD / YYYY-MM-DDTHH:MM:SS).
class AppDateFormatter {
  AppDateFormatter._();

  // DateTime format: "10 September 2026, 02:30 PM"
  static final DateFormat _displayDateTimeFormat = DateFormat('d MMMM yyyy, hh:mm a');

  // Input mask format: "10/09/2026"
  static final DateFormat _inputDateFormat = DateFormat('dd/MM/yyyy');

  // PDF Exact Timestamp format mandated by [FIX-TIMESTAMP-PDF-1]: "23/04/2026, 14:30"
  static final DateFormat _pdfTimestampFormat = DateFormat('dd/MM/yyyy, HH:mm');

  // ===========================================================================
  // DISPLAY FORMATTERS
  // ===========================================================================

  /// Formats a DateTime as "20 September 2026" (§2.2 [FIX-DATEFORMAT-1])
  static String formatDate(DateTime date) {
    return pure_date.formatDate(date);
  }

  /// Formats a DateTime as "10 September 2026, 02:30 PM"
  static String formatDateTime(DateTime dateTime) {
    return _displayDateTimeFormat.format(dateTime);
  }

  /// Formats a DateTime as "September 2026" (§2.2 [FIX-DATEFORMAT-1])
  static String formatMonthYear(DateTime date) {
    return pure_date.formatMonthYear(date);
  }

  /// Formats duration / tenure in months (e.g. "1 month", "2 months", "2.5 months")
  static String formatMonths(double months) {
    if (months == 1.0) return '1 month';
    if (months == months.roundToDouble()) {
      return '${months.toInt()} months';
    }
    return '${months.toStringAsFixed(1)} months';
  }

  /// Formats an ISO string as "20 September 2026"
  static String formatDateString(String? isoString, {String fallback = '—'}) {
    if (isoString == null || isoString.trim().isEmpty) return fallback;
    try {
      final parsed = DateTime.parse(isoString);
      return pure_date.formatDate(parsed);
    } catch (_) {
      return fallback;
    }
  }

  /// Formats an ISO string as "10 September 2026, 02:30 PM"
  static String formatDateTimeString(String? isoString, {String fallback = '—'}) {
    if (isoString == null || isoString.trim().isEmpty) return fallback;
    try {
      final parsed = DateTime.parse(isoString);
      return _displayDateTimeFormat.format(parsed);
    } catch (_) {
      return fallback;
    }
  }

  // ===========================================================================
  // INPUT & PARSING HELPERS
  // ===========================================================================

  /// Formats DateTime for masked input fields: "10/09/2026"
  static String formatInputDate(DateTime date) {
    return _inputDateFormat.format(date);
  }

  /// Safely parses an ISO date or datetime string
  static DateTime? parseIso(String? isoString) {
    if (isoString == null || isoString.trim().isEmpty) return null;
    try {
      return DateTime.parse(isoString);
    } catch (_) {
      return null;
    }
  }

  /// Formats a DateTime to standard ISO date: "YYYY-MM-DD"
  /// Formats digits by hand (no DateFormat) to guarantee ASCII digits [FIX-TIMESTAMP-TYPECONVERTERS-1].
  static String toIsoDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Formats a DateTime for PDF exact timestamps: "dd/MM/yyyy, HH:mm" [FIX-TIMESTAMP-PDF-1]
  static String formatPdfTimestamp(DateTime dateTime) {
    return _pdfTimestampFormat.format(dateTime);
  }

  /// Formats a DateTime to standard ISO datetime: "YYYY-MM-DDTHH:MM:SS"
  /// Formats digits by hand (no DateFormat) to guarantee ASCII digits [FIX-TIMESTAMP-TYPECONVERTERS-1].
  static String toIsoDateTime(DateTime dateTime) {
    final y = dateTime.year.toString().padLeft(4, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final mm = dateTime.minute.toString().padLeft(2, '0');
    final ss = dateTime.second.toString().padLeft(2, '0');
    return '$y-$m-${d}T$hh:$mm:$ss';
  }
}

// Convenience top-level accessors
String formatPdfTimestamp(DateTime dateTime) => AppDateFormatter.formatPdfTimestamp(dateTime);
String formatDateString(String? isoString, {String fallback = '—'}) =>
    AppDateFormatter.formatDateString(isoString, fallback: fallback);
String formatDateTimeString(String? isoString, {String fallback = '—'}) =>
    AppDateFormatter.formatDateTimeString(isoString, fallback: fallback);
String formatInputDate(DateTime date) => AppDateFormatter.formatInputDate(date);
String formatMonths(double months) => AppDateFormatter.formatMonths(months);
String toIsoDate(DateTime date) => AppDateFormatter.toIsoDate(date);
String toIsoDateTime(DateTime dateTime) => AppDateFormatter.toIsoDateTime(dateTime);
