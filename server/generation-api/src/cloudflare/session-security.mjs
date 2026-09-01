import {
  createHash,
  createHmac,
  randomBytes,
  randomUUID,
  timingSafeEqual,
} from 'node:crypto';

const SESSION_AUDIENCE = 'yingjian-generation';
const SESSION_SCOPE = 'generation';
const SESSION_VERSION = 1;
const PUBLIC_INSTALLATION_VERSION = 2;
const SESSION_KID = 'generation-session-v1';
const CHALLENGE_TTL_MILLISECONDS = 120_000;
const SESSION_TTL_SECONDS = 600;
const MAX_SESSION_LIFETIME_SECONDS = 900;
const CLOCK_TOLERANCE_SECONDS = 30;
const SESSION_PATHS = new Set([
  '/v1/installation-challenges',
  '/v1/installations',
  '/v1/generation-session-challenges',
  '/v1/generation-sessions',
]);

class SessionHttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

function json(status, body) {
  return Response.json(body, {
    status,
    headers: { 'cache-control': 'no-store' },
  });
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function base64url(bytes) {
  return Buffer.from(bytes).toString('base64url');
}

function decodeCanonicalBase64url(value, expectedBytes, code) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new SessionHttpError(400, code);
  }
  let bytes;
  try {
    bytes = Buffer.from(value, 'base64url');
  } catch {
    throw new SessionHttpError(400, code);
  }
  if (
    bytes.length !== expectedBytes ||
    bytes.toString('base64url') !== value
  ) {
    throw new SessionHttpError(400, code);
  }
  return bytes;
}

function requireString(value, code, maximumLength = 256) {
  if (
    typeof value !== 'string' ||
    value.length === 0 ||
    value.length > maximumLength
  ) {
    throw new SessionHttpError(400, code);
  }
  return value;
}

function requireVersion(value) {
  if (value !== SESSION_VERSION) {
    throw new SessionHttpError(400, 'session_version_unsupported');
  }
}

function requireInstallationVersion(value) {
  if (value !== SESSION_VERSION && value !== PUBLIC_INSTALLATION_VERSION) {
    throw new SessionHttpError(400, 'session_version_unsupported');
  }
  return value;
}

function requireKeyId(value) {
  const keyId = requireString(value, 'key_id_invalid', 64);
  if (!/^[a-f0-9]{64}$/.test(keyId)) {
    throw new SessionHttpError(400, 'key_id_invalid');
  }
  return keyId;
}

function requireInstallationId(value) {
  const installationId = requireString(value, 'installation_id_invalid', 128);
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(installationId)) {
    throw new SessionHttpError(400, 'installation_id_invalid');
  }
  return installationId;
}

async function readJson(request) {
  if (!request.headers.get('content-type')?.startsWith('application/json')) {
    throw new SessionHttpError(415, 'json_content_type_required');
  }
  const contentLength = Number(request.headers.get('content-length') ?? 0);
  if (Number.isFinite(contentLength) && contentLength > 16 * 1024) {
    throw new SessionHttpError(413, 'request_too_large');
  }
  const text = await request.text();
  if (text.length === 0 || text.length > 16 * 1024) {
    throw new SessionHttpError(400, 'invalid_json');
  }
  try {
    const body = JSON.parse(text);
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      throw new Error('not an object');
    }
    return body;
  } catch {
    throw new SessionHttpError(400, 'invalid_json');
  }
}

function resultChanges(result) {
  return Number(result?.meta?.changes ?? 0);
}

function bytesEqual(left, right) {
  const a = Buffer.from(left ?? []);
  const b = Buffer.from(right ?? []);
  return a.length === b.length && timingSafeEqual(a, b);
}

async function verifyP256({ publicKey, signature, message }) {
  try {
    const key = await globalThis.crypto.subtle.importKey(
      'raw',
      publicKey,
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['verify'],
    );
    return globalThis.crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' },
      key,
      signature,
      Buffer.from(message, 'utf8'),
    );
  } catch {
    return false;
  }
}

function parseJwtSegment(segment) {
  if (!/^[A-Za-z0-9_-]+$/.test(segment)) throw new Error('invalid JWT');
  const bytes = Buffer.from(segment, 'base64url');
  if (bytes.toString('base64url') !== segment) throw new Error('invalid JWT');
  return JSON.parse(bytes.toString('utf8'));
}

