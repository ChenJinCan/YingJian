import assert from 'node:assert/strict';
import test from 'node:test';

import { createLocalSharedBearerAuthenticator } from '../src/infrastructure/local-shared-bearer-authenticator.mjs';

test('local shared bearer authentication is explicit and rejects every other token', async () => {
  const authenticate = createLocalSharedBearerAuthenticator({
    bearerToken: 'local-evaluation-token',
    ownerId: 'local-owner',
  });

  assert.deepEqual(
    await authenticate(
      new Request('http://localhost', {
        headers: { authorization: 'Bearer local-evaluation-token' },
      }),
    ),
    { ownerId: 'local-owner' },
  );
  assert.equal(
    await authenticate(
      new Request('http://localhost', {
        headers: { authorization: 'Bearer another-token' },
      }),
    ),
    null,
  );
  assert.equal(await authenticate(new Request('http://localhost')), null);
});

test('local shared bearer authentication has no credential default', () => {
  assert.throws(
    () => createLocalSharedBearerAuthenticator({ ownerId: 'local-owner' }),
    /bearerToken is required/,
  );
});
