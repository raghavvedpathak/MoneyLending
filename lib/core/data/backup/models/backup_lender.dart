/// Backup DTO for Lender (§7.1, §4.4, [FIX-LENDER-CODEPATH-1]).
///
/// Kept separate from domain [Lender] to protect against serialization leakage.
class BackupLender {
  final String id;
  final String displayId;
  final String lenderType;
  final String name;
  final String phone;
  final String? institutionDetails;
  final String? notes;
  final String createdAt;
  final String updatedAt;

  const BackupLender({
    required this.id,
    this.displayId = '',
    this.lenderType = 'individual',
    required this.name,
    this.phone = '',
    this.institutionDetails,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  BackupLender copyWith({
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
    return BackupLender(
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

  factory BackupLender.fromJson(Map<String, dynamic> json) {
    return BackupLender(
      id: json['id']?.toString() ?? '',
      displayId: json['displayId']?.toString() ?? '',
      lenderType: json['lenderType']?.toString() ?? 'individual',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      institutionDetails: json['institutionDetails']?.toString(),
      notes: json['notes']?.toString(),
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? (json['createdAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayId': displayId,
      'lenderType': lenderType,
      'name': name,
      'phone': phone,
      if (institutionDetails != null) 'institutionDetails': institutionDetails,
      if (notes != null) 'notes': notes,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupLender &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          displayId == other.displayId &&
          lenderType == other.lenderType &&
          name == other.name &&
          phone == other.phone &&
          institutionDetails == other.institutionDetails &&
          notes == other.notes &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      displayId.hashCode ^
      lenderType.hashCode ^
      name.hashCode ^
      phone.hashCode ^
      institutionDetails.hashCode ^
      notes.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;
}
