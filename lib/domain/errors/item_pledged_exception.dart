/// Thrown when attempting an action on an item that is actively pledged
/// on another loan (Step 6.1 / [FIX-ITEM-CUSTODY-2]).
class ItemPledgedException implements Exception {
  final String itemId;
  final String holdingRecordId; // The ACTIVE TAKEN record holding the item
  final String holdingCustomerName; // Named in user-facing message

  const ItemPledgedException({
    required this.itemId,
    required this.holdingRecordId,
    required this.holdingCustomerName,
  });

  @override
  String toString() =>
      'ItemPledgedException: Item $itemId is currently pledged on active record $holdingRecordId by $holdingCustomerName.';
}
