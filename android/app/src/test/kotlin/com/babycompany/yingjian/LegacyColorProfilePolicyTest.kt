package com.babycompany.yingjian

import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.util.zip.DeflaterOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class LegacyColorProfilePolicyTest {
    @Test
    fun `allows a tagged sRGB JPEG on Android 7 policy`() {
        val source = File.createTempFile("srgb-profile", ".jpg")
        try {
            source.writeBytes(jpegWithProfile(iccProfile(SRGB_RED, SRGB_GREEN, SRGB_BLUE)))

            LegacyColorProfilePolicy.requireSrgbOrUntagged(source.absolutePath)
        } finally {
            source.delete()
        }
    }

    @Test
    fun `rejects a tagged Display P3 JPEG on Android 7 policy`() {
        val source = File.createTempFile("display-p3-profile", ".jpg")
        try {
            source.writeBytes(jpegWithProfile(iccProfile(P3_RED, P3_GREEN, P3_BLUE)))

            try {
                LegacyColorProfilePolicy.requireSrgbOrUntagged(source.absolutePath)
                fail("Display P3 should be rejected before legacy decode")
            } catch (error: AndroidPhotoExportException) {
                assertEquals(AndroidPhotoExporter.ERROR_UNSUPPORTED_COLOR_SPACE, error.code)
            }
        } finally {
            source.delete()
        }
    }

    @Test
    fun `rejects a compressed Display P3 PNG profile on Android 7 policy`() {
        val source = File.createTempFile("display-p3-profile", ".png")
        try {
            source.writeBytes(pngWithProfile(iccProfile(P3_RED, P3_GREEN, P3_BLUE)))

            try {
                LegacyColorProfilePolicy.requireSrgbOrUntagged(source.absolutePath)
                fail("Display P3 should be rejected before legacy decode")
            } catch (error: AndroidPhotoExportException) {
                assertEquals(AndroidPhotoExporter.ERROR_UNSUPPORTED_COLOR_SPACE, error.code)
            }
        } finally {
            source.delete()
        }
    }

    @Test
    fun `rejects an incomplete multipart JPEG ICC profile`() {
        val source = File.createTempFile("incomplete-profile", ".jpg")
        try {
            val prefix = "ICC_PROFILE\u0000".toByteArray(Charsets.US_ASCII)
            source.writeBytes(jpegWithPayload(prefix + byteArrayOf(1, 2) + ByteArray(32)))

            assertUnsupportedColorSpace(source)
        } finally {
            source.delete()
        }
    }

    @Test
    fun `rejects a malformed compressed PNG ICC profile`() {
        val source = File.createTempFile("malformed-profile", ".png")
        try {
            source.writeBytes(
                pngWithIccPayload(
                    "profile".toByteArray(Charsets.US_ASCII) +
                        byteArrayOf(0, 0, 1, 2, 3, 4),
                ),
            )

            assertUnsupportedColorSpace(source)
        } finally {
            source.delete()
        }
    }

    private fun iccProfile(
        red: Triple<Double, Double, Double>,
        green: Triple<Double, Double, Double>,
        blue: Triple<Double, Double, Double>,
    ): ByteArray {
        val dataOffset = 168
        return ByteBuffer.allocate(dataOffset + 60).apply {
            putInt(0, capacity())
            putAscii(36, "acsp")
            putInt(128, 3)
            listOf("rXYZ" to red, "gXYZ" to green, "bXYZ" to blue)
                .forEachIndexed { index, (tag, value) ->
                    val entry = 132 + index * 12
                    val valueOffset = dataOffset + index * 20
                    putAscii(entry, tag)
                    putInt(entry + 4, valueOffset)
                    putInt(entry + 8, 20)
                    putAscii(valueOffset, "XYZ ")
                    putFixed16(valueOffset + 8, value.first)
                    putFixed16(valueOffset + 12, value.second)
                    putFixed16(valueOffset + 16, value.third)
                }
        }.array()
    }

    private fun jpegWithProfile(profile: ByteArray): ByteArray {
        val prefix = "ICC_PROFILE\u0000".toByteArray(Charsets.US_ASCII)
        val payload = prefix + byteArrayOf(1, 1) + profile
        return jpegWithPayload(payload)
    }

    private fun jpegWithPayload(payload: ByteArray): ByteArray {
        return ByteBuffer.allocate(payload.size + 8).apply {
            put(0xFF.toByte())
            put(0xD8.toByte())
            put(0xFF.toByte())
            put(0xE2.toByte())
            putShort((payload.size + 2).toShort())
            put(payload)
            put(0xFF.toByte())
            put(0xD9.toByte())
        }.array()
    }

    private fun pngWithProfile(profile: ByteArray): ByteArray {
        val compressed = ByteArrayOutputStream().also { output ->
            DeflaterOutputStream(output).use { it.write(profile) }
        }.toByteArray()
        val payload = "profile".toByteArray(Charsets.US_ASCII) +
            byteArrayOf(0, 0) + compressed
        return pngWithIccPayload(payload)
    }

    private fun pngWithIccPayload(payload: ByteArray): ByteArray {
        val signature = byteArrayOf(
            0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        )
        return ByteBuffer.allocate(signature.size + 12 + payload.size + 12).apply {
            put(signature)
            putInt(payload.size)
            put("iCCP".toByteArray(Charsets.US_ASCII))
            put(payload)
            putInt(0)
            putInt(0)
            put("IEND".toByteArray(Charsets.US_ASCII))
            putInt(0)
        }.array()
    }

    private fun assertUnsupportedColorSpace(source: File) {
        try {
            LegacyColorProfilePolicy.requireSrgbOrUntagged(source.absolutePath)
            fail("Invalid ICC data should be rejected before legacy decode")
        } catch (error: AndroidPhotoExportException) {
            assertEquals(AndroidPhotoExporter.ERROR_UNSUPPORTED_COLOR_SPACE, error.code)
        }
    }

    private fun ByteBuffer.putAscii(offset: Int, value: String) {
        val position = position()
        position(offset)
        put(value.toByteArray(Charsets.US_ASCII))
        position(position)
    }

    private fun ByteBuffer.putFixed16(offset: Int, value: Double) {
        putInt(offset, (value * 65536.0).toInt())
    }

    private companion object {
        val SRGB_RED = Triple(0.4361, 0.2225, 0.0139)
        val SRGB_GREEN = Triple(0.3851, 0.7169, 0.0971)
        val SRGB_BLUE = Triple(0.1431, 0.0606, 0.7142)
        val P3_RED = Triple(0.5151, 0.2412, -0.0010)
        val P3_GREEN = Triple(0.2920, 0.6922, 0.0419)
        val P3_BLUE = Triple(0.1571, 0.0666, 0.7841)
    }
}
