import 'settings.dart';

/// Pure Domain Entity for Business Info / Header (§6.1).
///
/// Encapsulates the business/lender details displayed on PDF statement headers
/// and report documents.
class BusinessInfo {
  final String name;
  final String phone;
  final String address;

  const BusinessInfo({
    this.name = '',
    this.phone = '',
    this.address = '',
  });

  /// Factory constructing [BusinessInfo] from the central app [Settings].
  factory BusinessInfo.fromSettings(Settings settings) {
    return BusinessInfo(
      name: settings.name,
      phone: settings.phone,
      address: settings.address,
    );
  }

  BusinessInfo copyWith({
    String? name,
    String? phone,
    String? address,
  }) {
    return BusinessInfo(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusinessInfo &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          phone == other.phone &&
          address == other.address;

  @override
  int get hashCode => Object.hash(name, phone, address);

  @override
  String toString() => 'BusinessInfo(name: $name, phone: $phone, address: $address)';
}
