package com.babycompany.yingjian

import androidx.exifinterface.media.ExifInterface
import java.text.ParseException
import java.text.SimpleDateFormat
import java.util.Locale

data class AndroidExportMetadata private constructor(
    private val captureAttributes: Map<String, String>,
) {
    fun outputAttributes(): Map<String, String> = buildMap {
        put(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL.toString())
        putAll(captureAttributes)
    }

    fun dateTakenMillis(): Long? {
        val value = captureAttributes[ExifInterface.TAG_DATETIME_ORIGINAL]
            ?: captureAttributes[ExifInterface.TAG_DATETIME_DIGITIZED]
            ?: captureAttributes[ExifInterface.TAG_DATETIME]
            ?: return null
        return try {
            SimpleDateFormat(EXIF_DATE_FORMAT, Locale.US).parse(value)?.time
        } catch (_: ParseException) {
            null
        }
    }

    fun writeTo(destination: ExifInterface) {
        outputAttributes().forEach(destination::setAttribute)
        destination.saveAttributes()
    }

    companion object {
        private const val EXIF_DATE_FORMAT = "yyyy:MM:dd HH:mm:ss"
        private val captureKeys = listOf(
            ExifInterface.TAG_DATETIME_ORIGINAL,
            ExifInterface.TAG_DATETIME_DIGITIZED,
            ExifInterface.TAG_DATETIME,
        )

        fun fromSource(path: String): AndroidExportMetadata {
            return try {
                val source = ExifInterface(path)
                fromAttributes(captureKeys.associateWith(source::getAttribute))
            } catch (_: Exception) {
                fromAttributes(emptyMap())
            }
        }

        fun readOrientation(path: String): Int = try {
            ExifInterface(path).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        } catch (_: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }

        fun fromAttributes(attributes: Map<String, String?>): AndroidExportMetadata {
            return AndroidExportMetadata(
                captureAttributes = captureKeys.mapNotNull { key ->
                    attributes[key]?.let { key to it }
                }.toMap(),
            )
        }
    }
}
