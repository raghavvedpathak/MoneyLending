/// Thrown when attempting to delete a lender that still has records (§4.3, [FIX-LENDER-CODEPATH-1]).
class LenderHasRecordsException implements Exception {
  final int recordCount;
  final String? lenderId;

  const LenderHasRecordsException(this.recordCount, {this.lenderId});

  @override
  String toString() =>
      'LenderHasRecordsException: Cannot delete lender${lenderId != null ? " $lenderId" : ""} because $recordCount record(s) are associated with this lender.';
}
