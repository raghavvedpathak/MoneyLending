package com.moneylending.money_lending

import androidx.core.app.ShareCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.moneylending/pdf_share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "sharePdf") {
                val filePath = call.argument<String>("filePath")
                val chooserTitle = call.argument<String>("chooserTitle") ?: "Share PDF Document"

                if (filePath == null) {
                    result.error("INVALID_ARGUMENT", "File path cannot be null", null)
                    return@setMethodCallHandler
                }

                val pdfFile = File(filePath)
                if (!pdfFile.exists()) {
                    result.error("FILE_NOT_FOUND", "PDF file does not exist at $filePath", null)
                    return@setMethodCallHandler
                }

                try {
                    // Android-native FileProvider + ShareCompat mandated by §6.3:
                    // Never use File:// URIs directly on Android 7+ (API 24+)
                    val uri = FileProvider.getUriForFile(this, "${packageName}.provider", pdfFile)
                    ShareCompat.IntentBuilder(this)
                        .setType("application/pdf")
                        .setStream(uri)
                        .setChooserTitle(chooserTitle)
                        .startChooser()

                    result.success(true)
                } catch (e: Exception) {
                    result.error("SHARE_ERROR", e.localizedMessage, e.toString())
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
