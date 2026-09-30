// lib/core/domain/util/number_format.dart - pure Dart

/// [FIX-NUMFORMAT-1] (v1.27) Weight and percentage display.
///
/// Weight, fine weight, purity, lend % and interest rate need one fixed display
/// so a list, the entry form, and the PDF never disagree.
/// Pure Dart, no intl, returns ASCII digits on every device locale.
String _trim(double v, int decimals) {
  var s = v.toStringAsFixed(decimals); // ASCII digits on every device locale
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s == '-0' ? '0' : s;
}

/// grams: formatWeight(5) == '5', formatWeight(4.5) == '4.5', formatWeight(4.125) == '4.125'
String formatWeight(double grams) => _trim(grams, 3);

/// percent: formatRate(2.5) == '2.5', formatRate(2) == '2', formatRate(92.5) == '92.5'
String formatRate(double percent) => _trim(percent, 2);
