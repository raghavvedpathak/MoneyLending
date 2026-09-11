// ignore_for_file: constant_identifier_names

/// Record Type Enum (GIVEN vs TAKEN).
///
/// Mandated by Data Spec §4.2:
/// Stored as string enum.name for raw SQLite inspection readability.
enum RecordType {
  GIVEN,
  TAKEN;

  static RecordType? fromString(String? value) {
    if (value == null) return null;
    try {
      return RecordType.values.firstWhere((e) => e.name == value);
    } catch (_) {
      return null;
    }
  }
}
