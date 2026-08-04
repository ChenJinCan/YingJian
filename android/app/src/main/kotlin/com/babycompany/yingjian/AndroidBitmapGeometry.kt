package com.babycompany.yingjian

import android.graphics.Bitmap
import android.graphics.Matrix
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.floor
import kotlin.math.roundToInt

internal object AndroidBitmapGeometry {
    private const val ROWS_PER_CHUNK = 64
    private const val BYTES_PER_PIXEL = Int.SIZE_BYTES
    private const val OPAQUE_WHITE = -1

    /**
     * Applies geometry while keeping at most one full in-memory Bitmap.
     * A non-identity call consumes and recycles [source].
     */
    fun apply(source: Bitmap, geometry: ImageGeometry, temporaryDirectory: File): Bitmap {
        if (geometry.isIdentity) return source
        val crop = geometry.pixelCrop(source.width, source.height)
        val outputWidth = if (geometry.quarterTurns % 2 == 0) crop.width else crop.height
        val outputHeight = if (geometry.quarterTurns % 2 == 0) crop.height else crop.width
        val inverse = Matrix()
        check(forwardMatrix(crop, geometry).invert(inverse)) {
            "Photo geometry could not be inverted"
        }
        val inverseValues = FloatArray(9).also(inverse::getValues)
        val sourceWidth = source.width
        val sourceHeight = source.height
        val rawFile = File.createTempFile("yingjian-geometry-", ".rgba", temporaryDirectory)
        var output: Bitmap? = null
        try {
            writePixels(source, rawFile)
            val sourcePixels = mapPixels(rawFile, sourceWidth, sourceHeight)
            check(unlinkTemporary(rawFile)) {
                "Temporary geometry storage could not be unlinked"
            }
            source.recycle()

            output = Bitmap.createBitmap(outputWidth, outputHeight, Bitmap.Config.ARGB_8888)
            val row = IntArray(outputWidth)
            for (y in 0 until outputHeight) {
                val outputY = y + 0.5
                for (x in 0 until outputWidth) {
                    val outputX = x + 0.5
                    val sourceX =
                        inverseValues[Matrix.MSCALE_X] * outputX +
                            inverseValues[Matrix.MSKEW_X] * outputY +
                            inverseValues[Matrix.MTRANS_X]
                    val sourceY =
                        inverseValues[Matrix.MSKEW_Y] * outputX +
                            inverseValues[Matrix.MSCALE_Y] * outputY +
                            inverseValues[Matrix.MTRANS_Y]
                    row[x] = bilinearSample(
                        sourcePixels,
                        sourceWidth,
                        sourceHeight,
                        sourceX,
                        sourceY,
                    )
                }
                output.setPixels(row, 0, outputWidth, 0, y, outputWidth, 1)
            }
            return output
        } catch (error: Throwable) {
            output?.recycle()
            throw error
        } finally {
            unlinkTemporary(rawFile)
        }
    }

    internal fun forwardMatrix(crop: PixelCrop, geometry: ImageGeometry): Matrix {
        val straighten = Matrix().apply {
            setRotate(
                geometry.straightenDegrees.toFloat(),
                (crop.left + crop.right) / 2f,
                (crop.top + crop.bottom) / 2f,
            )
        }
        val cropTranslation = Matrix().apply {
            setTranslate(-crop.left.toFloat(), -crop.top.toFloat())
        }
        val cropped = Matrix().apply { setConcat(cropTranslation, straighten) }
        val quarterTurn = quarterTurnMatrix(crop.width.toFloat(), crop.height.toFloat(), geometry)
        return Matrix().apply { setConcat(quarterTurn, cropped) }
    }

    private fun writePixels(source: Bitmap, file: File) {
        val rows = minOf(ROWS_PER_CHUNK, source.height)
        val pixels = IntArray(source.width * rows)
        val bytes = ByteBuffer.allocateDirect(pixels.size * BYTES_PER_PIXEL)
            .order(ByteOrder.nativeOrder())
        FileOutputStream(file).channel.use { channel ->
            var top = 0
            while (top < source.height) {
                val rowCount = minOf(rows, source.height - top)
                val count = source.width * rowCount
                source.getPixels(pixels, 0, source.width, 0, top, source.width, rowCount)
                bytes.clear()
                bytes.asIntBuffer().put(pixels, 0, count)
                bytes.limit(count * BYTES_PER_PIXEL)
                while (bytes.hasRemaining()) channel.write(bytes)
                top += rowCount
            }
        }
    }

