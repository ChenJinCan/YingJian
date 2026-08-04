package com.babycompany.yingjian

import java.io.File
import java.nio.ByteBuffer
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidExportBitmapDecoderTest {
    @Test
    fun `recognizes HEIF brands before legacy decode`() {
        val file = File.createTempFile("heif-input", ".bin")
        try {
            file.writeBytes(
                byteArrayOf(0, 0, 0, 24) +
                    "ftyp".toByteArray(Charsets.US_ASCII) +
                    "heic".toByteArray(Charsets.US_ASCII) +
                    ByteArray(20),
            )

            assertTrue(AndroidExportBitmapDecoder.isHeif(file.absolutePath))
        } finally {
            file.delete()
        }
    }

    @Test
    fun `recognizes a late compatible HEIF brand in a bounded ftyp box`() {
        val file = File.createTempFile("heif-compatible-brand", ".bin")
        try {
            val ftyp = ByteBuffer.allocate(96).apply {
                putInt(96)
                put("ftyp".toByteArray(Charsets.US_ASCII))
                put("zzzz".toByteArray(Charsets.US_ASCII))
                putInt(0)
                while (position() < 92) {
                    put("zzzz".toByteArray(Charsets.US_ASCII))
                }
                put("hevm".toByteArray(Charsets.US_ASCII))
            }.array()
            val leadingBox = ByteBuffer.allocate(12).apply {
                putInt(12)
                put("free".toByteArray(Charsets.US_ASCII))
                putInt(0)
            }.array()
            file.writeBytes(leadingBox + ftyp)

            assertTrue(AndroidExportBitmapDecoder.isHeif(file.absolutePath))
        } finally {
            file.delete()
        }
    }

    @Test
    fun `does not classify a JPEG header as HEIF`() {
        val file = File.createTempFile("jpeg-input", ".bin")
        try {
            file.writeBytes(byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte()))

            assertFalse(AndroidExportBitmapDecoder.isHeif(file.absolutePath))
        } finally {
            file.delete()
        }
    }
}
