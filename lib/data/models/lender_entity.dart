import '../../core/utils/app_date_formatter.dart';
import '../../domain/models/lender.dart';

/// Data Layer Entity for 'lenders' table (§4.1 & §4.3, [FIX-LENDER-CODEPATH-1]).
///
/// Added for the TAKEN side of the ledger (Borrower/Lender separation).
class LenderEntity {
  final String id;
  final String displayId;
  final String lenderType; // 'individual' or 'institution'
  final String name;
  final String? phone;
  final String? institutionDetails;
  final String? notes;
  final String createdAt;
  final String updatedAt;

  const LenderEntity({
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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayId': displayId,
      'lenderType': lenderType,
      'name': name,
      'phone': phone,
      'institutionDetails': institutionDetails,
      'notes': notes,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory LenderEntity.fromMap(Map<String, dynamic> map) {
    return LenderEntity(
      id: map['id'] as String,
      displayId: map['displayId'] as String,
      lenderType: (map['lenderType'] as String?) ?? 'individual',
      name: map['name'] as String,
      phone: map['phone'] as String?,
      institutionDetails: map['institutionDetails'] as String?,
      notes: map['notes'] as String?,
      createdAt: map['createdAt'] as String,
      updatedAt: (map['updatedAt'] as String?) ?? (map['createdAt'] as String),
    );
  }

  LenderEntity copyWith({
    String? id,
    String? displayId,
    String? lenderType,
    String? name,
    String? phone,
    String? institutionDetails,
    String? notes,
    String? createdAt,
    String? updatedAt,
  }) {
    return LenderEntity(
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

  /// Maps to domain [Lender] model.
  Lender toDomain() {
    final type = lenderType == 'institution'
        ? LenderType.institution
        : LenderType.individual;
    final parsedCreated =
        AppDateFormatter.parseIso(createdAt) ?? DateTime.now();
    final parsedUpdated =
        AppDateFormatter.parseIso(updatedAt) ?? DateTime.now();
    return Lender(
      id: id,
      displayId: displayId,
      lenderType: type,
      name: name,
      phone: phone,
      institutionDetails: institutionDetails,
      notes: notes,
      createdAt: parsedCreated,
      updatedAt: parsedUpdated,
    );
  }

  /// Creates entity from domain [Lender] model.
  factory LenderEntity.fromDomain(Lender domain) {
    return LenderEntity(
      id: domain.id,
      displayId: domain.displayId,
      lenderType: domain.lenderType.name,
      name: domain.name,
      phone: domain.phone,
      institutionDetails: domain.institutionDetails,
      notes: domain.notes,
      createdAt: domain.createdAt.toIso8601String(),
      updatedAt: domain.updatedAt.toIso8601String(),
    );
  }
}

/// Drift/DAO alias mandated by Data Spec §4.4
typedef LenderEntityData = LenderEntity;
