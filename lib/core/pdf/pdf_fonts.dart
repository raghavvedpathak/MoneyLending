import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Font container for PDF generation ([FIX-PDF-FONT-1] & §6.1).
///
/// Embedded Noto Sans fonts provide complete Unicode coverage including the
/// Indian Rupee symbol (₹ / \u20B9), which is missing from default PDF fonts.
class PdfFonts {
  final pw.Font regular;
  final pw.Font bold;

  const PdfFonts({
    required this.regular,
    required this.bold,
  });

  /// Loads Google Noto Sans fonts via rootBundle asset with PdfGoogleFonts fallback ([FIX-PDF-FONT-1] & §6.1).
  static Future<PdfFonts> load() async {
    try {
      final regularData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
      return PdfFonts(
        regular: pw.Font.ttf(regularData),
        bold: pw.Font.ttf(boldData),
      );
    } catch (_) {
      final regular = await PdfGoogleFonts.notoSansRegular();
      final bold = await PdfGoogleFonts.notoSansBold();
      return PdfFonts(regular: regular, bold: bold);
    }
  }

  /// Builds a [pw.ThemeData] with this font family.
  pw.ThemeData toTheme() {
    return pw.ThemeData.withFont(
      base: regular,
      bold: bold,
    );
  }
}

/// Loads [PdfFonts] on the UI isolate ([FIX-PDF-FONT-1] & §6.3).
Future<PdfFonts> loadPdfFonts() => PdfFonts.load();
