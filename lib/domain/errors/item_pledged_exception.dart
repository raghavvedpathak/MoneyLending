class ItemPledgedException implements Exception {
  final String itemId;
  final String holdingRecordId; // The ACTIVE TAKEN record holding the item
  final String holdingCustomerName; // Named in user-facing message

  const ItemPledgedException({
    required this.itemId,
    required this.holdingRecordId,
    String? holdingCustomerName,
    String? holdingPartyName,
  }) : holdingCustomerName = holdingCustomerName ?? holdingPartyName ?? '';

  String get holdingPartyName => holdingCustomerName;

  @override
  String toString() =>
      'ItemPledgedException: Item $itemId is currently pledged on active record $holdingRecordId by $holdingPartyName.';
}
