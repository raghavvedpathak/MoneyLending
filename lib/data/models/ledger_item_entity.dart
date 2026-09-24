/// Data Layer Entity for 'ledger_items' table.
///
/// Mandated by Data Spec §4.1 and [FIXLEDGERITEM-NULLABILITY-1]:
/// - id: UUID String (Primary Key)
/// - recordId: Foreign key referencing records.id
/// - name: Short human display name (NOT NULL)
/// - itemCategory: Stable category key matching item_rates (NOT NULL)
/// - description: Optional notes, strictly NULLABLE (String?)
/// - weight: Weight of item (grams or units)
/// - purity: Purity percentage (e.g., 92.5)
/// - rate: Price per unit snapshot at time of lending
/// - itemValue: Computed snapshot (weight * (purity / 100) * rate)
/// - lendPercentage: User-entered percentage (e.g., 80)
/// - lendableAmount: Computed max lendable (itemValue * (lendPercentage / 100))
class LedgerItemEntity {
  final String id;
  final String recordId;
  final String name;
  final String itemCategory;
  final String? description; // Strictly nullable [FIXLEDGERITEM-NULLABILITY-1]
  final double? weight;
  final double? purity;
  // DO NOT CHANGE TO INTEGER — switching to paise storage requires a Room schema migration; see §4.2 for full rationale.
  final double? rate;
  final double? itemValue;
  final double? lendPercentage;
  final double? lendableAmount;
  // [FIX-ITEM-CUSTODY-2] sourceItemId: self-referential FK, null unless copied via custody chain
  final String? sourceItemId;

  const LedgerItemEntity({
    required this.id,
    required this.recordId,
    required this.name,
    required this.itemCategory,
    this.description,
    this.weight,
    this.purity,
    this.rate,
    this.itemValue,
    this.lendPercentage,
    this.lendableAmount,
    this.sourceItemId,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'recordId': recordId,
      'name': name,
      'itemCategory': itemCategory,
      'description': description,
      'weight': weight,
      'purity': purity,
      'rate': rate,
      'itemValue': itemValue,
      'lendPercentage': lendPercentage,
      'lendableAmount': lendableAmount,
    };
    if (sourceItemId != null) {
      map['sourceItemId'] = sourceItemId;
    }
    return map;
  }

  factory LedgerItemEntity.fromMap(Map<String, dynamic> map) {
    return LedgerItemEntity(
      id: map['id'] as String,
      recordId: map['recordId'] as String,
      name: map['name'] as String,
      itemCategory: map['itemCategory'] as String,
      description: map['description'] as String?,
      weight: (map['weight'] as num?)?.toDouble(),
      purity: (map['purity'] as num?)?.toDouble(),
      rate: (map['rate'] as num?)?.toDouble(),
      itemValue: (map['itemValue'] as num?)?.toDouble(),
      lendPercentage: (map['lendPercentage'] as num?)?.toDouble(),
      lendableAmount: (map['lendableAmount'] as num?)?.toDouble(),
      sourceItemId: map['sourceItemId'] as String?,
    );
  }

  LedgerItemEntity copyWith({
    String? id,
    String? recordId,
    String? name,
    String? itemCategory,
    String? description,
    double? weight,
    double? purity,
    double? rate,
    double? itemValue,
    double? lendPercentage,
    double? lendableAmount,
    String? sourceItemId,
  }) {
    return LedgerItemEntity(
      id: id ?? this.id,
      recordId: recordId ?? this.recordId,
      name: name ?? this.name,
      itemCategory: itemCategory ?? this.itemCategory,
      description: description ?? this.description,
      weight: weight ?? this.weight,
      purity: purity ?? this.purity,
      rate: rate ?? this.rate,
      itemValue: itemValue ?? this.itemValue,
      lendPercentage: lendPercentage ?? this.lendPercentage,
      lendableAmount: lendableAmount ?? this.lendableAmount,
      sourceItemId: sourceItemId ?? this.sourceItemId,
    );
  }
}

/// Drift/DAO alias mandated by Data Spec §4.4 (@DataClassName('LedgerItemEntityData'))
typedef LedgerItemEntityData = LedgerItemEntity;
