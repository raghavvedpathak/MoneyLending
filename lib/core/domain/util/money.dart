// lib/core/domain/util/money.dart — pure Dart (no intl, no Flutter, no Drift)

/// [FIX-MONEY-1] Rounds to 2 decimals, half away from zero. The +/-1e-6 nudge makes a
/// binary value such as 154.325 (stored as 154.32499999999999) round to 154.33 like a
/// human would, and "+ 0.0" turns -0.0 into 0.0 so "-₹0.00" can never appear.
double roundMoney(double v) =>
    (v * 100 + (v >= 0 ? 1e-6 : -1e-6)).roundToDouble() / 100 + 0.0;

/// Sum of money values, re-rounded (0.1 + 0.2 must be 0.30, not 0.30000000000000004).
double sumMoney(Iterable<double> xs) =>
    roundMoney(xs.fold(0.0, (s, x) => s + x));

/// Parses text typed into a money field. Returns null when the text is empty, is not a
/// number, is negative, or has more than 2 decimals ("154.325" -> null).
double? parseMoney(String text) {
  final s = text.trim();
  if (!RegExp(r'^\d{1,12}(\.\d{1,2})?$').hasMatch(s)) return null;
  return roundMoney(double.parse(s));
}

/// "₹154.32", "₹2,45,000.00", "-₹500.00". Always exactly 2 decimals, Indian grouping.
String formatCurrency(double amount) {
  final v = roundMoney(amount);
  final paise = (v.abs() * 100).round();
  final frac = (paise % 100).toString().padLeft(2, '0');
  return '${v < 0 ? '-' : ''}₹${_indian('${paise ~/ 100}')}.$frac';
}

String _indian(String d) {
  if (d.length <= 3) return d;
  var rest = d.substring(0, d.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '${groups.join(',')},${d.substring(d.length - 3)}';
}
