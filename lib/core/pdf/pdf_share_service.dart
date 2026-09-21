import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../domain/domain.dart';

/// PDF Sharing Service (:core:pdf).
///
/// Mandated by Business Logic Spec §6.3:
/// - Uses Android-native `FileProvider` + `ShareCompat` on Android to eliminate `FileUriExposedException`.
/// - Never passes `file://` URIs directly on Android 7+ (API 24+).
/// - Saves generated PDFs into the designated `pdfs/` cache/downloads subfolder.
/// - Provides cross-platform fallback (e.g. Windows desktop, share_plus).
class PdfShareService {
  static const MethodChannel defaultChannel = MethodChannel('com.moneylending/pdf_share');

  final MethodChannel channel;
  final Directory? overrideDirectory;

  const PdfShareService({
    this.channel = defaultChannel,
    this.overrideDirectory,
  });

  /// Saves PDF bytes to the application cache directory under `pdfs/`.
  Future<File> savePdfFile({
    required Uint8List bytes,
    required String fileName,
    String subDir = 'pdfs',
  }) async {
    final baseDir = overrideDirectory ?? await getTemporaryDirectory();
    final pdfDir = Directory(p.join(baseDir.path, subDir));

    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }

    final sanitizedName = fileName.endsWith('.pdf') ? fileName : '$fileName.pdf';
    final file = File(p.join(pdfDir.path, sanitizedName));

    return file.writeAsBytes(bytes, flush: true);
  }

  /// Shares a PDF document securely using FileProvider + ShareCompat on Android (§6.3),
  /// or share_plus on Windows/desktop platforms.
  Future<bool> sharePdf({
    required Uint8List bytes,
    required String fileName,
    String? chooserTitle,
    String? subject,
  }) async {
    final file = await savePdfFile(bytes: bytes, fileName: fileName);

    // On Android: Delegate to native FileProvider + ShareCompat.IntentBuilder (§6.3)
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final result = await channel.invokeMethod<bool>('sharePdf', {
          'filePath': file.path,
          'chooserTitle': chooserTitle ?? 'Share PDF Document',
        });
        return result ?? true;
      } on PlatformException catch (e) {
        debugPrint('PdfShareService Android native channel failed: $e, falling back to share_plus');
      }
    }

    // Cross-platform fallback (Windows / Desktop / iOS / tests)
    final xFile = XFile(
      file.path,
      mimeType: 'application/pdf',
      name: fileName,
    );

    final shareResult = await SharePlus.instance.share(
      ShareParams(
        files: [xFile],
        subject: subject ?? fileName,
        title: chooserTitle,
      ),
    );

    return shareResult.status != ShareResultStatus.dismissed;
  }

  /// Direct share method using printing's Printing.sharePdf(bytes: ..., filename: ...) (§6.3).
  Future<bool> shareWithPrinting({
    required Uint8List bytes,
    required String fileName,
    String? subject,
  }) async {
    final sanitizedName = fileName.endsWith('.pdf') ? fileName : '$fileName.pdf';
    return Printing.sharePdf(
      bytes: bytes,
      filename: sanitizedName,
      subject: subject,
    );
  }

  /// Convenience share method for customer statement matching §6.3:
  /// File: `${dir.path}/pdfs/${customer.displayId}_statement.pdf`
  /// Subject: `Statement — ${customer.name}`
  Future<bool> shareCustomerStatement({
    required Customer customer,
    required Uint8List bytes,
  }) async {
    final fileName = '${customer.displayId}_statement.pdf';
    final subject = 'Statement — ${customer.name}';
    return sharePdf(
      bytes: bytes,
      fileName: fileName,
      subject: subject,
      chooserTitle: 'Share Customer Statement',
    );
  }
}
