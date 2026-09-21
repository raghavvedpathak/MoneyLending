/// Backup DTO for Customer (§7.1).
///
/// Kept separate from domain [Customer] to protect against serialization leakage.
class BackupCustomer {
  final String id;
  final String displayId;
  final String name;
  final String phone;
  final String? address;
  final String createdAt;

  const BackupCustomer({
    required this.id,
    this.displayId = '',
    required this.name,
    this.phone = '',
    this.address,
    required this.createdAt,
  });

  BackupCustomer copyWith({
    String? id,
    String? displayId,
    String? name,
    String? phone,
    String? address,
    String? createdAt,
  }) {
    return BackupCustomer(
      id: id ?? this.id,
      displayId: displayId ?? this.displayId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory BackupCustomer.fromJson(Map<String, dynamic> json) {
    return BackupCustomer(
      id: json['id']?.toString() ?? '',
      displayId: json['displayId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      address: json['address']?.toString(),
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayId': displayId,
      'name': name,
      'phone': phone,
      if (address != null) 'address': address,
      'createdAt': createdAt,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupCustomer &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          displayId == other.displayId &&
          name == other.name &&
          phone == other.phone &&
          address == other.address &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      id.hashCode ^
      displayId.hashCode ^
      name.hashCode ^
      phone.hashCode ^
      address.hashCode ^
      createdAt.hashCode;
}
