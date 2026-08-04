package com.babycompany.yingjian

import org.junit.Assert.assertEquals
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
    fun `transform applies scale bias and clamps each opaque channel`() {
        val transform = ColorTransform(
            redScale = 2.0,
            greenScale = 0.5,
            blueScale = 1.0,
            redBias = 0.1,
            greenBias = 0.0,
            blueBias = -0.1,
        )

        val output = ArgbPixelTransformer.transform(0xFF804020.toInt(), transform)

        assertEquals(0xFFFF2006.toInt(), output)
    }
}