    private fun mapPixels(file: File, width: Int, height: Int): ByteBuffer {
        val byteCount = Math.multiplyExact(
            Math.multiplyExact(width.toLong(), height.toLong()),
            BYTES_PER_PIXEL.toLong(),
        )
        require(byteCount <= Int.MAX_VALUE) { "Photo is too large for bounded geometry" }
        return RandomAccessFile(file, "r").channel.use { channel ->
            channel.map(java.nio.channels.FileChannel.MapMode.READ_ONLY, 0, byteCount)
                .order(ByteOrder.nativeOrder())
        }
    }

    internal fun unlinkTemporary(file: File): Boolean {
        if (!file.exists() || file.delete()) return true
        runCatching {
            RandomAccessFile(file, "rw").use { it.setLength(0) }
        }
        return !file.exists()
    }

    private fun bilinearSample(
        pixels: ByteBuffer,
        width: Int,
        height: Int,
        sourceX: Double,
        sourceY: Double,
    ): Int {
        val pixelX = sourceX - 0.5
        val pixelY = sourceY - 0.5
        val left = floor(pixelX).toInt()
        val top = floor(pixelY).toInt()
        val horizontal = pixelX - left
        val vertical = pixelY - top
        val topLeft = pixelAt(pixels, width, height, left, top)
        val topRight = pixelAt(pixels, width, height, left + 1, top)
        val bottomLeft = pixelAt(pixels, width, height, left, top + 1)
        val bottomRight = pixelAt(pixels, width, height, left + 1, top + 1)
        return opaque(
            bilinearChannel(topLeft, topRight, bottomLeft, bottomRight, 16, horizontal, vertical),
            bilinearChannel(topLeft, topRight, bottomLeft, bottomRight, 8, horizontal, vertical),
            bilinearChannel(topLeft, topRight, bottomLeft, bottomRight, 0, horizontal, vertical),
        )
    }

    private fun pixelAt(pixels: ByteBuffer, width: Int, height: Int, x: Int, y: Int): Int {
        if (x !in 0 until width || y !in 0 until height) return OPAQUE_WHITE
        return pixels.getInt((y * width + x) * BYTES_PER_PIXEL)
    }

    private fun bilinearChannel(
        topLeft: Int,
        topRight: Int,
        bottomLeft: Int,
        bottomRight: Int,
        shift: Int,
        horizontal: Double,
        vertical: Double,
    ): Int {
        val top = channel(topLeft, shift) * (1 - horizontal) +
            channel(topRight, shift) * horizontal
        val bottom = channel(bottomLeft, shift) * (1 - horizontal) +
            channel(bottomRight, shift) * horizontal
        return (top * (1 - vertical) + bottom * vertical).roundToInt().coerceIn(0, 255)
    }

    private fun channel(pixel: Int, shift: Int): Int = pixel ushr shift and 0xFF

    private fun opaque(red: Int, green: Int, blue: Int): Int =
        (0xFF shl 24) or (red shl 16) or (green shl 8) or blue

    private fun quarterTurnMatrix(
        width: Float,
        height: Float,
        geometry: ImageGeometry,
    ): Matrix {
        if (geometry.quarterTurns == 0) return Matrix()
        val source = floatArrayOf(0f, 0f, width, 0f, 0f, height)
        val destination = when (geometry.quarterTurns) {
            1 -> floatArrayOf(height, 0f, height, width, 0f, 0f)
            2 -> floatArrayOf(width, height, 0f, height, width, 0f)
            3 -> floatArrayOf(0f, width, 0f, 0f, height, width)
            else -> error("Quarter turns are outside the supported range")
        }
        return Matrix().apply {
            check(setPolyToPoly(source, 0, destination, 0, 3)) {
                "Photo rotation could not be constructed"
            }
        }
    }
}
