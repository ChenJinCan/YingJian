package com.babycompany.yingjian

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.ColorSpace
import android.net.Uri
import android.os.Build
import android.system.Os
import androidx.exifinterface.media.ExifInterface
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.MessageDigest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidPhotoExporterInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun inputInspectionActuallyDecodesAndRecordsStableContentIdentity() {
        val source = File(context.cacheDir, "inspect-source.jpg")
        createJpeg(source, width = 8, height = 6)
        ExifInterface(source.absolutePath).apply {
            setAttribute(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_ROTATE_90.toString(),
            )
            saveAttributes()
        }

        try {
            val result = AndroidPhotoInputInspector().inspect(source.absolutePath)

            assertEquals(sha256(source), result["contentSha256"])
            assertEquals(8, result["pixelWidth"])
            assertEquals(6, result["pixelHeight"])
            assertEquals(ExifInterface.ORIENTATION_ROTATE_90, result["orientation"])
            assertEquals("jpeg", result["inputFormat"])
            assertEquals("srgb", result["colorSpace"])
        } finally {
            source.delete()
        }
    }

    @Test
    fun exportNormalizesOrientationAndKeepsOnlySafeMetadataWithoutChangingSource() {
        val source = File(context.cacheDir, "export-source.jpg")
        createJpeg(source, width = 4, height = 2)
        ExifInterface(source.absolutePath).apply {
            setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_ROTATE_90.toString())
            setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, "2026:08:04 13:14:15")
            setAttribute(ExifInterface.TAG_MAKE, "Private camera make")
            setAttribute(ExifInterface.TAG_GPS_LATITUDE, "31/1,12/1,0/1")
            setAttribute(ExifInterface.TAG_GPS_LATITUDE_REF, "N")
            setAttribute(ExifInterface.TAG_GPS_LONGITUDE, "121/1,30/1,0/1")
            setAttribute(ExifInterface.TAG_GPS_LONGITUDE_REF, "E")
            saveAttributes()
        }
        val sourceHash = sha256(source)

        val result = AndroidPhotoExporter(context.contentResolver).export(
            source.absolutePath,
            ImagePipelineV1(exposureEv = 0.0, contrast = 0.0, warmth = 0.0),
        )

        val outputUri = Uri.parse(result.assetId)
        try {
            assertEquals(2, result.width)
            assertEquals(4, result.height)
            assertEquals(sourceHash, sha256(source))
            context.contentResolver.openFileDescriptor(outputUri, "r")!!.use { descriptor ->
                val exif = ExifInterface(descriptor.fileDescriptor)
                assertEquals(
                    ExifInterface.ORIENTATION_NORMAL,
                    exif.getAttributeInt(
                        ExifInterface.TAG_ORIENTATION,
                        ExifInterface.ORIENTATION_UNDEFINED,
                    ),
                )
                assertEquals(
                    "2026:08:04 13:14:15",
                    exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL),
                )
                assertNull(exif.getAttribute(ExifInterface.TAG_MAKE))
                assertNull(exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE))
                assertNull(exif.getAttribute(ExifInterface.TAG_GPS_LONGITUDE))
            }
            context.contentResolver.openInputStream(outputUri)!!.use { stream ->
                val bitmap = BitmapFactory.decodeStream(stream)
                assertEquals(2, bitmap.width)
                assertEquals(4, bitmap.height)
                assertTrue(bitmap.colorSpace?.isSrgb == true)
                bitmap.recycle()
            }
        } finally {
            context.contentResolver.delete(outputUri, null, null)
            source.delete()
            assertNoGeometryTemporaryFiles()
        }
    }

    @Test
    fun legacyChunkedDecoderMatchesImageDecoderForEveryExifOrientation() {
        val orientations = listOf(
            ExifInterface.ORIENTATION_NORMAL,
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL,
            ExifInterface.ORIENTATION_ROTATE_180,
            ExifInterface.ORIENTATION_FLIP_VERTICAL,
            ExifInterface.ORIENTATION_TRANSPOSE,
            ExifInterface.ORIENTATION_ROTATE_90,
            ExifInterface.ORIENTATION_TRANSVERSE,
            ExifInterface.ORIENTATION_ROTATE_270,
        )
        for (orientation in orientations) {
            val source = File(context.cacheDir, "legacy-orientation-$orientation.jpg")
            createJpeg(source, width = 6, height = 4)
            ExifInterface(source.absolutePath).apply {
                setAttribute(ExifInterface.TAG_ORIENTATION, orientation.toString())
                saveAttributes()
            }
            val expected = AndroidExportBitmapDecoder.decode(source.absolutePath)
            val actual = AndroidExportBitmapDecoder.decodeLegacy(source.absolutePath)
            try {
                assertEquals(expected.width, actual.width)
                assertEquals(expected.height, actual.height)
                for (y in 0 until actual.height) {
                    for (x in 0 until actual.width) {
                        assertColorsNear(expected.getPixel(x, y), actual.getPixel(x, y))
                    }
                }
            } finally {
                expected.recycle()
                actual.recycle()
                source.delete()
            }
        }
    }

    @Test
    fun transparentPngIsCompositedOverWhiteByTheFullExportPath() {
        val source = File(context.cacheDir, "transparent-source.png")
        Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888).also { bitmap ->
            bitmap.setPixel(0, 0, Color.argb(128, 255, 0, 0))
            source.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
        }

        val result = AndroidPhotoExporter(context.contentResolver).export(
            source.absolutePath,
            ImagePipelineV1(0.0, 0.0, 0.0),
        )
        val outputUri = Uri.parse(result.assetId)
        try {
            val output = readBitmap(outputUri)
            val pixel = output.getPixel(0, 0)
            assertEquals(255, Color.alpha(pixel))
            assertTrue(Color.red(pixel) >= 245)
            assertTrue(Color.green(pixel) in 115..140)
            assertTrue(Color.blue(pixel) in 115..140)
            assertTrue(output.colorSpace?.isSrgb == true)
            output.recycle()
        } finally {
            context.contentResolver.delete(outputUri, null, null)
            source.delete()
        }
    }

    @Test
    fun nonNeutralRecipeProducesTheDeclaredBrightnessAndWarmthTrend() {
        val source = File(context.cacheDir, "gray-source.jpg")
        Bitmap.createBitmap(8, 8, Bitmap.Config.ARGB_8888).also { bitmap ->
            bitmap.eraseColor(Color.rgb(96, 96, 96))
            source.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 100, it) }
            bitmap.recycle()
        }
        val exporter = AndroidPhotoExporter(context.contentResolver)
        val neutral = exporter.export(source.absolutePath, ImagePipelineV1(0.0, 0.0, 0.0))
        val adjusted = exporter.export(source.absolutePath, ImagePipelineV1(0.5, 0.2, 0.6))
        val neutralUri = Uri.parse(neutral.assetId)
        val adjustedUri = Uri.parse(adjusted.assetId)
        try {
            val neutralPixel = readBitmap(neutralUri).usePixel()
            val adjustedPixel = readBitmap(adjustedUri).usePixel()
            assertTrue(Color.red(adjustedPixel) > Color.red(neutralPixel))
            assertTrue(Color.green(adjustedPixel) > Color.green(neutralPixel))
            assertTrue(Color.red(adjustedPixel) > Color.blue(adjustedPixel))
        } finally {
            context.contentResolver.delete(neutralUri, null, null)
            context.contentResolver.delete(adjustedUri, null, null)
            source.delete()
        }
    }

    @Test
    fun V2CropQuarterTurnAndAdjustmentsReachTheFinalArtifact() {
        val source = File(context.cacheDir, "v2-geometry-source.jpg")
        createJpeg(source, width = 10, height = 6)
        val pipeline = AndroidImagePipeline(
            exposureEv = 0.5,
            contrast = 0.0,
            warmth = 0.6,
            highlights = 0.2,
            shadows = 0.2,
            tint = 0.1,
            saturation = 0.2,
            clarity = 0.1,
            geometry = ImageGeometry(
                left = 0.2,
                top = 0.0,
                right = 0.8,
                bottom = 0.5,
                quarterTurns = 1,
                straightenDegrees = 0.0,
            ),
            schemaVersion = 2,
        )

        val result = AndroidPhotoExporter(context.contentResolver).export(
            source.absolutePath,
            pipeline,
        )
        val outputUri = Uri.parse(result.assetId)
        try {
            assertEquals(3, result.width)
            assertEquals(6, result.height)
            val output = readBitmap(outputUri)
            assertEquals(3, output.width)
            assertEquals(6, output.height)
            assertTrue(output.colorSpace?.isSrgb == true)
            val sourceBitmap = requireNotNull(BitmapFactory.decodeFile(source.absolutePath))
            assertTrue(
                averageLuminance(output, 0, 0, output.width, output.height) >
                    averageLuminance(sourceBitmap, 2, 0, 8, 3),
            )
            sourceBitmap.recycle()
            output.recycle()
        } finally {
            context.contentResolver.delete(outputUri, null, null)
            source.delete()
            assertNoGeometryTemporaryFiles()
        }
    }

    @Test
    fun V2QuarterTurnMapsAsymmetricPixelsClockwise() {
        val source = Bitmap.createBitmap(4, 6, Bitmap.Config.ARGB_8888).apply {
            eraseColor(Color.WHITE)
            setPixel(0, 0, Color.RED)
            setPixel(3, 0, Color.GREEN)
            setPixel(0, 5, Color.BLUE)
            setPixel(3, 5, Color.YELLOW)
        }
        val output = AndroidBitmapGeometry.apply(
            source,
            ImageGeometry(
                left = 0.0,
                top = 0.0,
                right = 1.0,
                bottom = 1.0,
                quarterTurns = 1,
                straightenDegrees = 0.0,
            ),
            context.cacheDir,
        )
        try {
            assertEquals(6, output.width)
            assertEquals(4, output.height)
            assertColorsNear(Color.BLUE, output.getPixel(0, 0))
            assertColorsNear(Color.RED, output.getPixel(5, 0))
            assertColorsNear(Color.YELLOW, output.getPixel(0, 3))
            assertColorsNear(Color.GREEN, output.getPixel(5, 3))
        } finally {
            output.recycle()
            if (!source.isRecycled) source.recycle()
            assertNoGeometryTemporaryFiles()
        }
    }

    @Test
    fun geometrySetupFailureDoesNotLeaveRawTemporaryPixels() {
        val invalidDirectory = File(context.cacheDir, "geometry-not-a-directory").apply {
            writeText("not a directory")
        }
        val source = Bitmap.createBitmap(4, 4, Bitmap.Config.ARGB_8888)
        try {
            val failure = runCatching {
                AndroidBitmapGeometry.apply(
                    source,
                    ImageGeometry(0.0, 0.0, 1.0, 1.0, 1, 0.0),
                    invalidDirectory,
                )
            }

            assertTrue(failure.isFailure)
            assertNoGeometryTemporaryFiles()
        } finally {
            if (!source.isRecycled) source.recycle()
            invalidDirectory.delete()
        }
    }

    @Test
    fun unlinkFailureClearsPixelsAndCannotBeTreatedAsSuccess() {
        val directory = File(context.cacheDir, "geometry-unlink-test").apply { mkdirs() }
        val raw = File(directory, "pixels.rgba").apply { writeBytes(ByteArray(32) { 7 }) }
        Os.chmod(directory.absolutePath, 0b101_000_000)
        try {
            assertFalse(AndroidBitmapGeometry.unlinkTemporary(raw))
            assertEquals(0L, raw.length())
        } finally {
            Os.chmod(directory.absolutePath, 0b111_000_000)
            raw.delete()
            directory.delete()
        }
    }

    @Test
    fun displayP3JpegIsConvertedToSrgbByTheExportPath() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val source = File(context.cacheDir, "display-p3-source.jpg")
        Bitmap.createBitmap(
            4,
            4,
            Bitmap.Config.ARGB_8888,
            false,
            ColorSpace.get(ColorSpace.Named.DISPLAY_P3),
        ).also { bitmap ->
            bitmap.eraseColor(Color.rgb(180, 80, 60))
            source.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 100, it) }
            bitmap.recycle()
        }
        val decodedSource = BitmapFactory.decodeFile(source.absolutePath)
        assertTrue(decodedSource.colorSpace?.isWideGamut == true)
        decodedSource.recycle()
        val result = AndroidPhotoExporter(context.contentResolver).export(
            source.absolutePath,
            ImagePipelineV1(0.0, 0.0, 0.0),
        )
        val outputUri = Uri.parse(result.assetId)
        try {
            val output = readBitmap(outputUri)
            assertTrue(output.colorSpace?.isSrgb == true)
            output.recycle()
        } finally {
            context.contentResolver.delete(outputUri, null, null)
            source.delete()
        }
    }

    @Test
    fun localAnalyzerDecodesARealFileIntoStableBoundedCategories() {
        val source = File(context.cacheDir, "analysis-dark-cool.jpg")
        Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888).also { bitmap ->
            bitmap.eraseColor(Color.rgb(10, 20, 80))
            source.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 100, it) }
            bitmap.recycle()
        }
        try {
            val result = AndroidPhotoAnalyzer.analyze(source.absolutePath)

            assertEquals(AndroidPhotoAnalyzer.ANALYSIS_VERSION, result["analysisVersion"])
            assertEquals(AndroidPhotoAnalyzer.CAPABILITY_VERSION, result["capabilityVersion"])
            assertEquals("underexposed", result["exposure"])
            assertEquals("coolCast", result["whiteBalance"])
            assertEquals("blurred", result["clarity"])
            assertEquals("unavailable", result["portrait"])
            assertEquals("capabilityUnavailable", result["portraitReason"])
        } finally {
            source.delete()
        }
    }

    private fun createJpeg(file: File, width: Int, height: Int) {
        Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { bitmap ->
            for (y in 0 until height) {
                for (x in 0 until width) {
                    bitmap.setPixel(
                        x,
                        y,
                        Color.rgb(x * 255 / width, y * 255 / height, 96),
                    )
                }
            }
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 100, it) }
            bitmap.recycle()
        }
    }

    private fun readBitmap(uri: Uri): Bitmap =
        context.contentResolver.openInputStream(uri)!!.use { stream ->
            requireNotNull(BitmapFactory.decodeStream(stream))
        }

    private fun Bitmap.usePixel(): Int = try {
        getPixel(0, 0)
    } finally {
        recycle()
    }

    private fun averageLuminance(
        bitmap: Bitmap,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int,
    ): Double {
        var total = 0.0
        var count = 0
        for (y in top until bottom) {
            for (x in left until right) {
                val pixel = bitmap.getPixel(x, y)
                total +=
                    Color.red(pixel) * 0.2126 +
                        Color.green(pixel) * 0.7152 +
                        Color.blue(pixel) * 0.0722
                count += 1
            }
        }
        return total / count
    }

    private fun assertNoGeometryTemporaryFiles() {
        assertTrue(
            context.cacheDir.listFiles().orEmpty().none {
                it.name.startsWith("yingjian-geometry-")
            },
        )
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }

    private fun assertColorsNear(expected: Int, actual: Int) {
        assertTrue(kotlin.math.abs(Color.red(expected) - Color.red(actual)) <= 8)
        assertTrue(kotlin.math.abs(Color.green(expected) - Color.green(actual)) <= 8)
        assertTrue(kotlin.math.abs(Color.blue(expected) - Color.blue(actual)) <= 8)
    }
}
