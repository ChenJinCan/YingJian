import assert from 'node:assert/strict';
import test from 'node:test';

import {
  BaiduImageRepairProvider,
  createBaiduAccessTokenProvider,
} from '../src/providers/baidu-image-repair.mjs';

test('AI repair calls only Baidu image_definition_enhance with the confirmed image', async () => {
  const calls = [];
  const provider = new BaiduImageRepairProvider({
    accessTokenProvider: async () => 'server-token',
    fetchImpl: async (url, init) => {
      calls.push({ url: String(url), init });
      return Response.json({ image: 'repaired-base64', log_id: 9001 });
    },
  });

  const result = await provider.submit({
    capability: 'optimizeAiRepair',
    sourceUri: 'data:image/jpeg;base64,c291cmNl',
  });

  assert.equal(calls.length, 1);
  const call = calls[0];
  assert.equal(
    call.url,
    'https://aip.baidubce.com/rest/2.0/image-process/v1/image_definition_enhance?access_token=server-token',
  );
  assert.equal(call.init.method, 'POST');
  assert.equal(
    call.init.headers['content-type'],
    'application/x-www-form-urlencoded',
  );
  assert.deepEqual(
    Object.fromEntries(new URLSearchParams(call.init.body)),
    { image: 'c291cmNl' },
  );
  assert.equal(call.init.body.includes('url='), false);
  assert.equal(call.init.body.includes('beaut'), false);
  assert.deepEqual(result, {
    kind: 'succeeded',
    provider: 'baidu',
    model: 'image_definition_enhance',
    providerRequestId: '9001',
    providerCancelable: false,
    output: {
      kind: 'base64',
      mimeType: 'image/jpeg',
      data: 'repaired-base64',
    },
  });
});

test('Baidu sync AI repair never claims provider cancellation', () => {
  const provider = new BaiduImageRepairProvider({
    accessTokenProvider: async () => 'server-token',
    fetchImpl: async () => Response.json({}),
  });

  assert.equal(provider.cancelPolicy, 'none');
  assert.equal('cancel' in provider, false);
});

test('Baidu OAuth credentials are exchanged server-side and the token is cached', async () => {
  const calls = [];
  const accessTokenProvider = createBaiduAccessTokenProvider({
    apiKey: 'api key',
    secretKey: 'secret/key',
    now: () => new Date('2026-09-01T00:00:00Z'),
    fetchImpl: async (url, init) => {
      calls.push({ url: String(url), init });
      return Response.json({ access_token: 'provider-token', expires_in: 3600 });
    },
  });

  assert.equal(await accessTokenProvider(), 'provider-token');
  assert.equal(await accessTokenProvider(), 'provider-token');
  assert.equal(calls.length, 1);
  assert.equal(
    calls[0].url,
    'https://aip.baidubce.com/oauth/2.0/token?grant_type=client_credentials&client_id=api+key&client_secret=secret%2Fkey',
  );
  assert.equal(calls[0].init.method, 'POST');
});
