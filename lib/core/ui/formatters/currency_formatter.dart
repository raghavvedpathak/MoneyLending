import 'package:intl/intl.dart';

/// Core UI Currency Formatter.
///
/// Mandated by Architecture Spec §2.2:
/// Always call this helper from :core:ui for all monetary display.
/// Never format money inline in feature screens.
/// Uses 'en_IN' locale for Indian Rupee numbering format (Lakhs / Crores).
class CurrencyFormatter {
  CurrencyFormatter._();

  static final NumberFormat _inrFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final NumberFormat _inrCompactFormat = NumberFormat.compactCurrency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 1,
  );

  /// Standard currency formatting with 2 decimal places.
  /// Example: 100000 -> ₹1,00,000.00
  static String format(double amount) {
    return _inrFormat.format(amount);
  }

  /// Compact currency formatting for summary cards / tight spaces.
  /// Example: 1500000 -> ₹15.0L
  static String formatCompact(double amount) {
    return _inrCompactFormat.format(amount);
  }
}

/// Convenience top-level function matching spec signature:
/// formatCurrency(amount: Double): String
String formatCurrency(double amount) => CurrencyFormatter.format(amount);
