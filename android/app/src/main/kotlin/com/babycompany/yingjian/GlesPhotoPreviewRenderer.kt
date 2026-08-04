package com.babycompany.yingjian

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
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

    init {
        channel.setMethodCallHandler(::handleMethodCall)
    }

    fun close() {
        channel.setMethodCallHandler(null)
        val activeSessions = sessions.values.toList()
        sessions.clear()
        renderHandler.post {
            activeSessions.forEach(PreviewSession::close)
            renderThread.quitSafely()
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createPreview" -> createPreview(call, result)
            "updatePreview" -> updatePreview(call, result)
            "disposePreview" -> disposePreview(call, result)
            else -> result.notImplemented()
        }
    }

    private fun createPreview(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val maxEdge = call.argument<Int>("maxEdge")
        val pipeline = try {
            ImagePipelineV1.parse(call.argument<Any>("pipeline"))
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
            try {
                val session = PreviewSession.create(
                    sourcePath = sourcePath,
                    maxEdge = maxEdge,
                    producer = producer,
                )
                session.render(pipeline)
                sessions[producer.id()] = session
                mainHandler.post {
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
                producer.release()
                mainHandler.post {
                    result.error("previewUnavailable", "Native preview could not be created", null)
                }
            }
        }
    }

    private fun updatePreview(call: MethodCall, result: MethodChannel.Result) {
        val textureId = call.argument<Number>("textureId")?.toLong()
        val pipeline = try {
            ImagePipelineV1.parse(call.argument<Any>("pipeline"))
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
            try {
                session.render(pipeline)
                mainHandler.post { result.success(null) }
            } catch (_: Throwable) {
                mainHandler.post {
                    result.error("previewRenderFailed", "Native preview could not be updated", null)
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
            mainHandler.post { result.success(null) }
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
    ) {
        fun render(pipeline: ImagePipelineV1) {
            check(EGL14.eglMakeCurrent(display, surface, surface, context)) {
                "Could not activate GLES preview context"
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
            producer.release()
        }

        companion object {
            fun create(
                sourcePath: String,
                maxEdge: Int,
                producer: TextureRegistry.SurfaceProducer,
            ): PreviewSession {
                val decoded = decodePreview(sourcePath, maxEdge)
                val oriented = applyExifOrientation(sourcePath, decoded)
                if (oriented !== decoded) decoded.recycle()
                val width = oriented.width
                val height = oriented.height
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
                in vec2 vTexCoord;
                out vec4 outColor;
                void main() {
                    vec4 sampled = texture(uTexture, vTexCoord);
                    vec3 onWhite = sampled.rgb * sampled.a + vec3(1.0) * (1.0 - sampled.a);
                    outColor = vec4(clamp(onWhite * uScale + uBias, 0.0, 1.0), 1.0);
                }
            """
        }
    }

    private companion object {
        const val CHANNEL_NAME = "yingjian/photo_preview"
    }
}
