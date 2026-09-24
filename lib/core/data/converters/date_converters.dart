import 'package:drift/drift.dart';

String _p2(int n) => n.toString().padLeft(2, '0');
String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_p2(d.month)}-${_p2(d.day)}';

/// "date-only" columns: endDate, settledDate, createdAt, effectiveDate.
/// SQL form 'YYYY-MM-DD'. Domain form: DateTime at LOCAL midnight.
class DateOnlyConverter extends TypeConverter<DateTime, String> {
  const DateOnlyConverter();

  @override
  DateTime fromSql(String fromDb) {
    final d = DateTime.parse(fromDb); // accepts a bare date or a full datetime
    return DateTime(d.year, d.month, d.day);
  }

  @override
  String toSql(DateTime value) => _ymd(value);
}

/// "datetime" columns: records.startDate, payments.date, item_rates.updatedAt,
/// retired_ids.retiredAt. SQL form 'YYYY-MM-DDTHH:MM:SS' - local time, no offset,
/// no fraction (milliseconds are dropped on purpose).
class LocalDateTimeConverter extends TypeConverter<DateTime, String> {
  const LocalDateTimeConverter();

  @override
  DateTime fromSql(String fromDb) => DateTime.parse(fromDb); // no offset => local

  @override
  String toSql(DateTime v) =>
      '${_ymd(v)}T${_p2(v.hour)}:${_p2(v.minute)}:${_p2(v.second)}';
}
