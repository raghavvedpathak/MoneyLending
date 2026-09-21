/// Backup DTO for RetiredId bookkeeping row (Addendum G, FIX-ID-REUSE-1 & §7.1).
class BackupRetiredId {
  final String kind;
  final String displayId;
  final String retiredAt;

  const BackupRetiredId({
    required this.kind,
    required this.displayId,
    required this.retiredAt,
  });

  BackupRetiredId copyWith({
    String? kind,
    String? displayId,
    String? retiredAt,
  }) {
    return BackupRetiredId(
      kind: kind ?? this.kind,
      displayId: displayId ?? this.displayId,
      retiredAt: retiredAt ?? this.retiredAt,
    );
  }

  factory BackupRetiredId.fromJson(Map<String, dynamic> json) {
    return BackupRetiredId(
      kind: json['kind']?.toString() ?? '',
      displayId: json['displayId']?.toString() ?? '',
      retiredAt: json['retiredAt']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'kind': kind,
      'displayId': displayId,
      'retiredAt': retiredAt,
    };
  }
}
