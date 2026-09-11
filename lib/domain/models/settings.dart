/// Pure Domain Entity for App Settings.
///
/// Mandated by Data Spec §4.1 & §4.6 (H-10 FIX):
/// Default values contract for the first-insert row (id = 1):
/// - name: "" (empty string — user must fill in business name)
/// - phone: "" (empty string)
/// - address: "" (empty string)
/// - defaultInterestRate: 2.0 (2% per month — common starting rate; user overrides in Settings screen)
class Settings {
  final int id;
  final String name;
  final String phone;
  final String address;
  final double defaultInterestRate;

  const Settings({
    this.id = 1,
    this.name = '',
    this.phone = '',
    this.address = '',
    this.defaultInterestRate = 2.0,
  });

  Settings copyWith({
    int? id,
    String? name,
    String? phone,
    String? address,
    double? defaultInterestRate,
  }) {
    return Settings(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      defaultInterestRate: defaultInterestRate ?? this.defaultInterestRate,
    );
  }
}
