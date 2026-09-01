package com.babycompany.yingjian

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI
import java.nio.charset.StandardCharsets
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * Mints a short-lived first-party generation credential after this app
 * installation proves possession of its AndroidKeyStore P-256 key.
 */
internal class AndroidGenerationSessionCredentialHost(
    context: Context,
    messenger: BinaryMessenger,
) : AutoCloseable {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val service = AndroidGenerationSessionService(context.applicationContext)
    private var cachedCredential: CachedCredential? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != METHOD_GET_CREDENTIAL) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val baseUrl = call.argument<String>("baseUrl")
            if (baseUrl == null) {
                result.error("unavailable", "Generation session is unavailable", null)
                return@setMethodCallHandler
            }
            try {
                executor.execute {
                    try {
                        val now = System.currentTimeMillis()
                        val cached = cachedCredential
                        val credential = if (
                            cached != null &&
                            cached.baseUrl == baseUrl &&
                            cached.credential.expiresAtEpochMilliseconds - now >= 30_000
                        ) {
                            cached.credential
                        } else {
                            service.obtainCredential(baseUrl).also {
                                cachedCredential = CachedCredential(baseUrl, it)
                            }
                        }
                        mainHandler.post {
                            result.success(
                                mapOf(
                                    "bearerToken" to credential.bearerToken,
                                    "expiresAtEpochMilliseconds" to
                                        credential.expiresAtEpochMilliseconds,
                                ),
                            )
                        }
                    } catch (error: AndroidGenerationSessionException) {
                        mainHandler.post {
                            result.error(
                                error.flutterCode,
                                "Generation session is unavailable",
                                null,
                            )
                        }
                    } catch (_: Exception) {
                        mainHandler.post {
                            result.error(
                                "unavailable",
                                "Generation session is unavailable",
                                null,
                            )
                        }
                    }
                }
            } catch (_: RejectedExecutionException) {
                result.error("unavailable", "Generation session is unavailable", null)
            }
        }
    }

    override fun close() {
        cachedCredential = null
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    private data class CachedCredential(
        val baseUrl: String,
        val credential: AndroidGenerationCredential,
    )

    private companion object {
        const val CHANNEL_NAME = "yingjian/generation_session"
        const val METHOD_GET_CREDENTIAL = "getShortLivedBearerCredential"
    }
}

private data class AndroidGenerationCredential(
    val bearerToken: String,
    val expiresAtEpochMilliseconds: Long,
)

private data class AndroidGenerationChallenge(
    val id: String,
    val value: String,
)

private class AndroidGenerationSessionService(context: Context) {
    private val installationStore = AndroidGenerationInstallationStore(context)
    private val keyStore = AndroidGenerationInstallationKeyStore()

    fun obtainCredential(baseUrlString: String): AndroidGenerationCredential {
        val baseUri = validatedBaseUri(baseUrlString)
        val storedInstallationId = installationStore.installationId()
        if (storedInstallationId != null) {
            val existingIdentity = keyStore.existingIdentityOrNull()
            if (existingIdentity != null) {
                return refreshCredential(baseUri, storedInstallationId, existingIdentity)
            }
            // Preferences may be restored from backup while AndroidKeyStore keys are not.
            installationStore.clearInstallationId()
        }

        val identity = keyStore.existingOrCreateIdentity()
        val keyId = keyId(identity.publicKeyX963)
        val challenge = requestChallenge(
            baseUri = baseUri,
            path = "/v1/installation-challenges",
            body = JSONObject()
                .put("version", 2)
                .put("keyId", keyId),
        )
        val message =
            "yingjian-installation-v2\n${challenge.id}\n${challenge.value}\n$keyId\n"
        val response = postJson(
            baseUri = baseUri,
            path = "/v1/installations",
            body = JSONObject()
                .put("version", 2)
                .put("challengeId", challenge.id)
                .put("challenge", challenge.value)
                .put("keyId", keyId)
                .put("publicKey", base64Url(identity.publicKeyX963))
                .put("signature", base64Url(identity.sign(message))),
        )
        val envelope = parseCredentialEnvelope(response)
        installationStore.storeInstallationId(envelope.first)
        return envelope.second
    }

