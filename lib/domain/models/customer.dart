import '../../core/utils/app_date_formatter.dart';

/// Pure Domain Entity for Customer.
///
/// Mandated by Architecture Spec §2.1 & §4.1:
/// Independent of SQLite and UI.
class Customer {
  final String id;
  final String displayId;
  final String name;
  final String? phone;
  final String? address;
  final DateTime createdAt;

  const Customer({
    required this.id,
    required this.displayId,
    required this.name,
    this.phone,
    this.address,
    required this.createdAt,
  });

  /// Formatted as "10 September 2026"
  String get formattedCreatedAt => formatDate(createdAt);

  Customer copyWith({
    String? id,
    String? displayId,
    String? name,
    String? phone,
    String? address,
    DateTime? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      displayId: displayId ?? this.displayId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
