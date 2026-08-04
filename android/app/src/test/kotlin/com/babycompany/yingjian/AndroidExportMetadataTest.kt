package com.babycompany.yingjian

import androidx.exifinterface.media.ExifInterface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class AndroidExportMetadataTest {
    @Test
    fun `output metadata keeps capture time and normalizes orientation only`() {
        val metadata = AndroidExportMetadata.fromAttributes(
            mapOf(
                ExifInterface.TAG_DATETIME_ORIGINAL to "2026:08:04 13:14:15",
                ExifInterface.TAG_DATETIME_DIGITIZED to "2026:08:04 13:14:16",
                ExifInterface.TAG_DATETIME to "2026:08:04 13:14:17",
                ExifInterface.TAG_GPS_LATITUDE to "31/1,12/1,0/1",
                ExifInterface.TAG_MAKE to "Private camera make",
            ),
        )

        val output = metadata.outputAttributes()

        assertEquals("1", output[ExifInterface.TAG_ORIENTATION])
        assertEquals(
            "2026:08:04 13:14:15",
            output[ExifInterface.TAG_DATETIME_ORIGINAL],
        )
        assertEquals(
            "2026:08:04 13:14:16",
            output[ExifInterface.TAG_DATETIME_DIGITIZED],
        )
        assertEquals("2026:08:04 13:14:17", output[ExifInterface.TAG_DATETIME])
        assertFalse(output.containsKey(ExifInterface.TAG_GPS_LATITUDE))
        assertFalse(output.containsKey(ExifInterface.TAG_MAKE))
    }
}
