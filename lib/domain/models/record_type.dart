// ignore_for_file: constant_identifier_names

/// Record Type Enum (GIVEN vs TAKEN).
///
/// Mandated by Data Spec §4.2:
/// Stored as string enum.name for raw SQLite inspection readability.
enum RecordType {
  GIVEN,
  TAKEN;

  /// Lowercase aliases for typed equalsValue() matching [FIX-ENUM-CASE-1]
  static const RecordType given = RecordType.GIVEN;
  static const RecordType taken = RecordType.TAKEN;

  static RecordType? fromString(String? value) {
    if (value == null) return null;
    try {
      final upper = value.toUpperCase();
      return RecordType.values.firstWhere((e) => e.name.toUpperCase() == upper);
    } catch (_) {
      return null;
    }
  }
}
