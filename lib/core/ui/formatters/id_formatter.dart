/// Authoritative Display Formatter for Customer, Transaction, and Payment IDs.
///
/// Formats:
/// - Customer ID: CUST-26/27-01
/// - Transaction ID: TRAN-092601 (TRAN-monthyearsequence)
/// - Payment ID: PAY-092601 (PAY-monthyearsequence)
class AppIdFormatter {
  AppIdFormatter._();

  static final RegExp _legacyCustNoSlash = RegExp(r'^CUST(\d{2})-(\d{2})-(\d+)$');
  static final RegExp _legacyCustDoubleHyphen = RegExp(r'^CUST-(\d{2})-(\d{2})-(\d+)$');
  static final RegExp _standardCust = RegExp(r'^CUST-(\d{2})/(\d{2})-(\d+)$');

  /// Formats customer displayId to CUST-26/27-01 format
  static String formatCustomerId(String? displayId) {
    if (displayId == null || displayId.trim().isEmpty) return '';
    final id = displayId.trim();

    // Already in standard format CUST-26/27-01
    final stdMatch = _standardCust.firstMatch(id);
    if (stdMatch != null) {
      final y1 = stdMatch.group(1)!;
      final y2 = stdMatch.group(2)!;
      final seq = stdMatch.group(3)!.padLeft(2, '0');
      return 'CUST-$y1/$y2-$seq';
    }

    // Legacy without leading hyphen: CUST26-27-01 -> CUST-26/27-01
    final match1 = _legacyCustNoSlash.firstMatch(id);
    if (match1 != null) {
      final y1 = match1.group(1)!;
      final y2 = match1.group(2)!;
      final seq = match1.group(3)!.padLeft(2, '0');
      return 'CUST-$y1/$y2-$seq';
    }

    // Legacy double hyphen: CUST-26-27-01 -> CUST-26/27-01
    final match2 = _legacyCustDoubleHyphen.firstMatch(id);
    if (match2 != null) {
      final y1 = match2.group(1)!;
      final y2 = match2.group(2)!;
      final seq = match2.group(3)!.padLeft(2, '0');
      return 'CUST-$y1/$y2-$seq';
    }

    return id;
  }

  /// Formats transactionId to TRAN-monthyearsequence format (e.g. TRAN-092601)
  static String formatTransactionId(String? transactionId) {
    if (transactionId == null || transactionId.trim().isEmpty) return '';
    final id = transactionId.trim();

    // Already has hyphen: TRAN-092601
    if (id.startsWith('TRAN-')) return id;

    // Legacy without hyphen: TRAN092601 -> TRAN-092601
    if (id.startsWith('TRAN') && id.length > 4) {
      return 'TRAN-${id.substring(4)}';
    }

    return id;
  }

  /// Formats paymentId to PAY-monthyearsequence format (e.g. PAY-092601)
  static String formatPaymentId(String? paymentId) {
    if (paymentId == null || paymentId.trim().isEmpty) return '';
    final id = paymentId.trim();

    // Already has hyphen: PAY-092601
    if (id.startsWith('PAY-')) return id;

    // Legacy without hyphen: PAY092601 -> PAY-092601
    if (id.startsWith('PAY') && id.length > 3) {
      return 'PAY-${id.substring(3)}';
    }

    return id;
  }
}
