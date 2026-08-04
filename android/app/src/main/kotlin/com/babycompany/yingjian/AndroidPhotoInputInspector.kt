package com.babycompany.yingjian

import android.graphics.BitmapFactory
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import kotlin.math.max

internal class AndroidPhotoInputInspector {
    fun inspect(path: String): Map<String, Any> {
        val file = File(path)
        require(file.isFile) { "Photo is unreadable" }
        val format = detectFormat(file)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            LegacyColorProfilePolicy.requireSrgbOrUntagged(path)
        }
        val decoded = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            decodeModern(file)
        } else {
            decodeLegacy(file)
        }
        val orientation = ExifInterface(file).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL,
        ).takeIf { it in 1..8 } ?: ExifInterface.ORIENTATION_NORMAL
        return mapOf(
            "contentSha256" to sha256(file),
            "pixelWidth" to decoded.width,
            "pixelHeight" to decoded.height,
            "orientation" to orientation,
            "colorSpace" to decoded.colorSpace,
            "inputFormat" to format,
        )
    }

    @RequiresApi(Build.VERSION_CODES.P)
    private fun decodeModern(file: File): DecodedPhoto {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "Photo dimensions are invalid" }
        val bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, info, _ ->
            val edge = max(info.size.width, info.size.height)
            val sample = max(1, (edge + DECODE_EDGE - 1) / DECODE_EDGE)
            decoder.setTargetSampleSize(sample)
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.memorySizePolicy = ImageDecoder.MEMORY_POLICY_LOW_RAM
        }
        return try {
            val colorSpace = when {
                bitmap.colorSpace?.isSrgb == true -> "srgb"
                bitmap.colorSpace?.id == ColorSpace.get(ColorSpace.Named.DISPLAY_P3).id -> "displayP3"
                else -> "unknown"
            }
            DecodedPhoto(bounds.outWidth, bounds.outHeight, colorSpace)
        } finally {
            bitmap.recycle()
        }
    }

    private fun decodeLegacy(file: File): DecodedPhoto {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "Photo dimensions are invalid" }
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / sample > DECODE_EDGE) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        val bitmap = requireNotNull(BitmapFactory.decodeFile(file.path, options)) {
            "Photo cannot be decoded"
        }
        return try {
            val colorSpace = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                when {
                    bitmap.colorSpace?.isSrgb == true -> "srgb"
                    bitmap.colorSpace?.id == ColorSpace.get(ColorSpace.Named.DISPLAY_P3).id -> "displayP3"
                    else -> "unknown"
                }
            } else {
                "srgb"
            }
            DecodedPhoto(bounds.outWidth, bounds.outHeight, colorSpace)
        } finally {
            bitmap.recycle()
        }
    }

    private fun detectFormat(file: File): String {
        val header = ByteArray(16)
        val count = FileInputStream(file).use { it.read(header) }
        return when {
            count >= 2 && header[0] == 0xff.toByte() && header[1] == 0xd8.toByte() -> "jpeg"
            count >= 8 && header.copyOfRange(0, 8).contentEquals(PNG_SIGNATURE) -> "png"
            count >= 12 && String(header, 4, 4, Charsets.US_ASCII) == "ftyp" -> "heic"
            else -> throw IllegalArgumentException("Photo format is unsupported")
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private data class DecodedPhoto(
        val width: Int,
        val height: Int,
        val colorSpace: String,
    )

    private companion object {
        const val DECODE_EDGE = 2048
        val PNG_SIGNATURE = byteArrayOf(
            0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
        )
    }
}
