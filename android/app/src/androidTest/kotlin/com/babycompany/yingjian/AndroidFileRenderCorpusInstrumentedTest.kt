package com.babycompany.yingjian

import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import androidx.exifinterface.media.ExifInterface
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.MessageDigest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidFileRenderCorpusInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun fixedCorpusTraversesTheProductionFileExporter() {
        assumeTrue(
            "formal corpus input is only mounted by run_android_file_render_corpus.rb",
            InstrumentationRegistry.getArguments().getString("fileRenderCorpus") == "true",
        )
        val inputRoot = File(context.cacheDir, INPUT_DIRECTORY)
        val indexFile = File(context.cacheDir, INDEX_FILE)
        assertTrue("corpus input directory is missing", inputRoot.isDirectory)
        assertTrue("corpus index is missing", indexFile.isFile)

        val outputRoot = File(context.filesDir, OUTPUT_DIRECTORY)
        check(!outputRoot.exists() || outputRoot.deleteRecursively()) {
            "Previous corpus output could not be removed"
        }
        check(outputRoot.mkdirs()) { "Corpus output directory could not be created" }

        val index = JSONObject(indexFile.readText()).getJSONArray("assets")
        val results = JSONArray()
        for (position in 0 until index.length()) {
            val asset = index.getJSONObject(position)
            val assetId = asset.getString("id")
            require(assetId.matches(Regex("[a-z0-9-]+"))) { "Unsafe corpus asset id" }
            val source = File(inputRoot, asset.getString("file"))
            require(source.isFile && source.canonicalPath.startsWith(inputRoot.canonicalPath + File.separator)) {
                "$assetId source is unavailable"
            }
            results.put(renderAsset(assetId, source, outputRoot))
        }

        File(context.filesDir, REPORT_FILE).writeText(
            JSONObject()
                .put("schema", 1)
                .put("engineering_only", true)
                .put("sdk", Build.VERSION.SDK_INT)
                .put("device", Build.MODEL)
                .put("pipeline_schema", 2)
                .put("assets", results)
                .toString(2) + "\n",
        )
    }

    private fun renderAsset(assetId: String, source: File, outputRoot: File): JSONObject {
        val sourceHashBefore = sha256(source)
        val result = AndroidPhotoExporter(
            context.contentResolver,
            temporaryDirectory = context.cacheDir,
        ).export(source.absolutePath, neutralPipeline())
        val outputUri = Uri.parse(result.assetId)
        val output = File(outputRoot, "$assetId.jpg")
        try {
            context.contentResolver.openInputStream(outputUri).use { input ->
                requireNotNull(input) { "$assetId output could not be opened" }
                output.outputStream().use(input::copyTo)
            }
            val bitmap = requireNotNull(BitmapFactory.decodeFile(output.absolutePath)) {
                "$assetId output could not be decoded"
            }
            val isSrgb = bitmap.colorSpace?.isSrgb == true
            val width = bitmap.width
            val height = bitmap.height
            bitmap.recycle()
            val exif = ExifInterface(output.absolutePath)
            return JSONObject()
                .put("id", assetId)
                .put("source_sha256_before", sourceHashBefore)
                .put("source_sha256_after", sha256(source))
                .put("output_sha256", sha256(output))
                .put("width", width)
                .put("height", height)
                .put("format", if (isJpeg(output)) "jpeg" else "unknown")
                .put("is_srgb", isSrgb)
                .put(
                    "orientation",
                    exif.getAttributeInt(
                        ExifInterface.TAG_ORIENTATION,
                        ExifInterface.ORIENTATION_NORMAL,
                    ),
                )
                .put("has_gps", hasGps(exif))
                .put("has_device_identity", hasDeviceIdentity(exif))
        } finally {
            context.contentResolver.delete(outputUri, null, null)
        }
    }

    private fun neutralPipeline() = AndroidImagePipeline(
        exposureEv = 0.0,
        contrast = 0.0,
        warmth = 0.0,
        highlights = 0.0,
        shadows = 0.0,
        tint = 0.0,
        saturation = 0.0,
        clarity = 0.0,
        geometry = ImageGeometry(
            left = 0.0,
            top = 0.0,
            right = 1.0,
            bottom = 1.0,
            quarterTurns = 0,
            straightenDegrees = 0.0,
        ),
        schemaVersion = 2,
    )

    private fun hasGps(exif: ExifInterface): Boolean =
        exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE) != null ||
            exif.getAttribute(ExifInterface.TAG_GPS_LONGITUDE) != null ||
            exif.getAttribute(ExifInterface.TAG_GPS_ALTITUDE) != null

    private fun hasDeviceIdentity(exif: ExifInterface): Boolean = listOf(
        ExifInterface.TAG_MAKE,
        ExifInterface.TAG_MODEL,
        ExifInterface.TAG_SOFTWARE,
        ExifInterface.TAG_LENS_MAKE,
        ExifInterface.TAG_LENS_MODEL,
        ExifInterface.TAG_CAMERA_OWNER_NAME,
        ExifInterface.TAG_BODY_SERIAL_NUMBER,
    ).any { exif.getAttribute(it) != null }

    private fun isJpeg(file: File): Boolean = file.inputStream().use { input ->
        input.read() == 0xFF && input.read() == 0xD8
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

    companion object {
        private const val INPUT_DIRECTORY = "file-render-corpus-input"
        private const val OUTPUT_DIRECTORY = "file-render-corpus-output"
        private const val INDEX_FILE = "file-render-corpus-index.json"
        private const val REPORT_FILE = "file-render-corpus-report.json"
    }
}
