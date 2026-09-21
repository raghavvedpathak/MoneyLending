/// Backup DTO for LedgerItem (§7.1).
///
/// Mandated by Step 6.1 [FIX-ITEM-CUSTODY-MIGRATION-1]:
/// - [sourceItemId]: added in v1.3; defaults to null on older backups.
/// - [itemCategory]: defaults to 'Unknown' on legacy bare-array backups.
class BackupItem {
  final String id;
  final String recordId;
  final String name;
  final String itemCategory;
  final String? description;
  final double weight;
  final double purity;
  final double rate;
  final double itemValue;
  final double lendPercentage;
  final double lendableAmount;
  final double? fineWeight;
  final String? sourceItemId;

  const BackupItem({
    required this.id,
    this.recordId = '',
    required this.name,
    this.itemCategory = 'Unknown',
    this.description,
    this.weight = 0.0,
    this.purity = 0.0,
    this.rate = 0.0,
    this.itemValue = 0.0,
    this.lendPercentage = 0.0,
    this.lendableAmount = 0.0,
    this.fineWeight,
    this.sourceItemId,
  });

  BackupItem copyWith({
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
    double? fineWeight,
    String? sourceItemId,
  }) {
    return BackupItem(
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
      fineWeight: fineWeight ?? this.fineWeight,
      sourceItemId: sourceItemId ?? this.sourceItemId,
    );
  }

  factory BackupItem.fromJson(Map<String, dynamic> json) {
    return BackupItem(
      id: json['id']?.toString() ?? '',
      recordId: json['recordId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      itemCategory: json['itemCategory']?.toString() ?? 'Unknown',
      description: json['description']?.toString(),
      weight: (json['weight'] as num?)?.toDouble() ?? 0.0,
      purity: (json['purity'] as num?)?.toDouble() ?? 0.0,
      rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
      itemValue: (json['itemValue'] as num?)?.toDouble() ?? 0.0,
      lendPercentage: (json['lendPercentage'] as num?)?.toDouble() ?? 0.0,
      lendableAmount: (json['lendableAmount'] as num?)?.toDouble() ?? 0.0,
      fineWeight: (json['fineWeight'] as num?)?.toDouble(),
      sourceItemId: json['sourceItemId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'recordId': recordId,
      'name': name,
      'itemCategory': itemCategory,
      if (description != null) 'description': description,
      'weight': weight,
      'purity': purity,
      'rate': rate,
      'itemValue': itemValue,
      'lendPercentage': lendPercentage,
      'lendableAmount': lendableAmount,
      if (fineWeight != null) 'fineWeight': fineWeight,
      'sourceItemId': sourceItemId,
    };
  }
}
