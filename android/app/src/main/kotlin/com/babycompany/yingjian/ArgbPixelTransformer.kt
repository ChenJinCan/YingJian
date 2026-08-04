package com.babycompany.yingjian

import android.graphics.Bitmap
import kotlin.math.roundToInt

object ArgbPixelTransformer {
    fun transform(pixel: Int, transform: ColorTransform): Int {
        val alpha = pixel ushr 24 and 0xFF
        val red = pixel ushr 16 and 0xFF
        val green = pixel ushr 8 and 0xFF
        val blue = pixel and 0xFF
        val inverseAlpha = 255 - alpha

        fun channel(value: Int, scale: Double, bias: Double): Int {
            val onWhite = (value * alpha + 255 * inverseAlpha) / (255.0 * 255.0)
            return ((onWhite * scale + bias).coerceIn(0.0, 1.0) * 255.0).roundToInt()
        }

        return (0xFF shl 24) or
            (channel(red, transform.redScale, transform.redBias) shl 16) or
            (channel(green, transform.greenScale, transform.greenBias) shl 8) or
            channel(blue, transform.blueScale, transform.blueBias)
    }

    fun transformInPlace(
        bitmap: Bitmap,
        transform: ColorTransform,
        rowsPerChunk: Int = 64,
    ) {
        require(bitmap.isMutable) { "Export bitmap must be mutable" }
        require(rowsPerChunk > 0) { "Rows per chunk must be positive" }
        val pixels = IntArray(bitmap.width * minOf(rowsPerChunk, bitmap.height))
        var top = 0
        while (top < bitmap.height) {
            val rowCount = minOf(rowsPerChunk, bitmap.height - top)
            val count = bitmap.width * rowCount
            bitmap.getPixels(pixels, 0, bitmap.width, 0, top, bitmap.width, rowCount)
            for (index in 0 until count) {
                pixels[index] = transform(pixels[index], transform)
            }
            bitmap.setPixels(pixels, 0, bitmap.width, 0, top, bitmap.width, rowCount)
            top += rowCount
        }
    }
}
