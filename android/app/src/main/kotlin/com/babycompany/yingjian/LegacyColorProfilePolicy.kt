package com.babycompany.yingjian

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.util.zip.InflaterInputStream
import kotlin.math.abs

internal object LegacyColorProfilePolicy {
    fun requireSrgbOrUntagged(path: String) {
        val result = when {
            hasJpegSignature(path) -> readJpegIcc(path)
            hasPngSignature(path) -> readPngIcc(path)
            else -> ProfileReadResult.Absent
        }
        val supported = when (result) {
            ProfileReadResult.Absent -> true
            ProfileReadResult.Invalid -> false
            is ProfileReadResult.Present -> isSrgb(result.bytes)
        }
        if (!supported) {
            throw AndroidPhotoExportException(
                code = AndroidPhotoExporter.ERROR_UNSUPPORTED_COLOR_SPACE,
                message = "Wide-gamut export requires Android 8 or newer",
            )
        }
    }

    internal fun isSrgb(profile: ByteArray): Boolean {
        if (profile.size < ICC_TAG_TABLE_OFFSET + 4 || ascii(profile, 36, 4) != "acsp") {
            return false
        }
        val tagCount = uint32(profile, ICC_TAG_TABLE_OFFSET)
        if (tagCount !in 1..MAX_ICC_TAGS) return false
        val tableEnd = ICC_TAG_TABLE_OFFSET + 4L + tagCount * 12L
        if (tableEnd > profile.size) return false
        val colorants = mutableMapOf<String, Triple<Double, Double, Double>>()
        for (index in 0 until tagCount.toInt()) {
            val entry = ICC_TAG_TABLE_OFFSET + 4 + index * 12
            val signature = ascii(profile, entry, 4)
            if (signature !in COLORANT_TAGS) continue
            val offset = uint32(profile, entry + 4)
            val size = uint32(profile, entry + 8)
            if (size < 20 || offset + size > profile.size) return false
            val valueOffset = offset.toInt()
            if (ascii(profile, valueOffset, 4) != "XYZ ") return false
            colorants[signature] = Triple(
                fixed16(profile, valueOffset + 8),
                fixed16(profile, valueOffset + 12),
                fixed16(profile, valueOffset + 16),
            )
        }
        return closeTo(colorants["rXYZ"], SRGB_RED) &&
            closeTo(colorants["gXYZ"], SRGB_GREEN) &&
            closeTo(colorants["bXYZ"], SRGB_BLUE)
    }

    private fun readJpegIcc(path: String): ProfileReadResult {
        val chunks = sortedMapOf<Int, ByteArray>()
        var expectedCount: Int? = null
        var sawProfile = false
        RandomAccessFile(path, "r").use { file ->
            if (file.readUnsignedShort() != JPEG_START_OF_IMAGE) return ProfileReadResult.Absent
            while (file.filePointer + 4 <= file.length()) {
                var prefix = file.readUnsignedByte()
                while (prefix != 0xFF && file.filePointer < file.length()) {
                    prefix = file.readUnsignedByte()
                }
                var marker = file.readUnsignedByte()
                while (marker == 0xFF && file.filePointer < file.length()) {
                    marker = file.readUnsignedByte()
                }
                if (marker == JPEG_START_OF_SCAN || marker == JPEG_END_OF_IMAGE) break
                if (marker in JPEG_STANDALONE_MARKERS) continue
                val segmentLength = file.readUnsignedShort()
                if (segmentLength < 2 || file.filePointer + segmentLength - 2 > file.length()) {
                    return if (sawProfile) ProfileReadResult.Invalid else ProfileReadResult.Absent
                }
                val payload = ByteArray(segmentLength - 2)
                file.readFully(payload)
                if (marker == JPEG_APP2 &&
                    payload.size >= ICC_JPEG_PREFIX.size &&
                    payload.copyOfRange(0, ICC_JPEG_PREFIX.size).contentEquals(ICC_JPEG_PREFIX)
                ) {
                    sawProfile = true
                    if (payload.size < ICC_JPEG_PREFIX.size + 2) {
                        return ProfileReadResult.Invalid
                    }
                    val sequence = payload[ICC_JPEG_PREFIX.size].toInt() and 0xFF
                    val count = payload[ICC_JPEG_PREFIX.size + 1].toInt() and 0xFF
                    if (sequence !in 1..count || count !in 1..MAX_ICC_CHUNKS) {
                        return ProfileReadResult.Invalid
                    }
                    if (expectedCount != null && expectedCount != count) {
                        return ProfileReadResult.Invalid
                    }
                    expectedCount = count
                    chunks[sequence] = payload.copyOfRange(ICC_JPEG_PREFIX.size + 2, payload.size)
                }
            }
        }
        if (!sawProfile) return ProfileReadResult.Absent
        val count = expectedCount ?: return ProfileReadResult.Invalid
        if (chunks.size != count) return ProfileReadResult.Invalid
        val output = ByteArrayOutputStream()
        for (sequence in 1..count) {
            output.write(chunks[sequence] ?: return ProfileReadResult.Invalid)
            if (output.size() > MAX_ICC_BYTES) return ProfileReadResult.Invalid
        }
        return ProfileReadResult.Present(output.toByteArray())
    }

