package com.babycompany.yingjian

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.graphics.Paint
import android.media.FaceDetector
import android.os.Build
import androidx.exifinterface.media.ExifInterface
import java.io.File
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

internal data class AndroidPixelAnalysis(
    val exposure: String,
    val whiteBalance: String,
    val clarity: String,
)

internal object AndroidPhotoAnalyzer {
    const val ANALYSIS_VERSION = "local-pixels-v1"
    const val CAPABILITY_VERSION = "android-bitmap-face-v1"
    private const val MAX_ANALYSIS_EDGE = 128

    fun analyze(path: String): Map<String, Any> {
        val bitmap = decodeBounded(path)
        return try {
            val pixels = IntArray(bitmap.width * bitmap.height)
            bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
            val analysis = analyzePixels(bitmap.width, bitmap.height, pixels)
            mapOf(
                "analysisVersion" to ANALYSIS_VERSION,
                "capabilityVersion" to CAPABILITY_VERSION,
                "confidence" to "medium",
                "exposure" to analysis.exposure,
                "whiteBalance" to analysis.whiteBalance,
                "clarity" to analysis.clarity,
                "portrait" to "unavailable",
                "scene" to if (hasFace(bitmap)) "people" else "unknown",
            )
        } finally {
            bitmap.recycle()
        }
    }

    internal fun analyzePixels(
        width: Int,
        height: Int,
        pixels: IntArray,
    ): AndroidPixelAnalysis {
        require(width > 0 && height > 0 && pixels.size == width * height) {
            "Invalid analysis pixels"
        }
        var luminanceTotal = 0.0
        var redTotal = 0.0
        var blueTotal = 0.0
        var edgeTotal = 0.0
        val previousRow = DoubleArray(width)
        for (y in 0 until height) {
            var previous = 0.0
            for (x in 0 until width) {
                val pixel = pixels[(y * width) + x]
                val alpha = ((pixel ushr 24) and 0xff) / 255.0
                val red = ((((pixel ushr 16) and 0xff) * alpha) + (255.0 * (1 - alpha))) / 255.0
                val green = ((((pixel ushr 8) and 0xff) * alpha) + (255.0 * (1 - alpha))) / 255.0
                val blue = (((pixel and 0xff) * alpha) + (255.0 * (1 - alpha))) / 255.0
                val luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
                luminanceTotal += luminance
                redTotal += red
                blueTotal += blue
                if (x > 0) edgeTotal += abs(luminance - previous)
                if (y > 0) edgeTotal += abs(luminance - previousRow[x])
                previous = luminance
                previousRow[x] = luminance
            }
        }
        val count = (width * height).toDouble()
        val meanLuminance = luminanceTotal / count
        val redBlueDelta = (redTotal - blueTotal) / count
        val edgeMean = edgeTotal / max(1.0, (count * 2.0) - width - height)
        return AndroidPixelAnalysis(
            exposure = when {
                meanLuminance < 0.34 -> "underexposed"
                meanLuminance > 0.72 -> "overexposed"
                else -> "balanced"
            },
            whiteBalance = when {
                redBlueDelta > 0.10 -> "warmCast"
                redBlueDelta < -0.10 -> "coolCast"
                else -> "balanced"
            },
            clarity = when {
                edgeMean < 0.018 -> "blurred"
                edgeMean < 0.040 -> "soft"
                else -> "clear"
            },
        )
    }

    private fun decodeBounded(path: String): Bitmap {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val source = ImageDecoder.createSource(File(path))
            return try {
                ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB))
                    val size = boundedSize(info.size.width, info.size.height)
                    decoder.setTargetSize(size.first, size.second)
                }
            } catch (error: Exception) {
                throw IllegalArgumentException("Photo could not be analyzed", error)
            }
        }

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) {
            "Photo could not be analyzed"
        }
        var sampleSize = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sampleSize * 2) >= MAX_ANALYSIS_EDGE) {
            sampleSize *= 2
        }
        val decoded = BitmapFactory.decodeFile(
            path,
            BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    inPreferredColorSpace = ColorSpace.get(ColorSpace.Named.SRGB)
                }
            },
        ) ?: throw IllegalArgumentException("Photo could not be analyzed")
        val oriented = try {
            val orientation = ExifInterface(path).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
            val matrix = AndroidExportBitmapDecoder.orientationMatrix(
                orientation,
                decoded.width,
                decoded.height,
            )
            Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        } catch (error: Exception) {
            decoded.recycle()
            throw IllegalArgumentException("Photo could not be analyzed", error)
        }
        if (oriented !== decoded) decoded.recycle()
        val target = boundedSize(oriented.width, oriented.height)
        if (target.first == oriented.width && target.second == oriented.height) return oriented
        return Bitmap.createScaledBitmap(oriented, target.first, target.second, true).also {
            oriented.recycle()
        }
    }

    private fun boundedSize(width: Int, height: Int): Pair<Int, Int> {
        require(width > 0 && height > 0) { "Photo could not be analyzed" }
        val longest = max(width, height)
        if (longest <= MAX_ANALYSIS_EDGE) return width to height
        val scale = MAX_ANALYSIS_EDGE.toDouble() / longest
        return max(1, (width * scale).roundToInt()) to max(1, (height * scale).roundToInt())
    }

    private fun hasFace(bitmap: Bitmap): Boolean {
        val evenWidth = bitmap.width - (bitmap.width % 2)
        if (evenWidth < 2 || bitmap.height < 2) return false
        val faceBitmap = Bitmap.createBitmap(evenWidth, bitmap.height, Bitmap.Config.RGB_565)
        return try {
            Canvas(faceBitmap).drawBitmap(
                bitmap,
                0f,
                0f,
                Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG),
            )
            val faces = arrayOfNulls<FaceDetector.Face>(1)
            FaceDetector(faceBitmap.width, faceBitmap.height, faces.size)
                .findFaces(faceBitmap, faces) > 0
        } catch (_: RuntimeException) {
            false
        } finally {
            faceBitmap.recycle()
        }
    }
}
