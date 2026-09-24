import '../../../../domain/models/settings.dart';

/// Backup DTO for Settings (§7.1, [FIX-BACKUP-CONFIG-1], Addendum J.7).
///
/// Encapsulates business settings:
/// - [name]: Business name
/// - [phone]: Contact phone
/// - [address]: Business address
/// - [defaultInterestRate]: Default monthly interest rate percentage (e.g. 2.0)
class BackupSettings {
  final String name;
  final String phone;
  final String address;
  final double defaultInterestRate;

  const BackupSettings({
    this.name = '',
    this.phone = '',
    this.address = '',
    this.defaultInterestRate = 2.0,
  });

  BackupSettings copyWith({
    String? name,
    String? phone,
    String? address,
    double? defaultInterestRate,
  }) {
    return BackupSettings(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      defaultInterestRate: defaultInterestRate ?? this.defaultInterestRate,
    );
  }

  factory BackupSettings.fromJson(Map<String, dynamic> json) {
    return BackupSettings(
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      defaultInterestRate: (json['defaultInterestRate'] as num?)?.toDouble() ?? 2.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'address': address,
      'defaultInterestRate': defaultInterestRate,
    };
  }

  /// Maps from domain [Settings].
  factory BackupSettings.fromDomain(Settings settings) {
    return BackupSettings(
      name: settings.name,
      phone: settings.phone,
      address: settings.address,
      defaultInterestRate: settings.defaultInterestRate,
    );
  }

  /// Maps to domain [Settings].
  Settings toDomain([int id = 1]) {
    return Settings(
      id: id,
      name: name,
      phone: phone,
      address: address,
      defaultInterestRate: defaultInterestRate,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupSettings &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          phone == other.phone &&
          address == other.address &&
          defaultInterestRate == other.defaultInterestRate;

  @override
  int get hashCode =>
      name.hashCode ^
      phone.hashCode ^
      address.hashCode ^
      defaultInterestRate.hashCode;
}