    private fun refreshCredential(
        baseUri: URI,
        installationId: String,
        identity: AndroidGenerationInstallationKeyStore.Identity,
    ): AndroidGenerationCredential {
        val keyId = keyId(identity.publicKeyX963)
        val challenge = requestChallenge(
            baseUri = baseUri,
            path = "/v1/generation-session-challenges",
            body = JSONObject()
                .put("version", 1)
                .put("installationId", installationId)
                .put("keyId", keyId),
        )
        val message =
            "yingjian-generation-session-v1\n${challenge.id}\n${challenge.value}\n" +
                "$installationId\n$keyId\n"
        val response = postJson(
            baseUri = baseUri,
            path = "/v1/generation-sessions",
            body = JSONObject()
                .put("version", 1)
                .put("installationId", installationId)
                .put("keyId", keyId)
                .put("challengeId", challenge.id)
                .put("challenge", challenge.value)
                .put("signature", base64Url(identity.sign(message))),
            authenticationRequest = true,
        )
        val envelope = parseCredentialEnvelope(response)
        if (envelope.first != installationId) {
            throw AndroidGenerationSessionException.unavailable()
        }
        return envelope.second
    }

    private fun requestChallenge(
        baseUri: URI,
        path: String,
        body: JSONObject,
    ): AndroidGenerationChallenge {
        val response = postJson(baseUri, path, body)
        val challengeId = response.string("challengeId")
        val challenge = response.string("challenge")
        val expiresAt = response.long("expiresAtEpochMilliseconds")
        val remaining = expiresAt - System.currentTimeMillis()
        if (
            !CHALLENGE_ID.matches(challengeId) ||
            !isCanonicalBase64Url(challenge, expectedBytes = 32) ||
            remaining < 5_000 ||
            remaining > 5 * 60 * 1_000
        ) {
            throw AndroidGenerationSessionException.unavailable()
        }
        return AndroidGenerationChallenge(challengeId, challenge)
    }

    private fun parseCredentialEnvelope(
        response: JSONObject,
    ): Pair<String, AndroidGenerationCredential> {
        val installationId = response.string("installationId")
        val bearerToken = response.string("bearerToken")
        val expiresAt = response.long("expiresAtEpochMilliseconds")
        val remaining = expiresAt - System.currentTimeMillis()
        if (
            !INSTALLATION_ID.matches(installationId) ||
            bearerToken.length !in 16..8_192 ||
            !BEARER_TOKEN.matches(bearerToken) ||
            remaining < 30_000 ||
            remaining > 15 * 60 * 1_000
        ) {
            throw AndroidGenerationSessionException.unavailable()
        }
        return installationId to AndroidGenerationCredential(bearerToken, expiresAt)
    }

    private fun postJson(
        baseUri: URI,
        path: String,
        body: JSONObject,
        authenticationRequest: Boolean = false,
    ): JSONObject {
        val url = baseUri.resolve(path).toURL()
        val connection = (url.openConnection() as? HttpURLConnection)
            ?: throw AndroidGenerationSessionException.unavailable()
        try {
            connection.requestMethod = "POST"
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 15_000
            connection.readTimeout = 20_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("Cache-Control", "no-store")
            val requestBody = body.toString().toByteArray(StandardCharsets.UTF_8)
            connection.setFixedLengthStreamingMode(requestBody.size)
            connection.outputStream.use { it.write(requestBody) }

            val status = connection.responseCode
            if (status !in 200..299) {
                if (authenticationRequest && (status == 401 || status == 403)) {
                    throw AndroidGenerationSessionException.notAuthenticated()
                }
                throw AndroidGenerationSessionException.unavailable()
            }
            val contentType = connection.contentType?.lowercase()
            if (contentType?.startsWith("application/json") != true) {
                throw AndroidGenerationSessionException.unavailable()
            }
            if (connection.contentLength > MAXIMUM_RESPONSE_BYTES) {
                throw AndroidGenerationSessionException.unavailable()
            }
            val data = connection.inputStream.use {
                readLimited(it, MAXIMUM_RESPONSE_BYTES)
            }
            return try {
                JSONObject(String(data, StandardCharsets.UTF_8))
            } catch (_: Exception) {
                throw AndroidGenerationSessionException.unavailable()
            }
        } catch (error: AndroidGenerationSessionException) {
            throw error
        } catch (_: Exception) {
            throw AndroidGenerationSessionException.unavailable()
        } finally {
            connection.disconnect()
        }
    }

