import '../../core/domain/util/date_format.dart';

/// Type of lender party (§4.1 & §5.1, [FIX-ENUM-CASE-1]).
enum LenderType {
  individual,
  institution;

  String get displayName => switch (this) {
        individual => 'Individual',
        institution => 'Institution',
      };
}

/// Pure Domain Entity for Lender (§4.1 & §4.3, [FIX-LENDER-CODEPATH-1]).
///
/// Added for the TAKEN side of the ledger (Borrower/Lender separation).
class Lender {
  final String id;
  final String displayId;
  final LenderType lenderType;
  final String name;
  final String? phone;
  final String? institutionDetails;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Lender({
    required this.id,
    required this.displayId,
    required this.lenderType,
    required this.name,
    this.phone,
    this.institutionDetails,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Formatted as "10 September 2026"
  String get formattedCreatedAt => formatDate(createdAt);

  /// Formatted as "10 September 2026, 02:30 PM"
  String get formattedUpdatedAt => formatDateTime(updatedAt);

  bool get isIndividual => lenderType == LenderType.individual;
  bool get isInstitution => lenderType == LenderType.institution;

  Lender copyWith({
    String? id,
    String? displayId,
    LenderType? lenderType,
    String? name,
    String? phone,
    String? institutionDetails,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Lender(
      id: id ?? this.id,
      displayId: displayId ?? this.displayId,
      lenderType: lenderType ?? this.lenderType,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      institutionDetails: institutionDetails ?? this.institutionDetails,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Lender &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Lender(id: $id, displayId: $displayId, type: ${lenderType.name}, name: $name)';
}
