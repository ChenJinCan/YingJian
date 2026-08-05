package com.babycompany.yingjian

import android.graphics.Bitmap
import kotlin.math.pow
import kotlin.math.roundToInt

object ArgbPixelTransformer {
    fun transform(pixel: Int, transform: ColorTransform): Int {
        val alpha = pixel ushr 24 and 0xFF
        val red = pixel ushr 16 and 0xFF
        val green = pixel ushr 8 and 0xFF
        val blue = pixel and 0xFF

        return (0xFF shl 24) or
            (channel(red, alpha, transform.redScale, transform.redBias) shl 16) or
            (channel(green, alpha, transform.greenScale, transform.greenBias) shl 8) or
            channel(blue, alpha, transform.blueScale, transform.blueBias)
    }

    fun transformInPlace(
        bitmap: Bitmap,
        transform: ColorTransform,
        rowsPerChunk: Int = 64,
    ) {
        require(bitmap.isMutable) { "Export bitmap must be mutable" }
        require(rowsPerChunk > 0) { "Rows per chunk must be positive" }
        val lookup = ChannelLookup.create(transform)
        val pixels = IntArray(bitmap.width * minOf(rowsPerChunk, bitmap.height))
        var top = 0
        while (top < bitmap.height) {
            val rowCount = minOf(rowsPerChunk, bitmap.height - top)
            val count = bitmap.width * rowCount
            bitmap.getPixels(pixels, 0, bitmap.width, 0, top, bitmap.width, rowCount)
            for (index in 0 until count) {
                pixels[index] = transform(pixels[index], transform, lookup)
            }
            bitmap.setPixels(pixels, 0, bitmap.width, 0, top, bitmap.width, rowCount)
            top += rowCount
        }
    }

    fun transformInPlace(
        bitmap: Bitmap,
        pipeline: AndroidImagePipeline,
        rowsPerChunk: Int = 64,
    ) {
        require(bitmap.isMutable) { "Export bitmap must be mutable" }
        require(rowsPerChunk > 0) { "Rows per chunk must be positive" }
        val transform = pipeline.colorTransform()
        val lookup = ChannelLookup.create(transform)
        val pixels = IntArray(bitmap.width * minOf(rowsPerChunk, bitmap.height))
        var top = 0
        while (top < bitmap.height) {
            val rowCount = minOf(rowsPerChunk, bitmap.height - top)
            val count = bitmap.width * rowCount
            bitmap.getPixels(pixels, 0, bitmap.width, 0, top, bitmap.width, rowCount)
            for (index in 0 until count) {
                val base = transform(pixels[index], transform, lookup)
                pixels[index] = applySecondaryAdjustments(base, pipeline)
            }
            bitmap.setPixels(pixels, 0, bitmap.width, 0, top, bitmap.width, rowCount)
            top += rowCount
        }
        if (pipeline.clarity != 0.0 && bitmap.width > 1 && bitmap.height > 1) {
            applyClarityInPlace(bitmap, pipeline.clarity)
        }
    }

    internal fun transformAdjustments(
        pixel: Int,
        transform: ColorTransform,
        pipeline: AndroidImagePipeline,
    ): Int {
        val base = transform(pixel, transform)
        return applySecondaryAdjustments(base, pipeline)
    }

    private fun applySecondaryAdjustments(base: Int, pipeline: AndroidImagePipeline): Int {
        var red = (base ushr 16 and 0xFF) / 255.0
        var green = (base ushr 8 and 0xFF) / 255.0
        var blue = (base and 0xFF) / 255.0
        var luminance = luminance(red, green, blue)
        val tonalDelta =
            pipeline.shadows * (1.0 - luminance) * 0.25 +
                pipeline.highlights * luminance * 0.15
        red = (red + tonalDelta).coerceIn(0.0, 1.0)
        green = (green + tonalDelta).coerceIn(0.0, 1.0)
        blue = (blue + tonalDelta).coerceIn(0.0, 1.0)
        luminance = luminance(red, green, blue)
        val saturationScale = 1.0 + pipeline.saturation
        red = (luminance + (red - luminance) * saturationScale + pipeline.tint * 0.04)
            .coerceIn(0.0, 1.0)
        green = (luminance + (green - luminance) * saturationScale - pipeline.tint * 0.025)
            .coerceIn(0.0, 1.0)
        blue = (luminance + (blue - luminance) * saturationScale + pipeline.tint * 0.04)
            .coerceIn(0.0, 1.0)
        return opaque(red, green, blue)
    }

