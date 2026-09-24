import '../../../../domain/models/item_rate.dart';

/// Backup DTO for ItemRate (§7.1, [FIX-BACKUP-CONFIG-1], Addendum J.7).
///
/// Encapsulates precious item market rate snapshot:
/// - [id]: Unique identifier
/// - [itemCategory]: Item category (e.g. "Gold 22K")
/// - [ratePerUnit]: Market rate per unit (e.g. 6543.21)
/// - [effectiveDate]: Effective date string ("2026-09-20")
/// - [updatedAt]: ISO datetime string ("2026-09-20T09:00:00")
class BackupItemRate {
  final String id;
  final String itemCategory;
  final double ratePerUnit;
  final String effectiveDate;
  final String updatedAt;

  const BackupItemRate({
    required this.id,
    required this.itemCategory,
    required this.ratePerUnit,
    required this.effectiveDate,
    required this.updatedAt,
  });

  BackupItemRate copyWith({
    String? id,
    String? itemCategory,
    double? ratePerUnit,
    String? effectiveDate,
    String? updatedAt,
  }) {
    return BackupItemRate(
      id: id ?? this.id,
      itemCategory: itemCategory ?? this.itemCategory,
      ratePerUnit: ratePerUnit ?? this.ratePerUnit,
      effectiveDate: effectiveDate ?? this.effectiveDate,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory BackupItemRate.fromJson(Map<String, dynamic> json) {
    return BackupItemRate(
      id: json['id']?.toString() ?? '',
      itemCategory: json['itemCategory']?.toString() ?? '',
      ratePerUnit: (json['ratePerUnit'] as num?)?.toDouble() ?? 0.0,
      effectiveDate: json['effectiveDate']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'itemCategory': itemCategory,
      'ratePerUnit': ratePerUnit,
      'effectiveDate': effectiveDate,
      'updatedAt': updatedAt,
    };
  }

  /// Maps from domain [ItemRate].
  factory BackupItemRate.fromDomain(ItemRate itemRate) {
    return BackupItemRate(
      id: itemRate.id,
      itemCategory: itemRate.itemCategory,
      ratePerUnit: itemRate.ratePerUnit,
      effectiveDate: _formatDateOnly(itemRate.effectiveDate),
      updatedAt: itemRate.updatedAt.toIso8601String(),
    );
  }

  /// Maps to domain [ItemRate].
  ItemRate toDomain() {
    return ItemRate(
      id: id,
      itemCategory: itemCategory,
      ratePerUnit: ratePerUnit,
      effectiveDate: DateTime.tryParse(effectiveDate) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(updatedAt) ?? DateTime.now(),
    );
  }

  static String _formatDateOnly(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupItemRate &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          itemCategory == other.itemCategory &&
          ratePerUnit == other.ratePerUnit &&
          effectiveDate == other.effectiveDate &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      itemCategory.hashCode ^
      ratePerUnit.hashCode ^
      effectiveDate.hashCode ^
      updatedAt.hashCode;
}
