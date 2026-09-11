import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDF Sharing Android Native Configuration (§6.3)', () {
    test('file_paths.xml exists and contains BOTH mandatory path entries', () {
      final filePathsXml = File('android/app/src/main/res/xml/file_paths.xml');
      expect(filePathsXml.existsSync(), isTrue, reason: 'file_paths.xml must exist in res/xml');

      final content = filePathsXml.readAsStringSync();

      // Mandatory entry 1: <cache-path name="pdfs" path="pdfs/"/>
      expect(
        content.contains('<cache-path name="pdfs" path="pdfs/"/>'),
        isTrue,
        reason: 'file_paths.xml must include cache-path for pdfs/',
      );

      // Mandatory entry 2: <external-files-path name="pdfs_downloads" path="pdfs/"/>
      expect(
        content.contains('<external-files-path name="pdfs_downloads" path="pdfs/"/>'),
        isTrue,
        reason: 'file_paths.xml must include external-files-path for pdfs/',
      );
    });

    test('AndroidManifest.xml declares FileProvider with \${applicationId}.provider authority', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue);

      final content = manifestFile.readAsStringSync();

      expect(content.contains('androidx.core.content.FileProvider'), isTrue);
      expect(content.contains(r'android:authorities="${applicationId}.provider"'), isTrue);
      expect(content.contains('android:exported="false"'), isTrue);
      expect(content.contains('android:grantUriPermissions="true"'), isTrue);
      expect(content.contains(r'android:resource="@xml/file_paths"'), isTrue);
    });

    test('MainActivity.kt implements FileProvider and ShareCompat sharing channel', () {
      final mainActivityFile = File('android/app/src/main/kotlin/com/moneylending/money_lending/MainActivity.kt');
      expect(mainActivityFile.existsSync(), isTrue);

      final content = mainActivityFile.readAsStringSync();

      expect(content.contains('com.moneylending/pdf_share'), isTrue);
      expect(content.contains('FileProvider.getUriForFile'), isTrue);
      expect(content.contains('ShareCompat.IntentBuilder'), isTrue);
      expect(content.contains('.setType("application/pdf")'), isTrue);
      expect(content.contains('.setStream(uri)'), isTrue);
      expect(content.contains('.startChooser()'), isTrue);
    });
  });

  group('PdfShareService Dart Implementation (§6.3)', () {
    late Directory tempDir;
    late PdfShareService shareService;
    final channelCalls = <MethodCall>[];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pdf_share_test_');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PdfShareService.defaultChannel, (MethodCall methodCall) async {
        channelCalls.add(methodCall);
        if (methodCall.method == 'sharePdf') {
          return true;
        }
        return null;
      });

      shareService = PdfShareService(overrideDirectory: tempDir);
    });

    tearDown(() async {
      channelCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PdfShareService.defaultChannel, null);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('savePdfFile writes PDF bytes into pdfs/ subdirectory with .pdf extension', () async {
      final dummyBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]); // %PDF-1
      final file = await shareService.savePdfFile(
        bytes: dummyBytes,
        fileName: 'customer_statement_CUST-0001',
      );

      expect(file.existsSync(), isTrue);
      expect(file.path.endsWith('.pdf'), isTrue);
      expect(file.path.contains('pdfs'), isTrue);
      expect(await file.readAsBytes(), dummyBytes);
    });
  });
}
