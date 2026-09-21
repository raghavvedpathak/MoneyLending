// ignore_for_file: constant_identifier_names

/// Record Status Enum (ACTIVE vs SETTLED).
///
/// Mandated by Data Spec §4.2:
/// Stored as string enum.name for raw SQLite inspection readability.
enum RecordStatus {
  ACTIVE,
  SETTLED;

  /// Lowercase aliases for typed equalsValue() matching [FIX-ENUM-CASE-1]
  static const RecordStatus active = RecordStatus.ACTIVE;
  static const RecordStatus settled = RecordStatus.SETTLED;

  static RecordStatus? fromString(String? value) {
    if (value == null) return null;
    try {
      final upper = value.toUpperCase();
      return RecordStatus.values.firstWhere((e) => e.name.toUpperCase() == upper);
    } catch (_) {
      return null;
    }
  }
}