    private fun validatedBaseUri(rawValue: String): URI {
        if (rawValue != rawValue.trim()) {
            throw AndroidGenerationSessionException.unavailable()
        }
        val uri = try {
            URI(rawValue)
        } catch (_: Exception) {
            throw AndroidGenerationSessionException.unavailable()
        }
        val scheme = uri.scheme?.lowercase()
        val host = uri.host?.lowercase()
        val isDebugLoopback = BuildConfig.DEBUG && scheme == "http" && isLoopback(host)
        if (
            host.isNullOrEmpty() ||
            uri.rawUserInfo != null ||
            uri.rawQuery != null ||
            uri.rawFragment != null ||
            (scheme != "https" && !isDebugLoopback)
        ) {
            throw AndroidGenerationSessionException.unavailable()
        }
        return uri
    }

    private fun isLoopback(host: String?): Boolean =
        host == "localhost" || host == "127.0.0.1" || host == "::1"

    private fun JSONObject.string(name: String): String =
        opt(name) as? String ?: throw AndroidGenerationSessionException.unavailable()

    private fun JSONObject.long(name: String): Long =
        (opt(name) as? Number)?.toLong()
            ?: throw AndroidGenerationSessionException.unavailable()

    private fun keyId(publicKey: ByteArray): String =
        MessageDigest.getInstance("SHA-256")
            .digest(publicKey)
            .joinToString(separator = "") { "%02x".format(it) }

    private fun base64Url(bytes: ByteArray): String =
        Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)

    private fun isCanonicalBase64Url(value: String, expectedBytes: Int): Boolean {
        if (!BASE64_URL.matches(value)) return false
        return try {
            val decoded = Base64.decode(value, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
            decoded.size == expectedBytes && base64Url(decoded) == value
        } catch (_: IllegalArgumentException) {
            false
        }
    }

    private fun readLimited(input: InputStream, maximumBytes: Int): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(4_096)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            if (output.size() + count > maximumBytes) {
                throw AndroidGenerationSessionException.unavailable()
            }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    private companion object {
        const val MAXIMUM_RESPONSE_BYTES = 64 * 1_024
        val CHALLENGE_ID = Regex("^[A-Za-z0-9_-]{8,128}$")
        val INSTALLATION_ID = Regex("^[A-Za-z0-9_-]{16,128}$")
        val BEARER_TOKEN = Regex("^[A-Za-z0-9._~+/-]+=*$")
        val BASE64_URL = Regex("^[A-Za-z0-9_-]+$")
    }
}

private class AndroidGenerationInstallationStore(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun installationId(): String? {
        val value = preferences.getString(INSTALLATION_ID_KEY, null) ?: return null
        if (!INSTALLATION_ID.matches(value)) {
            clearInstallationId()
            return null
        }
        return value
    }

    fun storeInstallationId(value: String) {
        if (!INSTALLATION_ID.matches(value) ||
            !preferences.edit().putString(INSTALLATION_ID_KEY, value).commit()
        ) {
            throw AndroidGenerationSessionException.unavailable()
        }
    }

    fun clearInstallationId() {
        if (!preferences.edit().remove(INSTALLATION_ID_KEY).commit()) {
            throw AndroidGenerationSessionException.unavailable()
        }
    }

    private companion object {
        const val PREFERENCES_NAME = "yingjian_generation_session"
        const val INSTALLATION_ID_KEY = "installation_id_v1"
        val INSTALLATION_ID = Regex("^[A-Za-z0-9_-]{16,128}$")
    }
}

private class AndroidGenerationInstallationKeyStore {
    data class Identity(
        private val privateKey: java.security.PrivateKey,
        val publicKeyX963: ByteArray,
    ) {
        fun sign(message: String): ByteArray {
            val signer = Signature.getInstance("SHA256withECDSA")
            signer.initSign(privateKey)
            signer.update(message.toByteArray(StandardCharsets.UTF_8))
            return derEcdsaSignatureToP1363(signer.sign())
        }
    }

    fun existingIdentityOrNull(): Identity? {
        return try {
            readIdentity()
        } catch (_: Exception) {
            deleteInvalidKey()
            null
        }
    }

