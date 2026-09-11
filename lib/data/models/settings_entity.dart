/// Data Layer Entity for 'settings' table.
///
/// Mandated by Data Spec §4.1 & §4.6 (H-10 FIX):
/// Single-row table with id = 1.
/// Default values contract for the first-insert row (id = 1):
/// - name = "" (empty string — user must fill in business name)
/// - phone = "" (empty string)
/// - address = "" (empty string)
/// - defaultInterestRate = 2.0 (2% per month — common starting rate; user overrides in Settings screen)
class SettingsEntity {
  final int id; // Fixed at 1
  final String name;
  final String phone;
  final String address;
  // DO NOT CHANGE TO INTEGER — switching to paise storage requires a Room schema migration; see §4.2 for full rationale.
  final double defaultInterestRate;

  const SettingsEntity({
    this.id = 1,
    this.name = '',
    this.phone = '',
    this.address = '',
    this.defaultInterestRate = 2.0, // Standard 2% per month default
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'defaultInterestRate': defaultInterestRate,
    };
  }

  factory SettingsEntity.fromMap(Map<String, dynamic> map) {
    return SettingsEntity(
      id: map['id'] as int? ?? 1,
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      address: map['address'] as String? ?? '',
      defaultInterestRate: (map['defaultInterestRate'] as num?)?.toDouble() ?? 2.0,
    );
  }
}
