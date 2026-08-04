package com.babycompany.yingjian

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.media.ExifInterface
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val exportExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingExport: Pair<MethodCall, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        exportExecutor.shutdown()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun needsLegacyWritePermission(): Boolean =
        Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED

    private fun exportPhoto(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val redScale = call.argument<Double>("redScale")
        val greenScale = call.argument<Double>("greenScale")
        val blueScale = call.argument<Double>("blueScale")
        val redBias = call.argument<Double>("redBias")
        val greenBias = call.argument<Double>("greenBias")
        val blueBias = call.argument<Double>("blueBias")
        if (
            sourcePath == null || redScale == null || greenScale == null || blueScale == null ||
            redBias == null || greenBias == null || blueBias == null
        ) {
            result.error("invalidArguments", "Invalid export request", null)
            return
        }
        exportExecutor.execute {
            try {
                val source = BitmapFactory.decodeFile(
                    sourcePath,
                    BitmapFactory.Options().apply {
                        inPreferredConfig = Bitmap.Config.ARGB_8888
                        inScaled = false
                    },
                ) ?: throw IllegalArgumentException("Photo could not be decoded")
                val oriented = applyExifOrientation(sourcePath, source)
                val output = Bitmap.createBitmap(
                    oriented.width,
                    oriented.height,
                    Bitmap.Config.ARGB_8888,
                )
                Canvas(output).apply {
                    drawColor(Color.WHITE)
                    val colorMatrix = ColorMatrix(
                        floatArrayOf(
                            redScale.toFloat(), 0f, 0f, 0f, (redBias * 255).toFloat(),
                            0f, greenScale.toFloat(), 0f, 0f, (greenBias * 255).toFloat(),
                            0f, 0f, blueScale.toFloat(), 0f, (blueBias * 255).toFloat(),
                            0f, 0f, 0f, 1f, 0f,
                        ),
                    )
                    drawBitmap(
                        oriented,
                        0f,
                        0f,
                        Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            isFilterBitmap = true
                            colorFilter = ColorMatrixColorFilter(colorMatrix)
                        },
                    )
                }
                val assetId = saveToPhotos(output)
                val response = mapOf(
                    "assetId" to assetId,
                    "width" to output.width,
                    "height" to output.height,
                )
                if (oriented !== source) source.recycle()
                oriented.recycle()
                output.recycle()
                mainHandler.post { result.success(response) }
            } catch (_: Throwable) {
                mainHandler.post {
                    result.error("exportFailed", "Photo could not be exported", null)
                }
            }
        }
    }

    private fun applyExifOrientation(path: String, bitmap: Bitmap): Bitmap {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return bitmap
        val orientation = ExifInterface(path).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL,
        )
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.setRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.setRotate(-90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    private fun saveToPhotos(bitmap: Bitmap): String {
        val displayName = "Yingjian_${System.currentTimeMillis()}.jpg"
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Yingjian")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            } else {
                val directory = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                    "Yingjian",
                ).apply { mkdirs() }
                put(MediaStore.Images.Media.DATA, File(directory, displayName).absolutePath)
            }
        }
        val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Photo destination could not be created")
        try {
            contentResolver.openOutputStream(uri)?.use { stream ->
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 100, stream)) {
                    throw IllegalStateException("Photo could not be encoded")
                }
            } ?: throw IllegalStateException("Photo destination could not be opened")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentResolver.update(
                    uri,
                    ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) },
                    null,
                    null,
                )
            }
            return uri.toString()
        } catch (error: Throwable) {
            contentResolver.delete(uri, null, null)
            throw error
        }
    }

    private companion object {
        const val PHOTO_EXPORT_CHANNEL = "yingjian/photo_export"
        const val WRITE_REQUEST = 8021
    }
}
