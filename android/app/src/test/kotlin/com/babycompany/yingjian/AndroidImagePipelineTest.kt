package com.babycompany.yingjian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class AndroidImagePipelineTest {
    @Test
    fun `V1 remains frozen with identity extended semantics`() {
        val pipeline = AndroidImagePipeline.parse(
            mapOf(
                "schemaVersion" to 1,
                "workingColorSpace" to "srgb",
                "adjustments" to mapOf(
                    "exposureEv" to 0.5,
                    "contrast" to 0.2,
                    "warmth" to -0.3,
                ),
            ),
        )

        assertEquals(1, pipeline.schemaVersion)
        assertEquals(ImageGeometry.original, pipeline.geometry)
        assertEquals(0.0, pipeline.highlights, 0.0)
        assertEquals(0.0, pipeline.clarity, 0.0)
    }

    @Test
    fun `V2 parses every declared adjustment and geometry field`() {
        val pipeline = AndroidImagePipeline.parse(v2())

        assertEquals(2, pipeline.schemaVersion)
        assertEquals(0.25, pipeline.highlights, 0.0)
        assertEquals(-0.4, pipeline.shadows, 0.0)
        assertEquals(0.3, pipeline.tint, 0.0)
        assertEquals(0.5, pipeline.saturation, 0.0)
        assertEquals(0.2, pipeline.clarity, 0.0)
        assertEquals(ImageGeometry(0.2, 0.1, 0.8, 0.6, 1, -2.5), pipeline.geometry)
    }

    @Test
    fun `V2 crop keeps pixel aligned dimensions when translated`() {
        val crop = ImageGeometry(0.21, 0.1, 0.79, 0.51, 1, 0.0)
            .pixelCrop(sourceWidth = 10, sourceHeight = 6)
        val edgeCrop = ImageGeometry(0.5, 0.0, 1.0, 1.0, 0, 0.0)
            .pixelCrop(sourceWidth = 3, sourceHeight = 2)

        assertEquals(PixelCrop(left = 2, top = 1, right = 8, bottom = 3), crop)
        assertEquals(PixelCrop(left = 1, top = 0, right = 3, bottom = 2), edgeCrop)
    }

    @Test
    fun `V2 rejects unknown unsafe or incomplete contracts`() {
        assertThrows(IllegalArgumentException::class.java) {
            AndroidImagePipeline.parse(v2(schemaVersion = 3))
        }
        assertThrows(IllegalArgumentException::class.java) {
            AndroidImagePipeline.parse(v2(portraitStrength = 0.1))
        }
        assertThrows(IllegalArgumentException::class.java) {
            AndroidImagePipeline.parse(v2(crop = listOf(0.8, 0.0, 0.2, 1.0)))
        }
        assertThrows(IllegalArgumentException::class.java) {
            AndroidImagePipeline.parse(v2(straightenDegrees = 46.0))
        }
        assertThrows(IllegalArgumentException::class.java) {
            val missing = v2().toMutableMap()
            missing.remove("portrait")
            AndroidImagePipeline.parse(missing)
        }
        assertThrows(IllegalArgumentException::class.java) {
            AndroidImagePipeline.parse(v2(schemaVersion = 1.9))
        }
        assertThrows(IllegalArgumentException::class.java) {
            AndroidImagePipeline.parse(v2(quarterTurns = 1.9))
        }
        assertThrows(IllegalArgumentException::class.java) {
            AndroidImagePipeline.parse(v2(portraitRecipeVersion = 1.9))
        }
    }

    private fun v2(
        schemaVersion: Number = 2,
        crop: List<Double> = listOf(0.2, 0.1, 0.8, 0.6),
        straightenDegrees: Double = -2.5,
        portraitStrength: Double = 0.0,
        quarterTurns: Number = 1,
        portraitRecipeVersion: Number = 1,
    ): Map<String, Any> = mapOf(
        "schemaVersion" to schemaVersion,
        "workingColorSpace" to "srgb",
        "adjustments" to mapOf(
            "exposureEv" to 0.4,
            "highlights" to 0.25,
            "shadows" to -0.4,
            "contrast" to 0.1,
            "warmth" to -0.2,
            "tint" to 0.3,
            "saturation" to 0.5,
            "clarity" to 0.2,
        ),
        "geometry" to mapOf(
            "normalizedCrop" to crop,
            "quarterTurns" to quarterTurns,
            "straightenDegrees" to straightenDegrees,
        ),
        "portrait" to mapOf(
            "recipeVersion" to portraitRecipeVersion,
            "strength" to portraitStrength,
        ),
    )
}
