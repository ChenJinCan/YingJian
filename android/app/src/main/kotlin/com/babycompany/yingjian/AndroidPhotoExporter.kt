package com.babycompany.yingjian

import android.content.ContentResolver
import android.content.ContentValues
import android.annotation.TargetApi
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.io.RandomAccessFile

internal data class AndroidPhotoExportResult(
    val assetId: String,
    val width: Int,
    val height: Int,
)

internal class AndroidPhotoExportException(
    val code: String,
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

internal class AndroidPhotoExporter(
    private val contentResolver: ContentResolver,
    private val temporaryDirectory: File? = null,
) {
    fun export(sourcePath: String, pipeline: AndroidImagePipeline): AndroidPhotoExportResult {
        val metadata = AndroidExportMetadata.fromSource(sourcePath)
        var output = AndroidExportBitmapDecoder.decode(sourcePath)
        return try {
            ArgbPixelTransformer.transformInPlace(output, pipeline)
            output = AndroidBitmapGeometry.apply(
                output,
                pipeline.geometry,
                temporaryDirectory ?: File(sourcePath).parentFile
                ?: throw AndroidPhotoExportException(
                    code = ERROR_EXPORT_FAILED,
                    message = "Temporary image storage is unavailable",
                ),
            )
            val assetId = saveToPhotos(output, metadata)
            AndroidPhotoExportResult(
                assetId = assetId,
                width = output.width,
                height = output.height,
            )
        } finally {
            if (!output.isRecycled) output.recycle()
        }
    }

    private fun saveToPhotos(
        bitmap: Bitmap,
        metadata: AndroidExportMetadata,
    ): String {
        val displayName = "Yingjian_${System.currentTimeMillis()}.jpg"
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            metadata.dateTakenMillis()?.let { put(MediaStore.Images.Media.DATE_TAKEN, it) }
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
            ?: throw AndroidPhotoExportException(
                code = ERROR_EXPORT_FAILED,
                message = "Photo destination could not be created",
            )
        try {
            contentResolver.openOutputStream(uri)?.use { stream ->
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, stream)) {
                    throw AndroidPhotoExportException(
                        code = ERROR_EXPORT_FAILED,
                        message = "Photo could not be encoded",
                    )
                }
            } ?: throw AndroidPhotoExportException(
                code = ERROR_EXPORT_FAILED,
                message = "Photo destination could not be opened",
            )
            contentResolver.openFileDescriptor(uri, "rw")?.use { descriptor ->
                metadata.writeTo(ExifInterface(descriptor.fileDescriptor))
            } ?: throw AndroidPhotoExportException(
                code = ERROR_EXPORT_FAILED,
                message = "Photo metadata could not be written",
            )
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

    companion object {
        const val ERROR_UNSUPPORTED_FORMAT = "unsupportedFormat"
        const val ERROR_UNSUPPORTED_COLOR_SPACE = "unsupportedColorSpace"
        const val ERROR_DECODE_FAILED = "decodeFailed"
        const val ERROR_EXPORT_FAILED = "exportFailed"
        const val ERROR_INSUFFICIENT_MEMORY = "insufficientMemory"
        const val JPEG_QUALITY = 95
    }
}

internal object AndroidExportBitmapDecoder {
    private const val LEGACY_ROWS_PER_CHUNK = 64

    fun decode(path: String): Bitmap {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return decodeWithImageDecoder(path)
        }
        if (isHeif(path)) {
            throw AndroidPhotoExportException(
                code = AndroidPhotoExporter.ERROR_UNSUPPORTED_FORMAT,
                message = "HEIF export requires Android 9 or newer",
            )
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            LegacyColorProfilePolicy.requireSrgbOrUntagged(path)
        }
        return decodeLegacy(path)
    }

    @TargetApi(Build.VERSION_CODES.P)
    private fun decodeWithImageDecoder(path: String): Bitmap {
        return try {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(File(path))) {
                    decoder,
                    _,
                    _,
                ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                decoder.isMutableRequired = true
                decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB))
            }
        } catch (error: Exception) {
            throw AndroidPhotoExportException(
                code = AndroidPhotoExporter.ERROR_DECODE_FAILED,
                message = "Photo could not be decoded",
                cause = error,
            )
        }
    }

    internal fun decodeLegacy(path: String): Bitmap {
        val decoder = try {
            BitmapRegionDecoder.newInstance(path, false)
        } catch (error: Exception) {
            throw AndroidPhotoExportException(
                code = AndroidPhotoExporter.ERROR_DECODE_FAILED,
                message = "Photo could not be decoded",
                cause = error,
            )
        } ?: throw AndroidPhotoExportException(
            code = AndroidPhotoExporter.ERROR_DECODE_FAILED,
            message = "Photo could not be decoded",
        )

        decoder.use {
            val sourceWidth = decoder.width
            val sourceHeight = decoder.height
            val orientation = AndroidExportMetadata.readOrientation(path)
            val swapsAxes = orientation == ExifInterface.ORIENTATION_TRANSPOSE ||
                orientation == ExifInterface.ORIENTATION_ROTATE_90 ||
                orientation == ExifInterface.ORIENTATION_TRANSVERSE ||
                orientation == ExifInterface.ORIENTATION_ROTATE_270
            val output = Bitmap.createBitmap(
                if (swapsAxes) sourceHeight else sourceWidth,
                if (swapsAxes) sourceWidth else sourceHeight,
                Bitmap.Config.ARGB_8888,
            )
            val canvas = Canvas(output).apply { drawColor(Color.WHITE) }
            val matrix = orientationMatrix(orientation, sourceWidth, sourceHeight)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
            val options = BitmapFactory.Options().apply {
                inPreferredConfig = Bitmap.Config.ARGB_8888
                inScaled = false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    inPreferredColorSpace = ColorSpace.get(ColorSpace.Named.SRGB)
                }
            }

            try {
                var top = 0
                while (top < sourceHeight) {
                    val bottom = minOf(top + LEGACY_ROWS_PER_CHUNK, sourceHeight)
                    val tile = decoder.decodeRegion(
                        Rect(0, top, sourceWidth, bottom),
                        options,
                    ) ?: throw AndroidPhotoExportException(
                        code = AndroidPhotoExporter.ERROR_DECODE_FAILED,
                        message = "Photo region could not be decoded",
                    )
                    try {
                        canvas.save()
                        try {
                            canvas.concat(matrix)
                            canvas.drawBitmap(tile, 0f, top.toFloat(), paint)
                        } finally {
                            canvas.restore()
                        }
                    } finally {
                        tile.recycle()
                    }
                    top = bottom
                }
                return output
            } catch (error: Throwable) {
                output.recycle()
                throw error
            }
        }
    }

    internal fun orientationMatrix(
        orientation: Int,
        width: Int,
        height: Int,
    ): Matrix {
        val source = floatArrayOf(
            0f,
            0f,
            width.toFloat(),
            0f,
            0f,
            height.toFloat(),
        )
        val destination = when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> floatArrayOf(
                width.toFloat(), 0f, 0f, 0f, width.toFloat(), height.toFloat(),
            )
            ExifInterface.ORIENTATION_ROTATE_180 -> floatArrayOf(
                width.toFloat(), height.toFloat(), 0f, height.toFloat(), width.toFloat(), 0f,
            )
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> floatArrayOf(
                0f, height.toFloat(), width.toFloat(), height.toFloat(), 0f, 0f,
            )
            ExifInterface.ORIENTATION_TRANSPOSE -> floatArrayOf(
                0f, 0f, 0f, width.toFloat(), height.toFloat(), 0f,
            )
            ExifInterface.ORIENTATION_ROTATE_90 -> floatArrayOf(
                height.toFloat(), 0f, height.toFloat(), width.toFloat(), 0f, 0f,
            )
            ExifInterface.ORIENTATION_TRANSVERSE -> floatArrayOf(
                height.toFloat(), width.toFloat(), height.toFloat(), 0f, 0f, width.toFloat(),
            )
            ExifInterface.ORIENTATION_ROTATE_270 -> floatArrayOf(
                0f, width.toFloat(), 0f, 0f, height.toFloat(), width.toFloat(),
            )
            else -> source
        }
        return Matrix().apply {
            check(setPolyToPoly(source, 0, destination, 0, 3)) {
                "Photo orientation could not be normalized"
            }
        }
    }

    internal fun isHeif(path: String): Boolean {
        return try {
            RandomAccessFile(path, "r").use(::containsHeifFileTypeBox)
        } catch (_: Exception) {
            false
        }
    }

    private fun containsHeifFileTypeBox(file: RandomAccessFile): Boolean {
        val scanLimit = minOf(file.length(), MAX_FILE_TYPE_SCAN_BYTES)
        var offset = 0L
        while (offset + 8 <= scanLimit) {
            file.seek(offset)
            val size32 = file.readInt().toLong() and 0xFFFF_FFFFL
            val type = readBrand(file)
            var headerSize = 8L
            val boxSize = when (size32) {
                0L -> file.length() - offset
                1L -> {
                    if (offset + 16 > scanLimit) return false
                    headerSize = 16L
                    file.readLong()
                }
                else -> size32
            }
            if (boxSize < headerSize || offset + boxSize > file.length()) return false
            if (type == "ftyp") {
                if (boxSize < headerSize + 8 || offset + boxSize > scanLimit) return false
                val majorBrand = readBrand(file)
                file.readInt()
                if (majorBrand in HEIF_BRANDS) return true
                val boxEnd = offset + boxSize
                while (file.filePointer + 4 <= boxEnd) {
                    if (readBrand(file) in HEIF_BRANDS) return true
                }
                return false
            }
            offset += boxSize
        }
        return false
    }

    private fun readBrand(file: RandomAccessFile): String {
        val bytes = ByteArray(4)
        file.readFully(bytes)
        return String(bytes, Charsets.US_ASCII)
    }

    private const val MAX_FILE_TYPE_SCAN_BYTES = 1024L * 1024L
    private val HEIF_BRANDS = setOf(
        "heic",
        "heix",
        "hevc",
        "hevx",
        "heim",
        "heis",
        "hevm",
        "hevs",
        "mif1",
        "msf1",
        "avif",
        "avis",
    )
}

private inline fun <T> BitmapRegionDecoder.use(block: (BitmapRegionDecoder) -> T): T {
    return try {
        block(this)
    } finally {
        recycle()
    }
}
