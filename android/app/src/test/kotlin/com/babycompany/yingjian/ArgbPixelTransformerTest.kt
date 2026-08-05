package com.babycompany.yingjian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ArgbPixelTransformerTest {
    @Test
    fun `neutral transform composites transparent input over white`() {
        val transform = ColorTransform(
            redScale = 1.0,
            greenScale = 1.0,
            blueScale = 1.0,
            redBias = 0.0,
            greenBias = 0.0,
            blueBias = 0.0,
        )

        val output = ArgbPixelTransformer.transform(0x80FF0000.toInt(), transform)

        assertEquals(0xFFFF7F7F.toInt(), output)
    }

    @Test
    fun `transform applies scale and bias to linear light channels`() {
        val transform = ColorTransform(
            redScale = 2.0,
            greenScale = 0.5,
            blueScale = 1.0,
            redBias = 0.1,
            greenBias = 0.0,
            blueBias = -0.1,
        )

        val output = ArgbPixelTransformer.transform(0xFF804020.toInt(), transform)

        assertEquals(0xFFC12C00.toInt(), output)
    }

    @Test
    fun `positive exposure is applied in linear light without clipping encoded mid highlights`() {
        val pipeline = AndroidImagePipeline(
            exposureEv = 0.5,
            contrast = 0.0,
            warmth = 0.0,
        )

        val output = ArgbPixelTransformer.transform(0xFFCCCCCC.toInt(), pipeline.colorTransform())

        assertTrue(red(output) in 235..240)
        assertEquals(red(output), green(output))
        assertEquals(green(output), blue(output))
    }

    @Test
    fun `V2 tonal saturation and tint adjustments have declared trends`() {
        val pipeline = AndroidImagePipeline(
            exposureEv = 0.0,
            contrast = 0.0,
            warmth = 0.0,
            highlights = 0.5,
            shadows = 0.5,
            tint = 0.5,
            saturation = 0.5,
            schemaVersion = 2,
        )
        val neutral = ArgbPixelTransformer.transform(0xFF604020.toInt(), pipeline.colorTransform())
        val adjusted = ArgbPixelTransformer.transformAdjustments(
            0xFF604020.toInt(),
            pipeline.colorTransform(),
            pipeline,
        )

        assertTrue(red(adjusted) > red(neutral))
        assertTrue(green(adjusted) > green(neutral))
        assertTrue(red(adjusted) - blue(adjusted) > red(neutral) - blue(neutral))
    }

    private fun red(pixel: Int): Int = pixel ushr 16 and 0xFF

    private fun green(pixel: Int): Int = pixel ushr 8 and 0xFF

    private fun blue(pixel: Int): Int = pixel and 0xFF
}
