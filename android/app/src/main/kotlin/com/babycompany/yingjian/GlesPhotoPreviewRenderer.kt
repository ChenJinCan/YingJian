package com.babycompany.yingjian

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES30
import android.opengl.GLUtils
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.ConcurrentHashMap

class GlesPhotoPreviewRenderer(
    messenger: BinaryMessenger,
    private val textureRegistry: FlutterRenderer,
) {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val renderThread = HandlerThread("yingjian-gles-preview").apply { start() }
    private val renderHandler = Handler(renderThread.looper)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val sessions = ConcurrentHashMap<Long, PreviewSession>()
    @Volatile
    private var closed = false

    init {
        channel.setMethodCallHandler(::handleMethodCall)
    }

    fun close() {
        if (closed) return
        closed = true
        channel.setMethodCallHandler(null)
        renderHandler.post {
            val activeSessions = sessions.values.toList()
            sessions.clear()
            activeSessions.forEach(PreviewSession::close)
            mainHandler.post {
                activeSessions.forEach(PreviewSession::releaseProducer)
            }
            renderThread.quitSafely()
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getMetaOpCapabilities" -> result.success(
                mapOf(
                    "platform" to "android",
                    "operations" to listOf(
                        metaOpCapability("composition.geometry"),
                        metaOpCapability("tone.exposure"),
                        metaOpCapability("tone.highlights"),
                        metaOpCapability("tone.shadows"),
                        metaOpCapability("tone.contrast"),
                        metaOpCapability("color.warmth"),
                        metaOpCapability("color.tint"),
                        metaOpCapability("color.saturation"),
                        metaOpCapability("tone.clarity"),
                    ),
                ),
            )
            "createPreview" -> createPreview(call, result)
            "updatePreview" -> updatePreview(call, result)
            "disposePreview" -> disposePreview(call, result)
            else -> result.notImplemented()
        }
    }

    private fun metaOpCapability(id: String): Map<String, Any> = mapOf(
        "id" to id,
        "version" to 1,
        "preview" to true,
        "export" to true,
        "maxTargets" to 0,
        "maxResourceBytes" to 0,
    )

    private fun createPreview(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val maxEdge = call.argument<Int>("maxEdge")
        val pipeline = try {
            AndroidImagePipeline.parse(call.argument<Any>("pipeline"))
        } catch (error: IllegalArgumentException) {
            result.error("invalidArguments", error.message, null)
            return
        }
        if (sourcePath == null || maxEdge == null || maxEdge !in 1..2048) {
            result.error("invalidArguments", "Invalid preview request", null)
            return
        }
        val producer = textureRegistry.createSurfaceProducer(
            TextureRegistry.SurfaceLifecycle.manual,
        )
        renderHandler.post {
            if (closed) {
                mainHandler.post(producer::release)
                return@post
            }
            var session: PreviewSession? = null
            try {
                session = PreviewSession.create(
                    sourcePath = sourcePath,
                    maxEdge = maxEdge,
                    producer = producer,
                    pipeline = pipeline,
                )
                session.render(pipeline)
                if (closed) {
                    session.close()
                    mainHandler.post(producer::release)
                    return@post
                }
                sessions[producer.id()] = session
                mainHandler.post {
                    if (closed) return@post
                    result.success(
                        mapOf(
                            "textureId" to producer.id(),
                            "width" to session.width,
                            "height" to session.height,
                            "backend" to "android-gles3",
                        ),
                    )
                }
            } catch (_: Throwable) {
                session?.close()
                mainHandler.post {
                    producer.release()
                    if (!closed) {
                        result.error(
                            "previewUnavailable",
                            "Native preview could not be created",
                            null,
                        )
                    }
                }
            }
        }
    }

    private fun updatePreview(call: MethodCall, result: MethodChannel.Result) {
        val textureId = call.argument<Number>("textureId")?.toLong()
        val pipeline = try {
            AndroidImagePipeline.parse(call.argument<Any>("pipeline"))
        } catch (error: IllegalArgumentException) {
            result.error("invalidArguments", error.message, null)
            return
        }
        val session = textureId?.let(sessions::get)
        if (session == null) {
            result.error("previewNotFound", "Native preview no longer exists", null)
            return
        }
        renderHandler.post {
            if (closed) return@post
            try {
                session.render(pipeline)
                mainHandler.post {
                    if (!closed) result.success(null)
                }
            } catch (_: Throwable) {
                mainHandler.post {
                    if (!closed) {
                        result.error(
                            "previewRenderFailed",
                            "Native preview could not be updated",
                            null,
                        )
                    }
                }
            }
        }
    }

    private fun disposePreview(call: MethodCall, result: MethodChannel.Result) {
        val textureId = call.argument<Number>("textureId")?.toLong()
        if (textureId == null) {
            result.error("invalidArguments", "Missing preview texture", null)
            return
        }
        val session = sessions.remove(textureId)
        if (session == null) {
            result.success(null)
            return
        }
        renderHandler.post {
            session.close()
            mainHandler.post {
                session.releaseProducer()
                if (!closed) result.success(null)
            }
        }
    }

    private class PreviewSession private constructor(
        val width: Int,
        val height: Int,
        private val producer: TextureRegistry.SurfaceProducer,
        private val display: EGLDisplay,
        private val context: EGLContext,
        private val surface: EGLSurface,
        private val program: Int,
        private val sourceTexture: Int,
        private val vertexBuffer: FloatBuffer,
        private val sourceWidth: Int,
        private val sourceHeight: Int,
    ) {
        fun render(pipeline: AndroidImagePipeline) {
            check(EGL14.eglMakeCurrent(display, surface, surface, context)) {
                "Could not activate GLES preview context"
            }
            val crop = pipeline.geometry.pixelCrop(sourceWidth, sourceHeight)
            val expectedWidth = if (pipeline.geometry.quarterTurns % 2 == 0) {
                crop.width
            } else {
                crop.height
            }
            val expectedHeight = if (pipeline.geometry.quarterTurns % 2 == 0) {
                crop.height
            } else {
                crop.width
            }
            check(expectedWidth == width && expectedHeight == height) {
                "Preview dimensions changed"
            }
            val transform = pipeline.colorTransform()
            GLES30.glViewport(0, 0, width, height)
            GLES30.glClearColor(1f, 1f, 1f, 1f)
            GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT)
            GLES30.glUseProgram(program)
            GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, sourceTexture)
            GLES30.glUniform1i(GLES30.glGetUniformLocation(program, "uTexture"), 0)
            GLES30.glUniform3f(
                GLES30.glGetUniformLocation(program, "uScale"),
                transform.redScale.toFloat(),
                transform.greenScale.toFloat(),
                transform.blueScale.toFloat(),
            )
            GLES30.glUniform3f(
                GLES30.glGetUniformLocation(program, "uBias"),
                transform.redBias.toFloat(),
                transform.greenBias.toFloat(),
                transform.blueBias.toFloat(),
            )
            GLES30.glUniform4f(
                GLES30.glGetUniformLocation(program, "uCrop"),
                crop.left.toFloat() / sourceWidth,
                crop.top.toFloat() / sourceHeight,
                crop.width.toFloat() / sourceWidth,
                crop.height.toFloat() / sourceHeight,
            )
            GLES30.glUniform1i(
                GLES30.glGetUniformLocation(program, "uQuarterTurns"),
                pipeline.geometry.quarterTurns,
            )
            GLES30.glUniform1f(
                GLES30.glGetUniformLocation(program, "uStraightenRadians"),
                Math.toRadians(-pipeline.geometry.straightenDegrees).toFloat(),
            )
            GLES30.glUniform4f(
                GLES30.glGetUniformLocation(program, "uSecondaryAdjustments"),
                pipeline.highlights.toFloat(),
                pipeline.shadows.toFloat(),
                pipeline.tint.toFloat(),
                pipeline.saturation.toFloat(),
            )
            GLES30.glUniform1f(
                GLES30.glGetUniformLocation(program, "uClarity"),
                pipeline.clarity.toFloat(),
            )
            vertexBuffer.position(0)
            GLES30.glVertexAttribPointer(0, 2, GLES30.GL_FLOAT, false, STRIDE_BYTES, vertexBuffer)
            GLES30.glEnableVertexAttribArray(0)
            vertexBuffer.position(2)
            GLES30.glVertexAttribPointer(1, 2, GLES30.GL_FLOAT, false, STRIDE_BYTES, vertexBuffer)
            GLES30.glEnableVertexAttribArray(1)
            GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
            GLES30.glDisableVertexAttribArray(0)
            GLES30.glDisableVertexAttribArray(1)
            check(EGL14.eglSwapBuffers(display, surface)) {
                "Could not publish GLES preview frame"
            }
        }

        fun close() {
            EGL14.eglMakeCurrent(display, surface, surface, context)
            if (sourceTexture != 0) {
                GLES30.glDeleteTextures(1, intArrayOf(sourceTexture), 0)
            }
            if (program != 0) {
                GLES30.glDeleteProgram(program)
            }
            EGL14.eglMakeCurrent(
                display,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_CONTEXT,
            )
            EGL14.eglDestroySurface(display, surface)
            EGL14.eglDestroyContext(display, context)
            EGL14.eglTerminate(display)
        }

        fun releaseProducer() {
            producer.release()
        }

        companion object {
            fun create(
                sourcePath: String,
                maxEdge: Int,
                producer: TextureRegistry.SurfaceProducer,
                pipeline: AndroidImagePipeline,
            ): PreviewSession {
                val decoded = decodePreview(sourcePath, maxEdge)
                val oriented = applyExifOrientation(sourcePath, decoded)
                if (oriented !== decoded) decoded.recycle()
                val sourceWidth = oriented.width
                val sourceHeight = oriented.height
                val crop = pipeline.geometry.pixelCrop(sourceWidth, sourceHeight)
                val width = if (pipeline.geometry.quarterTurns % 2 == 0) {
                    crop.width
                } else {
                    crop.height
                }
                val height = if (pipeline.geometry.quarterTurns % 2 == 0) {
                    crop.height
                } else {
                    crop.width
                }
                var display = EGL14.EGL_NO_DISPLAY
                var context = EGL14.EGL_NO_CONTEXT
                var surface = EGL14.EGL_NO_SURFACE
                var program = 0
                var sourceTexture = 0
                try {
                    producer.setSize(width, height)
                    display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
                    require(display != EGL14.EGL_NO_DISPLAY) { "GLES display is unavailable" }
                    val versions = IntArray(2)
                    check(EGL14.eglInitialize(display, versions, 0, versions, 1)) {
                        "GLES display could not be initialized"
                    }
                    val configs = arrayOfNulls<EGLConfig>(1)
                    val configCount = IntArray(1)
                    val configAttributes = intArrayOf(
                        EGL14.EGL_RENDERABLE_TYPE,
                        EGL_OPENGL_ES3_BIT,
                        EGL14.EGL_RED_SIZE,
                        8,
                        EGL14.EGL_GREEN_SIZE,
                        8,
                        EGL14.EGL_BLUE_SIZE,
                        8,
                        EGL14.EGL_ALPHA_SIZE,
                        8,
                        EGL14.EGL_NONE,
                    )
                    check(
                        EGL14.eglChooseConfig(
                            display,
                            configAttributes,
                            0,
                            configs,
                            0,
                            configs.size,
                            configCount,
                            0,
                        ) && configCount[0] > 0,
                    ) { "GLES3 configuration is unavailable" }
                    val config = requireNotNull(configs[0])
                    context = EGL14.eglCreateContext(
                        display,
                        config,
                        EGL14.EGL_NO_CONTEXT,
                        intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 3, EGL14.EGL_NONE),
                        0,
                    )
                    require(context != EGL14.EGL_NO_CONTEXT) {
                        "GLES3 context could not be created"
                    }
                    surface = EGL14.eglCreateWindowSurface(
                        display,
                        config,
                        producer.surface,
                        intArrayOf(EGL14.EGL_NONE),
                        0,
                    )
                    require(surface != EGL14.EGL_NO_SURFACE) {
                        "Preview surface could not be created"
                    }
                    check(EGL14.eglMakeCurrent(display, surface, surface, context)) {
                        "GLES3 context could not be activated"
                    }

                    program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
                    val texture = IntArray(1)
                    GLES30.glGenTextures(1, texture, 0)
                    sourceTexture = texture[0]
                    GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, sourceTexture)
                    GLES30.glTexParameteri(
                        GLES30.GL_TEXTURE_2D,
                        GLES30.GL_TEXTURE_MIN_FILTER,
                        GLES30.GL_LINEAR,
                    )
                    GLES30.glTexParameteri(
                        GLES30.GL_TEXTURE_2D,
                        GLES30.GL_TEXTURE_MAG_FILTER,
                        GLES30.GL_LINEAR,
                    )
                    GLES30.glTexParameteri(
                        GLES30.GL_TEXTURE_2D,
                        GLES30.GL_TEXTURE_WRAP_S,
                        GLES30.GL_CLAMP_TO_EDGE,
                    )
                    GLES30.glTexParameteri(
                        GLES30.GL_TEXTURE_2D,
                        GLES30.GL_TEXTURE_WRAP_T,
                        GLES30.GL_CLAMP_TO_EDGE,
                    )
                    GLUtils.texImage2D(GLES30.GL_TEXTURE_2D, 0, oriented, 0)

                    return PreviewSession(
                        width = width,
                        height = height,
                        producer = producer,
                        display = display,
                        context = context,
                        surface = surface,
                        program = program,
                        sourceTexture = sourceTexture,
                        sourceWidth = sourceWidth,
                        sourceHeight = sourceHeight,
                        vertexBuffer = ByteBuffer
                            .allocateDirect(VERTICES.size * Float.SIZE_BYTES)
                            .order(ByteOrder.nativeOrder())
                            .asFloatBuffer()
                            .apply { put(VERTICES).position(0) },
                    )
                } catch (error: Throwable) {
                    releaseFailedCreation(
                        display = display,
                        context = context,
                        surface = surface,
                        program = program,
                        sourceTexture = sourceTexture,
                    )
                    throw error
                } finally {
                    oriented.recycle()
                }
            }

            private fun releaseFailedCreation(
                display: EGLDisplay,
                context: EGLContext,
                surface: EGLSurface,
                program: Int,
                sourceTexture: Int,
            ) {
                if (display == EGL14.EGL_NO_DISPLAY) return
                if (context != EGL14.EGL_NO_CONTEXT && surface != EGL14.EGL_NO_SURFACE) {
                    EGL14.eglMakeCurrent(display, surface, surface, context)
                    if (sourceTexture != 0) {
                        GLES30.glDeleteTextures(1, intArrayOf(sourceTexture), 0)
                    }
                    if (program != 0) {
                        GLES30.glDeleteProgram(program)
                    }
                    EGL14.eglMakeCurrent(
                        display,
                        EGL14.EGL_NO_SURFACE,
                        EGL14.EGL_NO_SURFACE,
                        EGL14.EGL_NO_CONTEXT,
                    )
                    EGL14.eglDestroySurface(display, surface)
                }
                if (context != EGL14.EGL_NO_CONTEXT) {
                    EGL14.eglDestroyContext(display, context)
                }
                EGL14.eglTerminate(display)
            }

            private fun decodePreview(sourcePath: String, maxEdge: Int): Bitmap {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(sourcePath, bounds)
                require(bounds.outWidth > 0 && bounds.outHeight > 0) {
                    "Photo dimensions could not be read"
                }
                var sampleSize = 1
                while (maxOf(bounds.outWidth, bounds.outHeight) / sampleSize > maxEdge) {
                    sampleSize *= 2
                }
                return BitmapFactory.decodeFile(
                    sourcePath,
                    BitmapFactory.Options().apply {
                        inPreferredConfig = Bitmap.Config.ARGB_8888
                        inScaled = false
                        inSampleSize = sampleSize
                    },
                ) ?: throw IllegalArgumentException("Photo could not be decoded")
            }

            private fun applyExifOrientation(path: String, bitmap: Bitmap): Bitmap {
                val orientation = ExifInterface(path).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL,
                )
                val matrix = Matrix()
                when (orientation) {
                    ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
                    ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
                    ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
                    ExifInterface.ORIENTATION_TRANSPOSE -> {
                        matrix.setRotate(90f)
                        matrix.postScale(-1f, 1f)
                    }
                    ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
                    ExifInterface.ORIENTATION_TRANSVERSE -> {
                        matrix.setRotate(-90f)
                        matrix.postScale(-1f, 1f)
                    }
                    ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
                    else -> return bitmap
                }
                return Bitmap.createBitmap(
                    bitmap,
                    0,
                    0,
                    bitmap.width,
                    bitmap.height,
                    matrix,
                    true,
                )
            }

            private fun createProgram(vertexSource: String, fragmentSource: String): Int {
                val vertexShader = compileShader(GLES30.GL_VERTEX_SHADER, vertexSource)
                val fragmentShader = compileShader(GLES30.GL_FRAGMENT_SHADER, fragmentSource)
                val program = GLES30.glCreateProgram()
                GLES30.glAttachShader(program, vertexShader)
                GLES30.glAttachShader(program, fragmentShader)
                GLES30.glLinkProgram(program)
                val linkStatus = IntArray(1)
                GLES30.glGetProgramiv(program, GLES30.GL_LINK_STATUS, linkStatus, 0)
                GLES30.glDeleteShader(vertexShader)
                GLES30.glDeleteShader(fragmentShader)
                check(linkStatus[0] == GLES30.GL_TRUE) {
                    "GLES preview program could not be linked"
                }
                return program
            }

            private fun compileShader(type: Int, source: String): Int {
                val shader = GLES30.glCreateShader(type)
                GLES30.glShaderSource(shader, source)
                GLES30.glCompileShader(shader)
                val compileStatus = IntArray(1)
                GLES30.glGetShaderiv(shader, GLES30.GL_COMPILE_STATUS, compileStatus, 0)
                check(compileStatus[0] == GLES30.GL_TRUE) {
                    "GLES preview shader could not be compiled"
                }
                return shader
            }

            private const val EGL_OPENGL_ES3_BIT = 0x0040
            private const val STRIDE_BYTES = 4 * Float.SIZE_BYTES
            private val VERTICES = floatArrayOf(
                -1f, -1f, 0f, 1f,
                1f, -1f, 1f, 1f,
                -1f, 1f, 0f, 0f,
                1f, 1f, 1f, 0f,
            )
            private const val VERTEX_SHADER = """#version 300 es
                layout(location = 0) in vec2 aPosition;
                layout(location = 1) in vec2 aTexCoord;
                out vec2 vTexCoord;
                void main() {
                    gl_Position = vec4(aPosition, 0.0, 1.0);
                    vTexCoord = aTexCoord;
                }
            """
            private const val FRAGMENT_SHADER = """#version 300 es
                precision highp float;
                uniform sampler2D uTexture;
                uniform vec3 uScale;
                uniform vec3 uBias;
                uniform vec4 uCrop;
                uniform int uQuarterTurns;
                uniform float uStraightenRadians;
                uniform vec4 uSecondaryAdjustments;
                uniform float uClarity;
                in vec2 vTexCoord;
                out vec4 outColor;

                vec2 sourceCoordinate(vec2 outputCoordinate) {
                    vec2 local = outputCoordinate;
                    if (uQuarterTurns == 1) {
                        local = vec2(outputCoordinate.y, 1.0 - outputCoordinate.x);
                    } else if (uQuarterTurns == 2) {
                        local = vec2(1.0 - outputCoordinate.x, 1.0 - outputCoordinate.y);
                    } else if (uQuarterTurns == 3) {
                        local = vec2(1.0 - outputCoordinate.y, outputCoordinate.x);
                    }
                    vec2 centered = local - vec2(0.5);
                    float cosine = cos(uStraightenRadians);
                    float sine = sin(uStraightenRadians);
                    local = mat2(cosine, sine, -sine, cosine) * centered + vec2(0.5);
                    return uCrop.xy + local * uCrop.zw;
                }

                vec3 srgbToLinear(vec3 color) {
                    bvec3 cutoff = lessThanEqual(color, vec3(0.04045));
                    vec3 lower = color / 12.92;
                    vec3 higher = pow((color + 0.055) / 1.055, vec3(2.4));
                    return mix(higher, lower, cutoff);
                }

                vec3 linearToSrgb(vec3 color) {
                    bvec3 cutoff = lessThanEqual(color, vec3(0.0031308));
                    vec3 lower = color * 12.92;
                    vec3 higher = 1.055 * pow(color, vec3(1.0 / 2.4)) - 0.055;
                    return mix(higher, lower, cutoff);
                }

                vec3 adjustedPixel(ivec2 coordinate) {
                    ivec2 size = textureSize(uTexture, 0);
                    if (any(lessThan(coordinate, ivec2(0)))
                        || any(greaterThanEqual(coordinate, size))) {
                        return vec3(1.0);
                    }
                    vec4 sampled = texelFetch(uTexture, coordinate, 0);
                    vec3 color = sampled.rgb * sampled.a + vec3(1.0) * (1.0 - sampled.a);
                    color = srgbToLinear(color);
                    color = clamp(color * uScale + uBias, 0.0, 1.0);
                    color = linearToSrgb(color);
                    float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
                    float tonalDelta = uSecondaryAdjustments.y * (1.0 - luminance) * 0.25
                        + uSecondaryAdjustments.x * luminance * 0.15;
                    color = clamp(color + vec3(tonalDelta), 0.0, 1.0);
                    luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
                    color = vec3(luminance) + (color - vec3(luminance))
                        * (1.0 + uSecondaryAdjustments.w);
                    color += vec3(0.04, -0.025, 0.04) * uSecondaryAdjustments.z;
                    return clamp(color, 0.0, 1.0);
                }

                vec3 clarifiedPixel(ivec2 coordinate) {
                    ivec2 size = textureSize(uTexture, 0);
                    if (any(lessThan(coordinate, ivec2(0)))
                        || any(greaterThanEqual(coordinate, size))) {
                        return vec3(1.0);
                    }
                    vec3 color = adjustedPixel(coordinate);
                    if (uClarity == 0.0) return color;
                    float neighbors = 0.0;
                    for (int y = -1; y <= 1; y++) {
                        for (int x = -1; x <= 1; x++) {
                            if (x == 0 && y == 0) continue;
                            ivec2 neighbor = clamp(
                                coordinate + ivec2(x, y),
                                ivec2(0),
                                size - ivec2(1)
                            );
                            neighbors += dot(
                                adjustedPixel(neighbor),
                                vec3(0.2126, 0.7152, 0.0722)
                            );
                        }
                    }
                    float center = dot(color, vec3(0.2126, 0.7152, 0.0722));
                    return clamp(
                        color + vec3(uClarity * 0.5 * (center - neighbors / 8.0)),
                        0.0,
                        1.0
                    );
                }

                vec3 sampledColor(vec2 coordinate) {
                    vec2 sourceSize = vec2(textureSize(uTexture, 0));
                    vec2 pixel = coordinate * sourceSize - vec2(0.5);
                    ivec2 origin = ivec2(floor(pixel));
                    vec2 amount = fract(pixel);
                    vec3 top = mix(
                        clarifiedPixel(origin),
                        clarifiedPixel(origin + ivec2(1, 0)),
                        amount.x
                    );
                    vec3 bottom = mix(
                        clarifiedPixel(origin + ivec2(0, 1)),
                        clarifiedPixel(origin + ivec2(1, 1)),
                        amount.x
                    );
                    return mix(top, bottom, amount.y);
                }

                void main() {
                    vec2 source = sourceCoordinate(vTexCoord);
                    outColor = vec4(sampledColor(source), 1.0);
                }
            """
        }
    }

    private companion object {
        const val CHANNEL_NAME = "yingjian/photo_preview"
    }
}
