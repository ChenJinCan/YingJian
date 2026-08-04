package com.babycompany.yingjian

import kotlin.math.pow

data class ImagePipelineV1(
    val exposureEv: Double,
    val contrast: Double,
    val warmth: Double,
) {
    fun colorTransform(): ColorTransform {
        val exposureScale = 2.0.pow(exposureEv)
        val contrastScale = 1.0 + contrast * 0.75
        val redWarmthScale = 1.0 + warmth * 0.15
        val blueWarmthScale = 1.0 - warmth * 0.15
        val contrastBias = 0.5 * (1.0 - contrastScale)
        return ColorTransform(
            redScale = exposureScale * contrastScale * redWarmthScale,
            greenScale = exposureScale * contrastScale,
            blueScale = exposureScale * contrastScale * blueWarmthScale,
            redBias = contrastBias * redWarmthScale,
            greenBias = contrastBias,
            blueBias = contrastBias * blueWarmthScale,
        )
    }

    companion object {
        fun parse(arguments: Any?): ImagePipelineV1 {
            val pipeline = arguments as? Map<*, *>
                ?: throw IllegalArgumentException("Missing image pipeline")
            val schemaVersion = (pipeline["schemaVersion"] as? Number)?.toInt()
            require(schemaVersion == 1) { "Unsupported image pipeline version" }
            require(pipeline["workingColorSpace"] == "srgb") {
                "Unsupported working color space"
            }
            val adjustments = pipeline["adjustments"] as? Map<*, *>
                ?: throw IllegalArgumentException("Missing image adjustments")
            val exposureEv = adjustments.number("exposureEv")
            val contrast = adjustments.number("contrast")
            val warmth = adjustments.number("warmth")
            require(exposureEv.isFinite() && exposureEv in -2.0..2.0) {
                "Exposure is outside the supported range"
            }
            require(contrast.isFinite() && contrast in -1.0..1.0) {
                "Contrast is outside the supported range"
            }
            require(warmth.isFinite() && warmth in -1.0..1.0) {
                "Warmth is outside the supported range"
            }
            return ImagePipelineV1(
                exposureEv = exposureEv,
                contrast = contrast,
                warmth = warmth,
            )
        }

        private fun Map<*, *>.number(name: String): Double =
            (this[name] as? Number)?.toDouble()
                ?: throw IllegalArgumentException("Missing image adjustment: $name")
    }
}

data class ColorTransform(
    val redScale: Double,
    val greenScale: Double,
    val blueScale: Double,
    val redBias: Double,
    val greenBias: Double,
    val blueBias: Double,
)
