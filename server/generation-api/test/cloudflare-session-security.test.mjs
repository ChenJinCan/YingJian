import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { createCloudflareSessionSecurity } from '../src/cloudflare/session-security.mjs';
import { TestD1Database } from './cloudflare-d1-test-binding.mjs';

const schema = await readFile(
  new URL('../migrations/0001_generation_mvp.sql', import.meta.url),
  'utf8',
);

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function request(path, body, headers = {}) {
  return new Request(`https://generation.example${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
}

async function p256Identity() {
  const keyPair = await globalThis.crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' },
    true,
    ['sign', 'verify'],
  );
  const publicKey = Buffer.from(
    await globalThis.crypto.subtle.exportKey('raw', keyPair.publicKey),
  );
  return {
    keyPair,
    publicKey,
    publicKeyEncoded: publicKey.toString('base64url'),
    keyId: sha256(publicKey),
    async sign(message) {
      return Buffer.from(
        await globalThis.crypto.subtle.sign(
          { name: 'ECDSA', hash: 'SHA-256' },
          keyPair.privateKey,
          Buffer.from(message),
        ),
      ).toString('base64url');
    },
  };
}

async function v2Challenge(security, identity) {
  const response = await security.handleRequest(
    request('/v1/installation-challenges', {
      version: 2,
      keyId: identity.keyId,
    }),
  );
  assert.equal(response.status, 200);
  return response.json();
}

async function v2InstallationBody(identity, challenge, message = null) {
  const signedMessage =
    message ??
    (`yingjian-installation-v2\n${challenge.challengeId}\n` +
      `${challenge.challenge}\n${identity.keyId}\n`);
  return {
    version: 2,
    challengeId: challenge.challengeId,
    challenge: challenge.challenge,
    keyId: identity.keyId,
    publicKey: identity.publicKeyEncoded,
    signature: await identity.sign(signedMessage),
  };
}

async function enrollV2(security, identity) {
  const challenge = await v2Challenge(security, identity);
  const body = await v2InstallationBody(identity, challenge);
  const response = await security.handleRequest(
    request('/v1/installations', body),
  );
  return { body, response };
}

test('v2 automatically enrolls a proof-of-possession installation without an activation code', async (t) => {
  const db = new TestD1Database(schema);
  t.after(() => db.close());
  const current = new Date('2026-09-01T00:00:00.000Z');
  let nextId = 0;
  const security = createCloudflareSessionSecurity({
    database: db,
    signingKey: '0123456789abcdef0123456789abcdef',
    issuer: 'https://generation.example',
    installationCreditLimit: 5,
    now: () => current,
    idFactory: () => `test-identifier-${String(++nextId).padStart(4, '0')}`,
  });
  const identity = await p256Identity();

  const challengeResponse = await security.handleRequest(
    request('/v1/installation-challenges', {
      version: 2,
      keyId: identity.keyId,
    }),
  );
  assert.equal(challengeResponse.status, 200);
  const challenge = await challengeResponse.json();
  const installationMessage =
    `yingjian-installation-v2\n${challenge.challengeId}\n` +
    `${challenge.challenge}\n${identity.keyId}\n`;
  const installationResponse = await security.handleRequest(
    request('/v1/installations', {
      version: 2,
      challengeId: challenge.challengeId,
      challenge: challenge.challenge,
      keyId: identity.keyId,
      publicKey: identity.publicKeyEncoded,
      signature: await identity.sign(installationMessage),
    }),
  );

  assert.equal(installationResponse.status, 200);
  const credential = await installationResponse.json();
  assert.match(credential.installationId, /^test-identifier-/);
  assert.equal(
    credential.expiresAtEpochMilliseconds,
    current.getTime() + 10 * 60 * 1000,
  );
  assert.deepEqual(
    await security.authenticate(
      new Request('https://generation.example/v1/generation-capabilities', {
        headers: { authorization: `Bearer ${credential.bearerToken}` },
      }),
    ),
    { ownerId: `install:${credential.installationId}` },
  );
  const installation = await db
    .prepare(`SELECT credit_limit FROM installations WHERE id = ?`)
    .bind(credential.installationId)
    .first();
  const account = await db
    .prepare(`SELECT credit_limit FROM usage_accounts WHERE owner_id = ?`)
    .bind(`install:${credential.installationId}`)
    .first();
  assert.equal(installation.credit_limit, 5);
  assert.equal(account.credit_limit, 5);
});

test('v2 requires valid proof of possession and rejects challenge replay', async (t) => {
  const db = new TestD1Database(schema);
  t.after(() => db.close());
  const security = createCloudflareSessionSecurity({
    database: db,
    signingKey: '0123456789abcdef0123456789abcdef',
    issuer: 'https://generation.example',
    installationCreditLimit: 5,
  });
  const identity = await p256Identity();
  const challenge = await v2Challenge(security, identity);
  const invalidBody = await v2InstallationBody(
    identity,
    challenge,
    'not-the-installation-challenge',
  );

  const rejected = await security.handleRequest(
    request('/v1/installations', invalidBody),
  );
  assert.equal(rejected.status, 401);
  assert.equal((await rejected.json()).error.code, 'signature_invalid');

  const body = await v2InstallationBody(identity, challenge);
  const accepted = await security.handleRequest(
    request('/v1/installations', body),
  );
  assert.equal(accepted.status, 200);

  const replay = await security.handleRequest(
    request('/v1/installations', body),
  );
  assert.equal(replay.status, 401);
  assert.equal((await replay.json()).error.code, 'challenge_invalid');
});

test('v2 retry with the same key keeps the installation and existing quota', async (t) => {
  const db = new TestD1Database(schema);
  t.after(() => db.close());
  let nextId = 0;
  const security = createCloudflareSessionSecurity({
    database: db,
    signingKey: '0123456789abcdef0123456789abcdef',
    issuer: 'https://generation.example',
    installationCreditLimit: 5,
    idFactory: () => `test-identifier-${String(++nextId).padStart(4, '0')}`,
  });
  const identity = await p256Identity();
  const first = await enrollV2(security, identity);
  assert.equal(first.response.status, 200);
  const firstCredential = await first.response.json();
  const ownerId = `install:${firstCredential.installationId}`;
  await db
    .prepare(`UPDATE installations SET credit_limit = 2 WHERE id = ?`)
    .bind(firstCredential.installationId)
    .run();
  await db
    .prepare(`UPDATE usage_accounts SET credit_limit = 2 WHERE owner_id = ?`)
    .bind(ownerId)
    .run();

  const second = await enrollV2(security, identity);
  assert.equal(second.response.status, 200);
  const secondCredential = await second.response.json();
  assert.equal(secondCredential.installationId, firstCredential.installationId);
  const installation = await db
    .prepare(`SELECT credit_limit FROM installations WHERE id = ?`)
    .bind(firstCredential.installationId)
    .first();
  const account = await db
    .prepare(`SELECT credit_limit FROM usage_accounts WHERE owner_id = ?`)
    .bind(ownerId)
    .first();
  assert.equal(installation.credit_limit, 2);
  assert.equal(account.credit_limit, 2);
});

test('v2 retry cannot reactivate a revoked installation or quota account', async (t) => {
  const db = new TestD1Database(schema);
  t.after(() => db.close());
  const security = createCloudflareSessionSecurity({
    database: db,
    signingKey: '0123456789abcdef0123456789abcdef',
    issuer: 'https://generation.example',
    installationCreditLimit: 5,
  });
  const identity = await p256Identity();
  const first = await enrollV2(security, identity);
  assert.equal(first.response.status, 200);
  const credential = await first.response.json();
  const ownerId = `install:${credential.installationId}`;
  await db
    .prepare(`UPDATE installations SET status = 'revoked' WHERE id = ?`)
    .bind(credential.installationId)
    .run();
  await db
    .prepare(`UPDATE usage_accounts SET status = 'revoked' WHERE owner_id = ?`)
    .bind(ownerId)
    .run();

  const retry = await enrollV2(security, identity);
  assert.equal(retry.response.status, 401);
  assert.equal(
    (await retry.response.json()).error.code,
    'installation_activation_failed',
  );
  const installation = await db
    .prepare(`SELECT status FROM installations WHERE id = ?`)
    .bind(credential.installationId)
    .first();
  const account = await db
    .prepare(`SELECT status FROM usage_accounts WHERE owner_id = ?`)
    .bind(ownerId)
    .first();
  assert.equal(installation.status, 'revoked');
  assert.equal(account.status, 'revoked');
  assert.equal(
    await security.authenticate(
      new Request('https://generation.example/v1/generation-capabilities', {
        headers: { authorization: `Bearer ${credential.bearerToken}` },
      }),
    ),
    null,
  );
});

test('one-time enrollment binds a P-256 key and mints only proof-of-possession sessions', async (t) => {
  const db = new TestD1Database(schema);
  t.after(() => db.close());
  const current = new Date('2026-09-01T00:00:00.000Z');
  let nextId = 0;
  const security = createCloudflareSessionSecurity({
    database: db,
    signingKey: '0123456789abcdef0123456789abcdef',
    issuer: 'https://generation.example',
    installationCreditLimit: 5,
    now: () => current,
    idFactory: () => `test-identifier-${String(++nextId).padStart(4, '0')}`,
  });
  const identity = await p256Identity();
  const enrollmentCode = Buffer.alloc(32, 7).toString('base64url');
  const enrollmentHash = sha256(enrollmentCode);
  await db
    .prepare(
      `INSERT INTO enrollment_codes
        (code_hash, expires_at_ms, credit_limit, bound_key_id,
         bound_installation_id, consumed_at_ms)
       VALUES (?, ?, 5, NULL, NULL, NULL)`,
    )
    .bind(enrollmentHash, current.getTime() + 10 * 60 * 1000)
    .run();

  const challengeResponse = await security.handleRequest(
    request('/v1/installation-challenges', {
      version: 1,
      keyId: identity.keyId,
    }),
  );
  assert.equal(challengeResponse.status, 200);
  const challenge = await challengeResponse.json();
  const installationMessage =
    `yingjian-installation-v1\n${challenge.challengeId}\n` +
    `${challenge.challenge}\n${identity.keyId}\n${enrollmentHash}\n`;
  const installationResponse = await security.handleRequest(
    request('/v1/installations', {
      version: 1,
      challengeId: challenge.challengeId,
      challenge: challenge.challenge,
      enrollmentCode,
      keyId: identity.keyId,
      publicKey: identity.publicKeyEncoded,
      signature: await identity.sign(installationMessage),
    }),
  );
  assert.equal(installationResponse.status, 200);
  const credential = await installationResponse.json();
  assert.match(credential.installationId, /^test-identifier-/);
  assert.equal(
    credential.expiresAtEpochMilliseconds,
    current.getTime() + 10 * 60 * 1000,
  );
  assert.deepEqual(
    await security.authenticate(
      new Request('https://generation.example/v1/generation-capabilities', {
        headers: { authorization: `Bearer ${credential.bearerToken}` },
      }),
    ),
    { ownerId: `install:${credential.installationId}` },
  );

  const storedCode = await db
    .prepare(
      `SELECT code_hash, bound_key_id, bound_installation_id
         FROM enrollment_codes WHERE code_hash = ?`,
    )
    .bind(enrollmentHash)
    .first();
  assert.equal(storedCode.code_hash, enrollmentHash);
  assert.equal(storedCode.bound_key_id, identity.keyId);
  assert.equal(storedCode.bound_installation_id, credential.installationId);
  assert.equal(JSON.stringify(storedCode).includes(enrollmentCode), false);

  const sessionChallengeResponse = await security.handleRequest(
    request('/v1/generation-session-challenges', {
      version: 1,
      installationId: credential.installationId,
      keyId: identity.keyId,
    }),
  );
  assert.equal(sessionChallengeResponse.status, 200);
  const sessionChallenge = await sessionChallengeResponse.json();
  const sessionMessage =
    `yingjian-generation-session-v1\n${sessionChallenge.challengeId}\n` +
    `${sessionChallenge.challenge}\n${credential.installationId}\n` +
    `${identity.keyId}\n`;
  const sessionRequest = {
    version: 1,
    installationId: credential.installationId,
    keyId: identity.keyId,
    challengeId: sessionChallenge.challengeId,
    challenge: sessionChallenge.challenge,
    signature: await identity.sign(sessionMessage),
  };
  const sessionResponse = await security.handleRequest(
    request('/v1/generation-sessions', sessionRequest),
  );
  assert.equal(sessionResponse.status, 200);
  assert.equal(typeof (await sessionResponse.json()).bearerToken, 'string');
  const replay = await security.handleRequest(
    request('/v1/generation-sessions', sessionRequest),
  );
  assert.equal(replay.status, 401);
  assert.equal((await replay.json()).error.code, 'challenge_invalid');

  const arbitraryInstallation = await security.handleRequest(
    request('/v1/generation-session-challenges', {
      version: 1,
      installationId: 'not-a-real-installation',
      keyId: identity.keyId,
    }),
  );
  assert.equal(arbitraryInstallation.status, 401);
});

test('invalid JWTs and revoked installations fail closed', async (t) => {
  const db = new TestD1Database(schema);
  t.after(() => db.close());
  const security = createCloudflareSessionSecurity({
    database: db,
    signingKey: '0123456789abcdef0123456789abcdef',
    issuer: 'https://generation.example',
    installationCreditLimit: 5,
  });
  assert.equal(
    await security.authenticate(
      new Request('https://generation.example', {
        headers: { authorization: 'Bearer public-shared-token' },
      }),
    ),
    null,
  );
  assert.equal(
    await security.authenticate(new Request('https://generation.example')),
    null,
  );
});
