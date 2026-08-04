package com.babycompany.yingjian

import org.junit.Assert.assertEquals
import org.junit.Test

class AndroidPhotoAnalyzerTest {
    @Test
    fun `dark cool flat pixels produce the declared bounded categories`() {
        val pixels = IntArray(16) { argb(red = 10, green = 20, blue = 80) }

        val result = AndroidPhotoAnalyzer.analyzePixels(4, 4, pixels)

        assertEquals("underexposed", result.exposure)
        assertEquals("coolCast", result.whiteBalance)
        assertEquals("blurred", result.clarity)
    }

    @Test
    fun `balanced checker pixels produce a clear category`() {
        val pixels = IntArray(16) { index ->
            if (((index / 4) + (index % 4)) % 2 == 0) {
                argb(red = 32, green = 32, blue = 32)
            } else {
                argb(red = 224, green = 224, blue = 224)
            }
        }

        val result = AndroidPhotoAnalyzer.analyzePixels(4, 4, pixels)

        assertEquals("balanced", result.exposure)
        assertEquals("balanced", result.whiteBalance)
        assertEquals("clear", result.clarity)
    }

    @Test
    fun `transparent pixels are analyzed on the declared white background`() {
        val pixels = IntArray(4) { argb(alpha = 0, red = 0, green = 0, blue = 0) }

        val result = AndroidPhotoAnalyzer.analyzePixels(2, 2, pixels)

        assertEquals("overexposed", result.exposure)
        assertEquals("balanced", result.whiteBalance)
        assertEquals("blurred", result.clarity)
    }

    private fun argb(
        alpha: Int = 255,
        red: Int,
        green: Int,
        blue: Int,
    ): Int = (alpha shl 24) or (red shl 16) or (green shl 8) or blue
}