export function createCloudflareSessionSecurity({
  database,
  signingKey,
  issuer,
  installationCreditLimit,
  now = () => new Date(),
  randomBytesFactory = randomBytes,
  idFactory = randomUUID,
} = {}) {
  if (
    !database ||
    typeof database.prepare !== 'function' ||
    typeof database.batch !== 'function'
  ) {
    throw new TypeError('database is required.');
  }
  if (typeof signingKey !== 'string' || Buffer.byteLength(signingKey) < 32) {
    throw new TypeError('signingKey must contain at least 32 bytes.');
  }
  if (typeof issuer !== 'string' || !/^https:\/\/[^/]+$/.test(issuer)) {
    throw new TypeError('issuer must be an HTTPS origin without a path.');
  }
  if (
    !Number.isSafeInteger(installationCreditLimit) ||
    installationCreditLimit <= 0
  ) {
    throw new TypeError('installationCreditLimit must be a positive integer.');
  }

  function issueCredential(installationId) {
    const issuedAt = Math.floor(now().getTime() / 1000);
    const expiresAt = issuedAt + SESSION_TTL_SECONDS;
    const header = { alg: 'HS256', typ: 'JWT', kid: SESSION_KID };
    const claims = {
      iss: issuer,
      aud: SESSION_AUDIENCE,
      sub: `install:${installationId}`,
      scope: SESSION_SCOPE,
      iat: issuedAt,
      nbf: issuedAt - 5,
      exp: expiresAt,
      jti: base64url(randomBytesFactory(16)),
      ver: SESSION_VERSION,
    };
    const encodedHeader = base64url(JSON.stringify(header));
    const encodedClaims = base64url(JSON.stringify(claims));
    const signed = `${encodedHeader}.${encodedClaims}`;
    const signature = createHmac('sha256', signingKey)
      .update(signed)
      .digest('base64url');
    return {
      installationId,
      bearerToken: `${signed}.${signature}`,
      expiresAtEpochMilliseconds: expiresAt * 1000,
    };
  }

  async function authenticate(request) {
    try {
      const match = /^Bearer ([A-Za-z0-9._-]+)$/.exec(
        request.headers.get('authorization') ?? '',
      );
      if (!match || match[1].length > 4096) return null;
      const segments = match[1].split('.');
      if (segments.length !== 3) return null;
      const [encodedHeader, encodedClaims, encodedSignature] = segments;
      const header = parseJwtSegment(encodedHeader);
      const claims = parseJwtSegment(encodedClaims);
      if (
        header?.alg !== 'HS256' ||
        header?.typ !== 'JWT' ||
        header?.kid !== SESSION_KID
      ) {
        return null;
      }
      const expected = createHmac('sha256', signingKey)
        .update(`${encodedHeader}.${encodedClaims}`)
        .digest();
      const received = Buffer.from(encodedSignature, 'base64url');
      if (
        received.toString('base64url') !== encodedSignature ||
        received.length !== expected.length ||
        !timingSafeEqual(received, expected)
      ) {
        return null;
      }
      const current = Math.floor(now().getTime() / 1000);
      if (
        claims?.iss !== issuer ||
        claims?.aud !== SESSION_AUDIENCE ||
        claims?.scope !== SESSION_SCOPE ||
        claims?.ver !== SESSION_VERSION ||
        !/^install:[A-Za-z0-9_-]{16,128}$/.test(claims?.sub ?? '') ||
        !Number.isInteger(claims?.iat) ||
        !Number.isInteger(claims?.nbf) ||
        !Number.isInteger(claims?.exp) ||
        claims.exp <= claims.iat ||
        claims.exp - claims.iat > MAX_SESSION_LIFETIME_SECONDS ||
        claims.nbf > claims.iat ||
        claims.nbf < claims.iat - CLOCK_TOLERANCE_SECONDS ||
        claims.iat > current + CLOCK_TOLERANCE_SECONDS ||
        claims.nbf > current + CLOCK_TOLERANCE_SECONDS ||
        claims.exp <= current - CLOCK_TOLERANCE_SECONDS
      ) {
        return null;
      }
      decodeCanonicalBase64url(
        claims.jti,
        16,
        'jwt_jti_invalid',
      );
      const installationId = claims.sub.slice('install:'.length);
      const installation = await database
        .prepare(
          `SELECT status FROM installations WHERE id = ?`,
        )
        .bind(installationId)
        .first();
      return installation?.status === 'active'
        ? { ownerId: claims.sub }
        : null;
    } catch {
      return null;
    }
  }

  async function createChallenge({ purpose, keyId, installationId = null }) {
    const challengeId = idFactory();
    const challenge = base64url(randomBytesFactory(32));
    const expiresAt = now().getTime() + CHALLENGE_TTL_MILLISECONDS;
    await database
      .prepare(
        `INSERT INTO session_challenges
          (id, purpose, key_id, installation_id, nonce_hash, expires_at_ms, consumed_at_ms)
         VALUES (?, ?, ?, ?, ?, ?, NULL)`,
      )
      .bind(
        challengeId,
        purpose,
        keyId,
        installationId,
        sha256(challenge),
        expiresAt,
      )
      .run();
    return {
      challengeId,
      challenge,
      expiresAtEpochMilliseconds: expiresAt,
    };
  }

  async function requireChallenge({
    challengeId,
    challenge,
    purpose,
    keyId,
    installationId = null,
  }) {
    requireString(challengeId, 'challenge_id_invalid', 128);
    decodeCanonicalBase64url(challenge, 32, 'challenge_invalid');
    const row = await database
      .prepare(
        `SELECT id, nonce_hash, expires_at_ms, consumed_at_ms
           FROM session_challenges
          WHERE id = ? AND purpose = ? AND key_id = ?
            AND ((installation_id IS NULL AND ? IS NULL) OR installation_id = ?)`,
      )
      .bind(challengeId, purpose, keyId, installationId, installationId)
      .first();
    if (
      !row ||
      row.consumed_at_ms !== null ||
      Number(row.expires_at_ms) < now().getTime() ||
      row.nonce_hash !== sha256(challenge)
    ) {
      throw new SessionHttpError(401, 'challenge_invalid');
    }
    return row;
  }

  async function handleInstallationChallenge(request) {
    const body = await readJson(request);
    requireInstallationVersion(body.version);
    const keyId = requireKeyId(body.keyId);
    return json(200, await createChallenge({ purpose: 'installation', keyId }));
  }

  async function handleInstallation(request) {
    const body = await readJson(request);
    const version = requireInstallationVersion(body.version);
    const keyId = requireKeyId(body.keyId);
    const challengeId = requireString(
      body.challengeId,
      'challenge_id_invalid',
      128,
    );
    const challenge = requireString(body.challenge, 'challenge_invalid', 64);
    const publicKey = decodeCanonicalBase64url(
      body.publicKey,
      65,
      'public_key_invalid',
    );
    if (publicKey[0] !== 0x04 || sha256(publicKey) !== keyId) {
      throw new SessionHttpError(400, 'public_key_invalid');
    }
    const signature = decodeCanonicalBase64url(
      body.signature,
      64,
      'signature_invalid',
    );
    await requireChallenge({
      challengeId,
      challenge,
      purpose: 'installation',
      keyId,
    });
    if (version === PUBLIC_INSTALLATION_VERSION) {
      const message =
        `yingjian-installation-v2\n${challengeId}\n${challenge}\n` +
        `${keyId}\n`;
      if (!(await verifyP256({ publicKey, signature, message }))) {
        throw new SessionHttpError(401, 'signature_invalid');
      }
      const timestamp = now().getTime();
      const proposedInstallationId = idFactory();
      const results = await database.batch([
        database
          .prepare(
            `UPDATE session_challenges
                SET consumed_at_ms = ?
              WHERE id = ? AND purpose = 'installation' AND key_id = ?
                AND installation_id IS NULL AND consumed_at_ms IS NULL
                AND expires_at_ms >= ? AND nonce_hash = ?`,
          )
          .bind(timestamp, challengeId, keyId, timestamp, sha256(challenge)),
        database
          .prepare(
            `INSERT INTO installations
              (id, key_id, public_key_x963, status, credit_limit, created_at_ms, last_seen_at_ms)
             VALUES (?, ?, ?, 'active', ?, ?, ?)
             ON CONFLICT(key_id) DO UPDATE SET last_seen_at_ms = excluded.last_seen_at_ms
               WHERE installations.public_key_x963 = excluded.public_key_x963
                 AND installations.status = 'active'`,
          )
          .bind(
            proposedInstallationId,
            keyId,
            publicKey,
            installationCreditLimit,
            timestamp,
            timestamp,
          ),
        database
          .prepare(
            `INSERT INTO usage_accounts
              (owner_id, credit_limit, status, created_at_ms, updated_at_ms)
             SELECT 'install:' || id, credit_limit, 'active', ?, ?
               FROM installations
              WHERE key_id = ? AND public_key_x963 = ? AND status = 'active'
             ON CONFLICT(owner_id) DO UPDATE SET updated_at_ms = excluded.updated_at_ms`,
          )
          .bind(timestamp, timestamp, keyId, publicKey),
      ]);
      if (resultChanges(results[0]) !== 1) {
        throw new SessionHttpError(401, 'installation_activation_failed');
      }
      const installation = await database
        .prepare(
          `SELECT id, public_key_x963, status
             FROM installations WHERE key_id = ?`,
        )
        .bind(keyId)
        .first();
      if (
        !installation ||
        installation.status !== 'active' ||
        !bytesEqual(installation.public_key_x963, publicKey)
      ) {
        throw new SessionHttpError(401, 'installation_activation_failed');
      }
      return json(200, issueCredential(installation.id));
    }

    const enrollmentCode = requireString(
      body.enrollmentCode,
      'enrollment_code_invalid',
      64,
    );
    decodeCanonicalBase64url(enrollmentCode, 32, 'enrollment_code_invalid');
    const codeHash = sha256(enrollmentCode);
    const message =
      `yingjian-installation-v1\n${challengeId}\n${challenge}\n` +
      `${keyId}\n${codeHash}\n`;
    if (!(await verifyP256({ publicKey, signature, message }))) {
      throw new SessionHttpError(401, 'signature_invalid');
    }
    const enrollment = await database
      .prepare(
        `SELECT code_hash, expires_at_ms, credit_limit, bound_key_id, bound_installation_id
           FROM enrollment_codes WHERE code_hash = ?`,
      )
      .bind(codeHash)
      .first();
    const timestamp = now().getTime();
    if (
      !enrollment ||
      Number(enrollment.expires_at_ms) < timestamp ||
      (enrollment.bound_key_id !== null && enrollment.bound_key_id !== keyId)
    ) {
      throw new SessionHttpError(401, 'enrollment_code_invalid');
    }
    const proposedInstallationId =
      enrollment.bound_installation_id ?? idFactory();
    const results = await database.batch([
      database
        .prepare(
          `UPDATE session_challenges
              SET consumed_at_ms = ?
            WHERE id = ? AND purpose = 'installation' AND key_id = ?
              AND installation_id IS NULL AND consumed_at_ms IS NULL
              AND expires_at_ms >= ? AND nonce_hash = ?`,
        )
        .bind(timestamp, challengeId, keyId, timestamp, sha256(challenge)),
      database
        .prepare(
          `UPDATE enrollment_codes
              SET bound_key_id = ?,
                  bound_installation_id = COALESCE(bound_installation_id, ?),
                  consumed_at_ms = COALESCE(consumed_at_ms, ?)
            WHERE code_hash = ? AND expires_at_ms >= ?
              AND (bound_key_id IS NULL OR bound_key_id = ?)`,
        )
        .bind(
          keyId,
          proposedInstallationId,
          timestamp,
          codeHash,
          timestamp,
          keyId,
        ),
      database
        .prepare(
          `INSERT INTO installations
            (id, key_id, public_key_x963, status, credit_limit, created_at_ms, last_seen_at_ms)
           SELECT bound_installation_id, bound_key_id, ?, 'active', credit_limit, ?, ?
             FROM enrollment_codes
            WHERE code_hash = ? AND bound_key_id = ?
           ON CONFLICT(key_id) DO UPDATE SET last_seen_at_ms = excluded.last_seen_at_ms
             WHERE installations.public_key_x963 = excluded.public_key_x963`,
        )
        .bind(publicKey, timestamp, timestamp, codeHash, keyId),
      database
        .prepare(
          `INSERT INTO usage_accounts
            (owner_id, credit_limit, status, created_at_ms, updated_at_ms)
           SELECT 'install:' || bound_installation_id, credit_limit, 'active', ?, ?
             FROM enrollment_codes
            WHERE code_hash = ? AND bound_key_id = ?
           ON CONFLICT(owner_id) DO UPDATE SET updated_at_ms = excluded.updated_at_ms`,
        )
        .bind(timestamp, timestamp, codeHash, keyId),
    ]);
    if (resultChanges(results[0]) !== 1 || resultChanges(results[1]) !== 1) {
      throw new SessionHttpError(401, 'installation_activation_failed');
    }
    const installation = await database
      .prepare(
        `SELECT i.id, i.public_key_x963, i.status
           FROM installations i
           JOIN enrollment_codes e ON e.bound_installation_id = i.id
          WHERE e.code_hash = ? AND e.bound_key_id = ? AND i.key_id = ?`,
      )
      .bind(codeHash, keyId, keyId)
      .first();
    if (
      !installation ||
      installation.status !== 'active' ||
      !bytesEqual(installation.public_key_x963, publicKey)
    ) {
      throw new SessionHttpError(401, 'installation_activation_failed');
    }
    return json(200, issueCredential(installation.id));
  }

  async function handleGenerationSessionChallenge(request) {
    const body = await readJson(request);
    requireVersion(body.version);
    const installationId = requireInstallationId(body.installationId);
    const keyId = requireKeyId(body.keyId);
    const installation = await database
      .prepare(
        `SELECT status FROM installations WHERE id = ? AND key_id = ?`,
      )
      .bind(installationId, keyId)
      .first();
    if (installation?.status !== 'active') {
      throw new SessionHttpError(401, 'installation_invalid');
    }
    return json(
      200,
      await createChallenge({
        purpose: 'generation_session',
        keyId,
        installationId,
      }),
    );
  }

  async function handleGenerationSession(request) {
    const body = await readJson(request);
    requireVersion(body.version);
    const installationId = requireInstallationId(body.installationId);
    const keyId = requireKeyId(body.keyId);
    const challengeId = requireString(
      body.challengeId,
      'challenge_id_invalid',
      128,
    );
    const challenge = requireString(body.challenge, 'challenge_invalid', 64);
    const signature = decodeCanonicalBase64url(
      body.signature,
      64,
      'signature_invalid',
    );
    const installation = await database
      .prepare(
        `SELECT public_key_x963, status
           FROM installations WHERE id = ? AND key_id = ?`,
      )
      .bind(installationId, keyId)
      .first();
    if (installation?.status !== 'active') {
      throw new SessionHttpError(401, 'installation_invalid');
    }
    await requireChallenge({
      challengeId,
      challenge,
      purpose: 'generation_session',
      keyId,
      installationId,
    });
    const publicKey = Buffer.from(installation.public_key_x963);
    const message =
      `yingjian-generation-session-v1\n${challengeId}\n${challenge}\n` +
      `${installationId}\n${keyId}\n`;
    if (!(await verifyP256({ publicKey, signature, message }))) {
      throw new SessionHttpError(401, 'signature_invalid');
    }
    const timestamp = now().getTime();
    const results = await database.batch([
      database
        .prepare(
          `UPDATE session_challenges
              SET consumed_at_ms = ?
            WHERE id = ? AND purpose = 'generation_session' AND key_id = ?
              AND installation_id = ? AND consumed_at_ms IS NULL
              AND expires_at_ms >= ? AND nonce_hash = ?`,
        )
        .bind(
          timestamp,
          challengeId,
          keyId,
          installationId,
          timestamp,
          sha256(challenge),
        ),
      database
        .prepare(
          `UPDATE installations SET last_seen_at_ms = ?
            WHERE id = ? AND key_id = ? AND status = 'active'`,
        )
        .bind(timestamp, installationId, keyId),
    ]);
    if (resultChanges(results[0]) !== 1 || resultChanges(results[1]) !== 1) {
      throw new SessionHttpError(401, 'session_creation_failed');
    }
    return json(200, issueCredential(installationId));
  }

  async function handleRequest(request) {
    const pathname = new URL(request.url).pathname;
    if (!SESSION_PATHS.has(pathname)) return null;
    if (request.method !== 'POST') {
      return json(405, { error: { code: 'method_not_allowed' } });
    }
    try {
      if (pathname === '/v1/installation-challenges') {
        return await handleInstallationChallenge(request);
      }
      if (pathname === '/v1/installations') {
        return await handleInstallation(request);
      }
      if (pathname === '/v1/generation-session-challenges') {
        return await handleGenerationSessionChallenge(request);
      }
      return await handleGenerationSession(request);
    } catch (error) {
      if (error instanceof SessionHttpError) {
        return json(error.status, { error: { code: error.code } });
      }
      return json(500, { error: { code: 'internal_error' } });
    }
  }

  async function sweepExpired() {
    const timestamp = now().getTime();
    await database.batch([
      database
        .prepare(`DELETE FROM session_challenges WHERE expires_at_ms < ?`)
        .bind(timestamp - 60_000),
      database
        .prepare(`DELETE FROM enrollment_codes WHERE expires_at_ms < ?`)
        .bind(timestamp - 60_000),
    ]);
  }

  return { authenticate, handleRequest, sweepExpired, issueCredential };
}

export {
  CHALLENGE_TTL_MILLISECONDS,
  SESSION_AUDIENCE,
  SESSION_KID,
  SESSION_TTL_SECONDS,
};
