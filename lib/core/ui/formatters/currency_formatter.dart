import 'package:intl/intl.dart';
import '../../domain/util/money.dart' as money;

export '../../domain/util/money.dart';

/// Core UI Currency Formatter.
///
/// Mandated by Architecture Spec §2.2 and [FIX-MONEY-1]:
/// Always call this helper from :core:ui or :core:domain:util for all monetary display.
/// Never format money inline in feature screens.
/// Delegates to pure Dart hand-built formatter in util/money.dart (no intl dependency).
class CurrencyFormatter {
  CurrencyFormatter._();

  static final NumberFormat _inrCompactFormat = NumberFormat.compactCurrency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 1,
  );

  /// Standard currency formatting with 2 decimal places hand-built (§2.2 [FIX-MONEY-1]).
  /// Example: 100000 -> ₹1,00,000.00
  static String format(double amount) {
    return money.formatCurrency(amount);
  }

  /// Compact currency formatting for summary cards / tight spaces.
  /// Example: 1500000 -> ₹15.0L
  static String formatCompact(double amount) {
    return _inrCompactFormat.format(amount);
  }
}
