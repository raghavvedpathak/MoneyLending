import '../../core/utils/app_date_formatter.dart';

/// Data Layer Entity for 'customers' table.
///
/// Mandated by Data Spec §4.1:
/// - id: UUID String (Primary Key)
/// - displayId: Auto-generated CUST-0001 format, unique
/// - name: Customer name (NOT NULL)
/// - phone: Optional phone number
/// - address: Optional address
class CustomerEntity {
  final String id;
  final String displayId;
  final String name;
  final String? phone;
  final String? address;
  final String createdAt; // YYYY-MM-DD

  const CustomerEntity({
    required this.id,
    required this.displayId,
    required this.name,
    this.phone,
    this.address,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayId': displayId,
      'name': name,
      'phone': phone,
      'address': address,
      'createdAt': createdAt,
    };
  }

  factory CustomerEntity.fromMap(Map<String, dynamic> map) {
    return CustomerEntity(
      id: map['id'] as String,
      displayId: map['displayId'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      address: map['address'] as String?,
      createdAt: map['createdAt'] as String,
    );
  }

  CustomerEntity copyWith({
    String? id,
    String? displayId,
    String? name,
    String? phone,
    String? address,
    String? createdAt,
  }) {
    return CustomerEntity(
      id: id ?? this.id,
      displayId: displayId ?? this.displayId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Returns the date formatted as "10 September 2026" for UI display.
  String get formattedCreatedAt => AppDateFormatter.formatDateString(createdAt);

  /// Returns the parsed DateTime object.
  DateTime get parsedCreatedAt => AppDateFormatter.parseIso(createdAt) ?? DateTime.now();
}

/// Drift/DAO alias mandated by Data Spec §4.4 (@DataClassName('CustomerEntityData'))
typedef CustomerEntityData = CustomerEntity;
