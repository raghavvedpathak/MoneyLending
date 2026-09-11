import 'package:intl/intl.dart';

/// Single Authoritative Central Date Formatter for MoneyLending.
///
/// Mandated User Directive:
/// - Single central source of truth for all date/time formatting across the entire app.
/// - Display date format: "date month year", e.g. "10 September 2026".
/// - Display datetime format: "10 September 2026, 02:30 PM".
/// - Input mask format: "DD/MM/YYYY".
/// - Storage format: Standard ISO-8601 (YYYY-MM-DD / YYYY-MM-DDTHH:MM:SS).
class AppDateFormatter {
  AppDateFormatter._();

  // Date format: "10 September 2026"
  static final DateFormat _displayDateFormat = DateFormat('d MMMM yyyy');

  // DateTime format: "10 September 2026, 02:30 PM"
  static final DateFormat _displayDateTimeFormat = DateFormat('d MMMM yyyy, hh:mm a');

  // Month-Year format: "September 2026"
  static final DateFormat _monthYearFormat = DateFormat('MMMM yyyy');

  // Input mask format: "10/09/2026"
  static final DateFormat _inputDateFormat = DateFormat('dd/MM/yyyy');

  // ISO Storage formats
  static final DateFormat _isoDateFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _isoDateTimeFormat = DateFormat("yyyy-MM-dd'T'HH:mm:ss");

  // PDF Exact Timestamp format mandated by [FIX-TIMESTAMP-PDF-1]: "23/04/2026, 14:30"
  static final DateFormat _pdfTimestampFormat = DateFormat('dd/MM/yyyy, HH:mm');

  // ===========================================================================
  // DISPLAY FORMATTERS
  // ===========================================================================

  /// Formats a DateTime as "10 September 2026"
  static String formatDate(DateTime date) {
    return _displayDateFormat.format(date);
  }

  /// Formats a DateTime as "10 September 2026, 02:30 PM"
  static String formatDateTime(DateTime dateTime) {
    return _displayDateTimeFormat.format(dateTime);
  }

  /// Formats a DateTime as "September 2026"
  static String formatMonthYear(DateTime date) {
    return _monthYearFormat.format(date);
  }

  /// Formats an ISO string as "10 September 2026"
  static String formatDateString(String? isoString, {String fallback = '—'}) {
    if (isoString == null || isoString.trim().isEmpty) return fallback;
    try {
      final parsed = DateTime.parse(isoString);
      return _displayDateFormat.format(parsed);
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
  static String toIsoDate(DateTime date) {
    return _isoDateFormat.format(date);
  }

  /// Formats a DateTime for PDF exact timestamps: "dd/MM/yyyy, HH:mm" [FIX-TIMESTAMP-PDF-1]
  static String formatPdfTimestamp(DateTime dateTime) {
    return _pdfTimestampFormat.format(dateTime);
  }

  /// Formats a DateTime to standard ISO datetime: "YYYY-MM-DDTHH:MM:SS"
  static String toIsoDateTime(DateTime dateTime) {
    return _isoDateTimeFormat.format(dateTime);
  }
}

// Convenience top-level accessors
String formatDate(DateTime date) => AppDateFormatter.formatDate(date);
String formatDateTime(DateTime dateTime) => AppDateFormatter.formatDateTime(dateTime);
String formatPdfTimestamp(DateTime dateTime) => AppDateFormatter.formatPdfTimestamp(dateTime);
String formatDateString(String? isoString, {String fallback = '—'}) =>
    AppDateFormatter.formatDateString(isoString, fallback: fallback);
String formatDateTimeString(String? isoString, {String fallback = '—'}) =>
    AppDateFormatter.formatDateTimeString(isoString, fallback: fallback);
String formatInputDate(DateTime date) => AppDateFormatter.formatInputDate(date);
String toIsoDate(DateTime date) => AppDateFormatter.toIsoDate(date);
String toIsoDateTime(DateTime dateTime) => AppDateFormatter.toIsoDateTime(dateTime);
