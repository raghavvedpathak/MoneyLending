/// Data Layer Entity for 'item_rates' table.
///
/// Mandated by Data Spec §4.1:
/// - id: UUID String (Primary Key)
/// - itemCategory: User-defined category name (e.g. 'Gold 22K', 'Silver')
/// - ratePerUnit: Price per gram / unit in INR
/// - effectiveDate: ISO date string YYYY-MM-DD
/// - updatedAt: ISO datetime of last edit
/// Unique index on (itemCategory, effectiveDate).
class ItemRateEntity {
  final String id;
  final String itemCategory;
  final double ratePerUnit;
  final String effectiveDate; // YYYY-MM-DD
  final String updatedAt; // ISO Datetime

  const ItemRateEntity({
    required this.id,
    required this.itemCategory,
    required this.ratePerUnit,
    required this.effectiveDate,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'itemCategory': itemCategory,
      'ratePerUnit': ratePerUnit,
      'effectiveDate': effectiveDate,
      'updatedAt': updatedAt,
    };
  }

  factory ItemRateEntity.fromMap(Map<String, dynamic> map) {
    return ItemRateEntity(
      id: map['id'] as String,
      itemCategory: map['itemCategory'] as String,
      ratePerUnit: (map['ratePerUnit'] as num).toDouble(),
      effectiveDate: map['effectiveDate'] as String,
      updatedAt: map['updatedAt'] as String,
    );
  }
}
