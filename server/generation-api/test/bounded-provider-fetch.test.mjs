import assert from 'node:assert/strict';
import test from 'node:test';

import {
  fetchProviderJson,
  ProviderConcurrencyGate,
} from '../src/providers/bounded-provider-fetch.mjs';

test(
  'provider deadline covers a response body that hangs after headers',
  { timeout: 500 },
  async () => {
    await assert.rejects(
      fetchProviderJson({
        fetchImpl: async (_url, init) =>
          new Response(
            new ReadableStream({
              start(controller) {
                controller.enqueue(new TextEncoder().encode('{"ok":'));
                init.signal.addEventListener(
                  'abort',
                  () => controller.error(init.signal.reason),
                  { once: true },
                );
              },
            }),
            { status: 200 },
          ),
        url: 'https://provider.example',
        init: { method: 'POST' },
        timeoutMilliseconds: 20,
        maxResponseBytes: 1024,
      }),
      (error) =>
        error.code === 'provider_timeout' &&
        error.status === 504 &&
        error.billingDisposition === 'hold',
    );
  },
);

test('provider transport caps concurrent upstream requests', async () => {
  const gate = new ProviderConcurrencyGate({ maximumConcurrent: 1 });
  let active = 0;
  let maximumObserved = 0;
  const fetchImpl = async () => {
    active += 1;
    maximumObserved = Math.max(maximumObserved, active);
    await new Promise((resolve) => setTimeout(resolve, 10));
    active -= 1;
    return Response.json({ ok: true });
  };
  await Promise.all([
    fetchProviderJson({
      fetchImpl,
      concurrencyGate: gate,
      url: 'https://provider.example/a',
      init: {},
      timeoutMilliseconds: 100,
      maxResponseBytes: 1024,
    }),
    fetchProviderJson({
      fetchImpl,
      concurrencyGate: gate,
      url: 'https://provider.example/b',
      init: {},
      timeoutMilliseconds: 100,
      maxResponseBytes: 1024,
    }),
  ]);
  assert.equal(maximumObserved, 1);
});