    fun existingOrCreateIdentity(): Identity {
        existingIdentityOrNull()?.let { return it }
        return try {
            val generator = KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_EC,
                ANDROID_KEY_STORE,
            )
            generator.initialize(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_SIGN,
                )
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .setUserAuthenticationRequired(false)
                    .build(),
            )
            val keyPair = generator.generateKeyPair()
            identity(keyPair.private, keyPair.public as? ECPublicKey)
        } catch (error: AndroidGenerationSessionException) {
            throw error
        } catch (_: Exception) {
            throw AndroidGenerationSessionException.unavailable()
        }
    }

    private fun readIdentity(): Identity? {
        val store = keyStore()
        val entry = store.getEntry(KEY_ALIAS, null) ?: return null
        if (entry !is KeyStore.PrivateKeyEntry) {
            throw AndroidGenerationSessionException.unavailable()
        }
        return identity(entry.privateKey, entry.certificate.publicKey as? ECPublicKey)
    }

    private fun identity(
        privateKey: java.security.PrivateKey,
        publicKey: ECPublicKey?,
    ): Identity {
        if (publicKey == null || publicKey.params.curve.field.fieldSize != 256) {
            throw AndroidGenerationSessionException.unavailable()
        }
        val x = fixedUnsigned(publicKey.w.affineX.toByteArray(), 32)
        val y = fixedUnsigned(publicKey.w.affineY.toByteArray(), 32)
        return Identity(privateKey, byteArrayOf(0x04) + x + y)
    }

    private fun fixedUnsigned(value: ByteArray, size: Int): ByteArray {
        val firstNonZero = value.indexOfFirst { it.toInt() != 0 }.let {
            if (it < 0) value.lastIndex else it
        }
        val unsigned = value.copyOfRange(firstNonZero, value.size)
        if (unsigned.size > size) {
            throw AndroidGenerationSessionException.unavailable()
        }
        return ByteArray(size - unsigned.size) + unsigned
    }

    private fun deleteInvalidKey() {
        try {
            val store = keyStore()
            if (store.containsAlias(KEY_ALIAS)) store.deleteEntry(KEY_ALIAS)
        } catch (_: Exception) {
            throw AndroidGenerationSessionException.unavailable()
        }
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }

    private companion object {
        const val ANDROID_KEY_STORE = "AndroidKeyStore"
        const val KEY_ALIAS = "yingjian-generation-session-signing-key-v1"
    }
}

internal fun derEcdsaSignatureToP1363(der: ByteArray): ByteArray {
    var offset = 0
    fun readByte(): Int {
        if (offset >= der.size) throw AndroidGenerationSessionException.unavailable()
        return der[offset++].toInt() and 0xff
    }

    fun readLength(): Int {
        val first = readByte()
        if (first < 0x80) return first
        val byteCount = first and 0x7f
        if (byteCount !in 1..2) throw AndroidGenerationSessionException.unavailable()
        var length = 0
        repeat(byteCount) { length = (length shl 8) or readByte() }
        return length
    }

    if (readByte() != 0x30) throw AndroidGenerationSessionException.unavailable()
    val sequenceLength = readLength()
    if (sequenceLength != der.size - offset) throw AndroidGenerationSessionException.unavailable()

    fun readInteger(): ByteArray {
        if (readByte() != 0x02) throw AndroidGenerationSessionException.unavailable()
        val length = readLength()
        if (length <= 0 || offset + length > der.size) {
            throw AndroidGenerationSessionException.unavailable()
        }
        val value = der.copyOfRange(offset, offset + length)
        offset += length
        if ((value[0].toInt() and 0x80) != 0) {
            throw AndroidGenerationSessionException.unavailable()
        }
        val firstNonZero = value.indexOfFirst { it.toInt() != 0 }.let {
            if (it < 0) value.lastIndex else it
        }
        val unsigned = value.copyOfRange(firstNonZero, value.size)
        if (unsigned.size > 32) throw AndroidGenerationSessionException.unavailable()
        return ByteArray(32 - unsigned.size) + unsigned
    }

    val r = readInteger()
    val s = readInteger()
    if (offset != der.size) throw AndroidGenerationSessionException.unavailable()
    return r + s
}

private class AndroidGenerationSessionException private constructor(
    val flutterCode: String,
) : Exception() {
    companion object {
        fun unavailable() = AndroidGenerationSessionException("unavailable")
        fun notAuthenticated() = AndroidGenerationSessionException("not_authenticated")
    }
}
