package com.babycompany.yingjian

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val exportExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingExport: Pair<MethodCall, MethodChannel.Result>? = null
    private var photoPreviewRenderer: GlesPhotoPreviewRenderer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        photoPreviewRenderer = GlesPhotoPreviewRenderer(
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            textureRegistry = flutterEngine.renderer,
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PHOTO_INPUT_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "supportsHeif") {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                } else if (call.method == "inspectPhoto") {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("invalidArguments", "Photo path is required", null)
                        return@setMethodCallHandler
                    }
                    exportExecutor.execute {
                        try {
                            val inspection = AndroidPhotoInputInspector().inspect(path)
                            mainHandler.post { result.success(inspection) }
                        } catch (error: AndroidPhotoExportException) {
                            mainHandler.post {
                                result.error(error.code, error.message, null)
                            }
                        } catch (_: Throwable) {
                            mainHandler.post {
                                result.error("unreadable", "Photo could not be inspected", null)
                            }
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PHOTO_EXPORT_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "exportPhoto") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (needsLegacyWritePermission()) {
                    if (pendingExport != null) {
                        result.error("exportInProgress", "Another export is in progress", null)
                        return@setMethodCallHandler
                    }
                    pendingExport = call to result
                    requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), WRITE_REQUEST)
                    return@setMethodCallHandler
                }
                exportPhoto(call, result)
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PHOTO_ANALYSIS_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "analyzePhoto") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val sourcePath = call.argument<String>("sourcePath")
                if (sourcePath == null) {
                    result.error("invalidArguments", "Photo path is required", null)
                    return@setMethodCallHandler
                }
                exportExecutor.execute {
                    try {
                        val analysis = AndroidPhotoAnalyzer.analyze(sourcePath)
                        mainHandler.post { result.success(analysis) }
                    } catch (_: Throwable) {
                        mainHandler.post {
                            result.error(
                                "analysisUnavailable",
                                "Local photo analysis is unavailable",
                                null,
                            )
                        }
                    }
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != WRITE_REQUEST) return
        val pending = pendingExport ?: return
        pendingExport = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            exportPhoto(pending.first, pending.second)
        } else {
            pending.second.error("photoAccessDenied", "Photo access denied", null)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        photoPreviewRenderer?.close()
        photoPreviewRenderer = null
        exportExecutor.shutdown()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun needsLegacyWritePermission(): Boolean =
        Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED

    private fun exportPhoto(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val pipeline = try {
            AndroidImagePipeline.parse(call.argument<Any>("pipeline"))
        } catch (error: IllegalArgumentException) {
            result.error("invalidArguments", error.message, null)
            return
        }
        if (sourcePath == null) {
            result.error("invalidArguments", "Invalid export request", null)
            return
        }
        exportExecutor.execute {
            try {
                val response = AndroidPhotoExporter(contentResolver, cacheDir)
                    .export(sourcePath, pipeline)
                mainHandler.post {
                    result.success(
                        mapOf(
                            "assetId" to response.assetId,
                            "width" to response.width,
                            "height" to response.height,
                        ),
                    )
                }
            } catch (error: AndroidPhotoExportException) {
                mainHandler.post {
                    result.error(error.code, error.message, null)
                }
            } catch (_: OutOfMemoryError) {
                mainHandler.post {
                    result.error(
                        AndroidPhotoExporter.ERROR_INSUFFICIENT_MEMORY,
                        "Not enough memory to export this photo",
                        null,
                    )
                }
            } catch (_: SecurityException) {
                mainHandler.post {
                    result.error("photoAccessDenied", "Photo access denied", null)
                }
            } catch (_: Throwable) {
                mainHandler.post {
                    result.error(
                        AndroidPhotoExporter.ERROR_EXPORT_FAILED,
                        "Photo could not be exported",
                        null,
                    )
                }
            }
        }
    }

    private companion object {
        const val PHOTO_EXPORT_CHANNEL = "yingjian/photo_export"
        const val PHOTO_INPUT_CHANNEL = "yingjian/photo_input"
        const val PHOTO_ANALYSIS_CHANNEL = "yingjian/photo_analysis"
        const val WRITE_REQUEST = 8021
    }
}
