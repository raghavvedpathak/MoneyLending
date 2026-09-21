package com.moneylending

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ShareCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.moneylending/pdf_share"
    private val EXACT_ALARM_CHANNEL = "com.moneylending/exact_alarm"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Exact alarm permissions channel mandated by §8 on Android 12+ (API 31+)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EXACT_ALARM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canScheduleExactAlarms" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                        result.success(alarmManager?.canScheduleExactAlarms() ?: false)
                    } else {
                        result.success(true)
                    }
                }
                "openExactAlarmSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        try {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                Uri.parse("package:$packageName")
                            )
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INTENT_ERROR", e.localizedMessage, null)
                        }
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

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
