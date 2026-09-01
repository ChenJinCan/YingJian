import assert from 'node:assert/strict';
import test from 'node:test';

import { VolcengineOldPhotoProvider } from '../src/providers/volcengine-old-photo.mjs';

test('old photo repair is feature-gated off unless explicitly enabled', async () => {
  let called = false;
  const provider = new VolcengineOldPhotoProvider({
    accessKeyId: 'test-ak',
    secretAccessKey: 'test-secret',
    fetchImpl: async () => {
      called = true;
      return Response.json({});
    },
  });

  await assert.rejects(
    provider.submit({
      capability: 'optimizeOldPhoto',
      sourceUri: 'data:image/jpeg;base64,c291cmNl',
      colorMode: 'preserve',
    }),
    (error) => error.code === 'capability_disabled' && error.status === 503,
  );
  assert.equal(called, false);
});

test('disabled old photo repair does not require dormant provider credentials', async () => {
  const provider = new VolcengineOldPhotoProvider({
    fetchImpl: async () => {
      throw new Error('must not call provider');
    },
  });

  await assert.rejects(
    provider.submit({
      capability: 'optimizeOldPhoto',
      sourceUri: 'data:image/jpeg;base64,c291cmNl',
      colorMode: 'preserve',
    }),
    (error) => error.code === 'capability_disabled',
  );
});

test('enabled old photo repair signs LensOpr and fixes if_color to keep original color', async () => {
  const calls = [];
  const provider = new VolcengineOldPhotoProvider({
    accessKeyId: 'test-ak',
    secretAccessKey: 'test-secret',
    enabled: true,
    now: () => new Date('2026-09-01T01:02:03Z'),
    fetchImpl: async (url, init) => {
      calls.push({ url: String(url), init });
      return Response.json({
        code: 10000,
        request_id: 'volc-request-1',
        data: { binary_data_base64: ['restored-base64'] },
      });
    },
  });

  const result = await provider.submit({
    capability: 'optimizeOldPhoto',
    sourceUri: 'data:image/jpeg;base64,c291cmNl',
    colorMode: 'preserve',
  });

  assert.equal(
    calls[0].url,
    'https://visual.volcengineapi.com/?Action=LensOpr&Version=2024-06-06',
  );
  const body = JSON.parse(calls[0].init.body);
  assert.deepEqual(body, {
    req_key: 'lens_opr',
    binary_data_base64: ['c291cmNl'],
    if_color: 0,
  });
  assert.equal(JSON.stringify(body).includes('if_color":2'), false);
  assert.equal(
    calls[0].init.headers['x-content-sha256'],
    '2cd844516f9ff231eab23cf25d9f41019dc04024ada65890bc214eb6a472a446',
  );
  assert.equal(calls[0].init.headers['x-date'], '20260901T010203Z');
  assert.equal(
    calls[0].init.headers.authorization,
    'HMAC-SHA256 Credential=test-ak/20260901/cn-beijing/cv/request, SignedHeaders=content-type;host;x-content-sha256;x-date, Signature=5fe0438ed68cf2a6e53d7ae1ae5b9dd07f41da81273bb9ed9df6a3912b370fa7',
  );
  assert.equal(provider.cancelPolicy, 'none');
  assert.equal('cancel' in provider, false);
  assert.deepEqual(result, {
    kind: 'succeeded',
    provider: 'volcengine',
    model: 'lens_opr',
    providerRequestId: 'volc-request-1',
    providerCancelable: false,
    output: {
      kind: 'base64',
      mimeType: 'image/jpeg',
      data: 'restored-base64',
    },
  });
});

test('old photo colorization occurs only when colorize was explicitly selected', async () => {
  let requestBody;
  const provider = new VolcengineOldPhotoProvider({
    accessKeyId: 'test-ak',
    secretAccessKey: 'test-secret',
    enabled: true,
    fetchImpl: async (_url, init) => {
      requestBody = JSON.parse(init.body);
      return Response.json({
        code: 10000,
        data: { binary_data_base64: ['restored-base64'] },
      });
    },
  });

  await provider.submit({
    capability: 'optimizeOldPhoto',
    sourceUri: 'data:image/jpeg;base64,c291cmNl',
    colorMode: 'colorize',
  });
  assert.equal(requestBody.if_color, 1);
  assert.notEqual(requestBody.if_color, 2);

  await assert.rejects(
    provider.submit({
      capability: 'optimizeOldPhoto',
      sourceUri: 'data:image/jpeg;base64,c291cmNl',
    }),
    (error) => error.code === 'color_mode_required',
  );
});
