/// Bookkeeping entity for 'retired_ids' table (Addendum G, FIX-ID-REUSE-1).
///
/// Mandated by Data Spec §4.1:
/// - kind: 'customer' | 'transaction' | 'payment'
/// - displayId: the retired identifier
/// - retiredAt: ISO datetime string
/// - Composite primary key: (kind, displayId)
///
/// Bookkeeping only: a row is written when a number that had linked data is deleted
/// and is read only by the sequence generator, so a retired number is never reissued.
/// No FK, no domain model.
class RetiredIdEntity {
  final String kind;
  final String displayId;
  final String retiredAt;

  const RetiredIdEntity({
    required this.kind,
    required this.displayId,
    required this.retiredAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'kind': kind,
      'displayId': displayId,
      'retiredAt': retiredAt,
    };
  }

  factory RetiredIdEntity.fromMap(Map<String, dynamic> map) {
    return RetiredIdEntity(
      kind: map['kind'] as String,
      displayId: map['displayId'] as String,
      retiredAt: map['retiredAt'] as String,
    );
  }

  @override
  String toString() => 'RetiredIdEntity(kind: $kind, displayId: $displayId, retiredAt: $retiredAt)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RetiredIdEntity &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          displayId == other.displayId &&
          retiredAt == other.retiredAt;

  @override
  int get hashCode => Object.hash(kind, displayId, retiredAt);
}

/// Drift/DAO alias mandated by Data Spec §4.4 (@DataClassName('RetiredIdEntityData'))
typedef RetiredIdEntityData = RetiredIdEntity;