    private fun transform(pixel: Int, transform: ColorTransform, lookup: ChannelLookup): Int {
        val alpha = pixel ushr 24 and 0xFF
        if (alpha != 255) return transform(pixel, transform)
        return (0xFF shl 24) or
            (lookup.red[pixel ushr 16 and 0xFF] shl 16) or
            (lookup.green[pixel ushr 8 and 0xFF] shl 8) or
            lookup.blue[pixel and 0xFF]
    }

    private fun channel(value: Int, alpha: Int, scale: Double, bias: Double): Int {
        val inverseAlpha = 255 - alpha
        val onWhite = (value * alpha + 255 * inverseAlpha) / (255.0 * 255.0)
        val linear = srgbToLinear(onWhite)
        val adjusted = (linear * scale + bias).coerceIn(0.0, 1.0)
        return (linearToSrgb(adjusted) * 255.0).roundToInt()
    }

    private data class ChannelLookup(
        val red: IntArray,
        val green: IntArray,
        val blue: IntArray,
    ) {
        companion object {
            fun create(transform: ColorTransform) = ChannelLookup(
                red = channelLookup(transform.redScale, transform.redBias),
                green = channelLookup(transform.greenScale, transform.greenBias),
                blue = channelLookup(transform.blueScale, transform.blueBias),
            )

            private fun channelLookup(scale: Double, bias: Double) =
                IntArray(256) { value -> channel(value, 255, scale, bias) }
        }
    }

    private fun applyClarityInPlace(bitmap: Bitmap, clarity: Double) {
        val width = bitmap.width
        val previous = IntArray(width)
        val current = IntArray(width)
        val next = IntArray(width)
        val rows = arrayOf(previous, current, next)
        val output = IntArray(width)
        bitmap.getPixels(current, 0, width, 0, 0, width, 1)
        bitmap.getPixels(next, 0, width, 0, 1, width, 1)
        for (y in 0 until bitmap.height) {
            if (y > 0) {
                current.copyInto(previous)
                next.copyInto(current)
                val nextY = minOf(y + 1, bitmap.height - 1)
                bitmap.getPixels(next, 0, width, 0, nextY, width, 1)
            } else {
                current.copyInto(previous)
            }
            for (x in 0 until width) {
                var neighborLuminance = 0.0
                for (rowIndex in rows.indices) {
                    for (offsetX in -1..1) {
                        if (rowIndex == 1 && offsetX == 0) continue
                        val column = (x + offsetX).coerceIn(0, width - 1)
                        neighborLuminance += pixelLuminance(rows[rowIndex][column])
                    }
                }
                val center = current[x]
                val centerLuminance = pixelLuminance(center)
                val delta = clarity * 0.5 * (centerLuminance - neighborLuminance / 8.0)
                output[x] = offsetChannels(center, delta)
            }
            bitmap.setPixels(output, 0, width, 0, y, width, 1)
        }
    }

    private fun pixelLuminance(pixel: Int): Double = luminance(
        (pixel ushr 16 and 0xFF) / 255.0,
        (pixel ushr 8 and 0xFF) / 255.0,
        (pixel and 0xFF) / 255.0,
    )

    private fun offsetChannels(pixel: Int, delta: Double): Int = opaque(
        ((pixel ushr 16 and 0xFF) / 255.0 + delta).coerceIn(0.0, 1.0),
        ((pixel ushr 8 and 0xFF) / 255.0 + delta).coerceIn(0.0, 1.0),
        ((pixel and 0xFF) / 255.0 + delta).coerceIn(0.0, 1.0),
    )

    private fun luminance(red: Double, green: Double, blue: Double): Double =
        red * 0.2126 + green * 0.7152 + blue * 0.0722

    private fun srgbToLinear(value: Double): Double =
        if (value <= 0.04045) value / 12.92 else ((value + 0.055) / 1.055).pow(2.4)

    private fun linearToSrgb(value: Double): Double =
        if (value <= 0.0031308) value * 12.92 else 1.055 * value.pow(1.0 / 2.4) - 0.055

    private fun opaque(red: Double, green: Double, blue: Double): Int =
        (0xFF shl 24) or
            ((red * 255.0).roundToInt() shl 16) or
            ((green * 255.0).roundToInt() shl 8) or
            (blue * 255.0).roundToInt()
}
