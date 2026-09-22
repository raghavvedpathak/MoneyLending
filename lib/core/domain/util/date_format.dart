// lib/core/domain/util/date_format.dart — pure Dart

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// The ONE date display format in the app: "20 September 2026".
/// Uses the LOCAL calendar fields; never call .toUtc() on the argument.
String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "September 2026" - month labels (Reports > Monthly).
String formatMonthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

/// "20 September 2026, 02:30 PM" - datetime format.
String formatDateTime(DateTime d) {
  final datePart = formatDate(d);
  final hour = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
  final hourStr = hour.toString().padLeft(2, '0');
  final minuteStr = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour >= 12 ? 'PM' : 'AM';
  return '$datePart, $hourStr:$minuteStr $ampm';
}
