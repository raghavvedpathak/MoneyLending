/// Pure Domain Entity for LedgerItem.
///
/// Mandated by Data Spec §4.1 & [FIXLEDGERITEM-NULLABILITY-1]:
/// - name is NOT NULL: String
/// - description is strictly nullable: String?
class LedgerItem {
  final String id;
  final String recordId;
  final String name;
  final String itemCategory;
  final String? description;
  final double? weight;
  final double? purity;
  final double? rate;
  final double? itemValue;
  final double? lendPercentage;
  final double? lendableAmount;

  const LedgerItem({
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
  });
}
