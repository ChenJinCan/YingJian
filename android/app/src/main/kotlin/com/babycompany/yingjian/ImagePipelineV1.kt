package com.babycompany.yingjian

import kotlin.math.floor
import kotlin.math.pow

data class AndroidImagePipeline(
    val exposureEv: Double,
    val contrast: Double,
    val warmth: Double,
    val highlights: Double = 0.0,
    val shadows: Double = 0.0,
    val tint: Double = 0.0,
    val saturation: Double = 0.0,
    val clarity: Double = 0.0,
    val geometry: ImageGeometry = ImageGeometry.original,
    val schemaVersion: Int = 1,
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
        fun parse(arguments: Any?): AndroidImagePipeline {
            val pipeline = arguments as? Map<*, *>
                ?: throw IllegalArgumentException("Missing image pipeline")
            val schemaVersion = exactInteger(
                pipeline["schemaVersion"],
                "Missing image pipeline version",
            )
            require(schemaVersion == 1 || schemaVersion == 2) {
                "Unsupported image pipeline version"
            }
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
            if (schemaVersion == 1) {
                return AndroidImagePipeline(
                    exposureEv = exposureEv,
                    contrast = contrast,
                    warmth = warmth,
                )
            }

            val highlights = adjustments.normalized("highlights")
            val shadows = adjustments.normalized("shadows")
            val tint = adjustments.normalized("tint")
            val saturation = adjustments.normalized("saturation")
            val clarity = adjustments.normalized("clarity")
            val geometryArguments = pipeline["geometry"] as? Map<*, *>
                ?: throw IllegalArgumentException("Missing image geometry")
            val crop = geometryArguments["normalizedCrop"] as? List<*>
                ?: throw IllegalArgumentException("Missing normalized crop")
            require(crop.size == 4) { "Normalized crop must contain four values" }
            val values = crop.mapIndexed { index, value ->
                val number = (value as? Number)?.toDouble()
                    ?: throw IllegalArgumentException("Invalid normalized crop at $index")
                require(number.isFinite() && number in 0.0..1.0) {
                    "Normalized crop is outside the supported range"
                }
                number
            }
            require(values[2] > values[0] && values[3] > values[1]) {
                "Normalized crop is empty"
            }
            val quarterTurns = exactInteger(
                geometryArguments["quarterTurns"],
                "Missing quarter turns",
            )
            require(quarterTurns in 0..3) { "Quarter turns are outside the supported range" }
            val straightenDegrees =
                (geometryArguments["straightenDegrees"] as? Number)?.toDouble()
                    ?: throw IllegalArgumentException("Missing straighten angle")
            require(straightenDegrees.isFinite() && straightenDegrees in -45.0..45.0) {
                "Straighten angle is outside the supported range"
            }
            val portrait = pipeline["portrait"] as? Map<*, *>
                ?: throw IllegalArgumentException("Missing portrait recipe")
            require(
                exactInteger(
                    portrait["recipeVersion"],
                    "Missing portrait recipe version",
                ) == 1,
            ) {
                "Unsupported portrait recipe version"
            }
            val portraitStrength = (portrait["strength"] as? Number)?.toDouble()
                ?: throw IllegalArgumentException("Missing portrait strength")
            require(portraitStrength.isFinite() && portraitStrength == 0.0) {
                "Portrait processing is not production eligible"
            }
            return AndroidImagePipeline(
                exposureEv = exposureEv,
                contrast = contrast,
                warmth = warmth,
                highlights = highlights,
                shadows = shadows,
                tint = tint,
                saturation = saturation,
                clarity = clarity,
                geometry = ImageGeometry(
                    left = values[0],
                    top = values[1],
                    right = values[2],
                    bottom = values[3],
                    quarterTurns = quarterTurns,
                    straightenDegrees = straightenDegrees,
                ),
                schemaVersion = schemaVersion,
            )
        }

        private fun Map<*, *>.number(name: String): Double =
            (this[name] as? Number)?.toDouble()
                ?: throw IllegalArgumentException("Missing image adjustment: $name")

        private fun Map<*, *>.normalized(name: String): Double {
            val value = number(name)
            require(value.isFinite() && value in -1.0..1.0) {
                "$name is outside the supported range"
            }
            return value
        }

        private fun exactInteger(value: Any?, missingMessage: String): Int {
            val number = (value as? Number)?.toDouble()
                ?: throw IllegalArgumentException(missingMessage)
            require(
                number.isFinite() &&
                    number >= Int.MIN_VALUE.toDouble() &&
                    number <= Int.MAX_VALUE.toDouble() &&
                    number == floor(number),
            ) { "Image pipeline integer field is invalid" }
            return number.toInt()
        }
    }
}

typealias ImagePipelineV1 = AndroidImagePipeline

data class ImageGeometry(
    val left: Double,
    val top: Double,
    val right: Double,
    val bottom: Double,
    val quarterTurns: Int,
    val straightenDegrees: Double,
) {
    val isIdentity: Boolean
        get() = this == original

    fun pixelCrop(sourceWidth: Int, sourceHeight: Int): PixelCrop {
        require(sourceWidth > 0 && sourceHeight > 0)
        val width = aligned((right - left) * sourceWidth).coerceIn(1, sourceWidth)
        val height = aligned((bottom - top) * sourceHeight).coerceIn(1, sourceHeight)
        val leftPixel = aligned(left * sourceWidth).coerceIn(0, sourceWidth - width)
        val topPixel = aligned(top * sourceHeight).coerceIn(0, sourceHeight - height)
        val rightPixel = leftPixel + width
        val bottomPixel = topPixel + height
        return PixelCrop(leftPixel, topPixel, rightPixel, bottomPixel)
    }

    private fun aligned(value: Double): Int = floor(value + 0.5).toInt()

    companion object {
        val original = ImageGeometry(
            left = 0.0,
            top = 0.0,
            right = 1.0,
            bottom = 1.0,
            quarterTurns = 0,
            straightenDegrees = 0.0,
        )
    }
}

data class PixelCrop(
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
) {
    val width: Int get() = right - left
    val height: Int get() = bottom - top
}

data class ColorTransform(
    val redScale: Double,
    val greenScale: Double,
    val blueScale: Double,
    val redBias: Double,
    val greenBias: Double,
    val blueBias: Double,
)
