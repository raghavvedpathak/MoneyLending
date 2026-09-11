// ignore_for_file: constant_identifier_names

/// Record Status Enum (ACTIVE vs SETTLED).
///
/// Mandated by Data Spec §4.2:
/// Stored as string enum.name for raw SQLite inspection readability.
enum RecordStatus {
  ACTIVE,
  SETTLED;

  static RecordStatus? fromString(String? value) {
    if (value == null) return null;
    try {
      return RecordStatus.values.firstWhere((e) => e.name == value);
    } catch (_) {
      return null;
    }
  }
}