    private fun readPngIcc(path: String): ProfileReadResult {
        RandomAccessFile(path, "r").use { file ->
            file.seek(PNG_SIGNATURE.size.toLong())
            while (file.filePointer + 12 <= file.length() && file.filePointer < MAX_PROFILE_SCAN_BYTES) {
                val length = file.readInt().toLong() and 0xFFFF_FFFFL
                val type = ByteArray(4).also(file::readFully).toString(Charsets.US_ASCII)
                if (length > MAX_ICC_BYTES || file.filePointer + length + 4 > file.length()) {
                    return if (type == "iCCP") {
                        ProfileReadResult.Invalid
                    } else {
                        ProfileReadResult.Absent
                    }
                }
                val payload = ByteArray(length.toInt())
                file.readFully(payload)
                file.skipBytes(4)
                if (type == "iCCP") {
                    val nameEnd = payload.indexOf(0)
                    if (nameEnd < 0 || nameEnd + 2 > payload.size || payload[nameEnd + 1] != 0.toByte()) {
                        return ProfileReadResult.Invalid
                    }
                    val profile = inflateBounded(payload.copyOfRange(nameEnd + 2, payload.size))
                        ?: return ProfileReadResult.Invalid
                    return ProfileReadResult.Present(profile)
                }
                if (type == "IEND") return ProfileReadResult.Absent
            }
        }
        return ProfileReadResult.Absent
    }

    private fun inflateBounded(compressed: ByteArray): ByteArray? {
        return try {
            InflaterInputStream(ByteArrayInputStream(compressed)).use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    output.write(buffer, 0, count)
                    if (output.size() > MAX_ICC_BYTES) return null
                }
                output.toByteArray()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun hasJpegSignature(path: String): Boolean = try {
        RandomAccessFile(path, "r").use { it.length() >= 2 && it.readUnsignedShort() == JPEG_START_OF_IMAGE }
    } catch (_: Exception) {
        false
    }

    private fun hasPngSignature(path: String): Boolean = try {
        RandomAccessFile(path, "r").use { file ->
            if (file.length() < PNG_SIGNATURE.size) return@use false
            ByteArray(PNG_SIGNATURE.size).also(file::readFully).contentEquals(PNG_SIGNATURE)
        }
    } catch (_: Exception) {
        false
    }

    private fun closeTo(
        actual: Triple<Double, Double, Double>?,
        expected: Triple<Double, Double, Double>,
    ): Boolean = actual != null &&
        abs(actual.first - expected.first) <= COLORANT_TOLERANCE &&
        abs(actual.second - expected.second) <= COLORANT_TOLERANCE &&
        abs(actual.third - expected.third) <= COLORANT_TOLERANCE

    private fun ascii(bytes: ByteArray, offset: Int, length: Int): String =
        if (offset < 0 || length < 0 || offset + length > bytes.size) {
            ""
        } else {
            String(bytes, offset, length, Charsets.US_ASCII)
        }

    private fun uint32(bytes: ByteArray, offset: Int): Long {
        if (offset < 0 || offset + 4 > bytes.size) return Long.MAX_VALUE
        return ((bytes[offset].toLong() and 0xFF) shl 24) or
            ((bytes[offset + 1].toLong() and 0xFF) shl 16) or
            ((bytes[offset + 2].toLong() and 0xFF) shl 8) or
            (bytes[offset + 3].toLong() and 0xFF)
    }

    private fun fixed16(bytes: ByteArray, offset: Int): Double {
        val raw = uint32(bytes, offset).toInt()
        return raw / 65536.0
    }

    private const val ICC_TAG_TABLE_OFFSET = 128
    private const val MAX_ICC_TAGS = 128L
    private const val MAX_ICC_CHUNKS = 16
    private const val MAX_ICC_BYTES = 1024 * 1024
    private const val MAX_PROFILE_SCAN_BYTES = 1024L * 1024L
    private const val COLORANT_TOLERANCE = 0.035
    private const val JPEG_START_OF_IMAGE = 0xFFD8
    private const val JPEG_START_OF_SCAN = 0xDA
    private const val JPEG_END_OF_IMAGE = 0xD9
    private const val JPEG_APP2 = 0xE2
    private val JPEG_STANDALONE_MARKERS = setOf(0x01, 0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7)
    private val ICC_JPEG_PREFIX = "ICC_PROFILE\u0000".toByteArray(Charsets.US_ASCII)
    private val PNG_SIGNATURE = byteArrayOf(
        0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    )
    private val COLORANT_TAGS = setOf("rXYZ", "gXYZ", "bXYZ")
    private val SRGB_RED = Triple(0.4361, 0.2225, 0.0139)
    private val SRGB_GREEN = Triple(0.3851, 0.7169, 0.0971)
    private val SRGB_BLUE = Triple(0.1431, 0.0606, 0.7142)

    private sealed interface ProfileReadResult {
        data object Absent : ProfileReadResult
        data object Invalid : ProfileReadResult
        data class Present(val bytes: ByteArray) : ProfileReadResult
    }
}
