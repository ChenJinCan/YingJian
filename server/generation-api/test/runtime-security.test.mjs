import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { createGenerationRuntime } from '../src/runtime.mjs';

function localEvaluationEnvironment(directory, overrides = {}) {
  return {
    GENERATION_ALLOW_SHARED_BEARER_AUTH: 'true',
    GENERATION_LOCAL_BEARER_TOKEN: '0123456789abcdef',
    GENERATION_LOCAL_OWNER_ID: 'local-owner',
    GENERATION_LOCAL_MAX_CREDITS: '10',
    GENERATION_LOCAL_MAX_CONCURRENT: '2',
    GENERATION_LOCAL_MAX_RESERVATIONS_PER_WINDOW: '5',
    GENERATION_LOCAL_RATE_WINDOW_MS: '60000',
    GENERATION_LOCAL_MAX_STORAGE_BYTES: '52428800',
    GENERATION_OFFER_SIGNING_KEY: '0123456789abcdef0123456789abcdef',
    GENERATION_TASK_DIRECTORY: join(directory, 'tasks'),
    GENERATION_MEDIA_DIRECTORY: join(directory, 'media'),
    ...overrides,
  };
}

async function discoverCapabilityStates(runtime) {
  const response = await runtime.handler(
    new Request('http://localhost/v1/generation-capabilities', {
      headers: { authorization: 'Bearer 0123456789abcdef' },
    }),
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.capabilities.length, 6);
  return Object.fromEntries(
    body.capabilities.map(({ capability, enabled }) => [capability, enabled]),
  );
}

test('runtime refuses production authentication without an injected usage guard', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'yingjian-runtime-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const authModule = join(directory, 'auth.mjs');
  await writeFile(
    authModule,
    "export async function authenticate() { return { ownerId: 'owner-a' }; }\n",
  );
  await assert.rejects(
    createGenerationRuntime({
      env: {
        GENERATION_AUTH_MODULE: authModule,
      },
    }),
    /No production usage guard configured/,
  );
});

test('loopback evaluation guard requires every explicit fixed limit', async () => {
  await assert.rejects(
    createGenerationRuntime({
      env: {
        GENERATION_ALLOW_SHARED_BEARER_AUTH: 'true',
        GENERATION_LOCAL_BEARER_TOKEN: '0123456789abcdef',
        GENERATION_LOCAL_OWNER_ID: 'local-owner',
      },
    }),
    /GENERATION_LOCAL_MAX_CREDITS is required/,
  );
  await assert.rejects(
    createGenerationRuntime({
      env: {
        GENERATION_ALLOW_SHARED_BEARER_AUTH: 'true',
        GENERATION_HOST: '0.0.0.0',
        GENERATION_LOCAL_BEARER_TOKEN: '0123456789abcdef',
        GENERATION_LOCAL_OWNER_ID: 'local-owner',
      },
    }),
    /require loopback/,
  );
});

test('runtime keeps every provider capability disabled when enable flags are missing', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'yingjian-disabled-runtime-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const runtime = await createGenerationRuntime({
    env: localEvaluationEnvironment(directory),
    fetchImpl: async () => { throw new Error('network must not be used'); },
  });
  t.after(() => runtime.close());

  const states = await discoverCapabilityStates(runtime);
  assert.equal(
    Object.values(states).every((enabled) => enabled === false),
    true,
  );
});

test('runtime keeps every provider capability disabled when enable flags are false', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'yingjian-false-runtime-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const runtime = await createGenerationRuntime({
    env: localEvaluationEnvironment(directory, {
      BAIDU_IMAGE_REPAIR_ENABLED: 'false',
      ALIBABA_IMAGE_ENABLED: 'false',
      ALIBABA_VIDEO_ENABLED: 'false',
      VOLC_LENS_OPR_ENABLED: 'false',
    }),
    fetchImpl: async () => { throw new Error('network must not be used'); },
  });
  t.after(() => runtime.close());

  const states = await discoverCapabilityStates(runtime);
  assert.equal(
    Object.values(states).every((enabled) => enabled === false),
    true,
  );
});

test('provider credentials alone never enable a capability', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'yingjian-credentials-only-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const runtime = await createGenerationRuntime({
    env: localEvaluationEnvironment(directory, {
      BAIDU_API_KEY: 'test-only-api-key',
      BAIDU_SECRET_KEY: 'test-only-secret-key',
      ALIBABA_DASHSCOPE_API_KEY: 'test-only-dashscope-key',
      VOLC_ACCESS_KEY_ID: 'test-only-access-key',
      VOLC_SECRET_ACCESS_KEY: 'test-only-secret-key',
    }),
    fetchImpl: async () => { throw new Error('network must not be used'); },
  });
  t.after(() => runtime.close());

  const states = await discoverCapabilityStates(runtime);
  assert.equal(
    Object.values(states).every((enabled) => enabled === false),
    true,
  );
});

test('runtime requires provider credentials only for an explicitly enabled provider', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'yingjian-provider-credentials-'));
  t.after(() => rm(directory, { recursive: true, force: true }));

  await assert.rejects(
    createGenerationRuntime({
      env: localEvaluationEnvironment(directory, {
        BAIDU_IMAGE_REPAIR_ENABLED: 'true',
      }),
    }),
    /BAIDU_API_KEY is required/,
  );
  await assert.rejects(
    createGenerationRuntime({
      env: localEvaluationEnvironment(directory, {
        BAIDU_IMAGE_REPAIR_ENABLED: 'true',
        BAIDU_API_KEY: 'test-only-api-key',
      }),
    }),
    /BAIDU_SECRET_KEY is required/,
  );
  await assert.rejects(
    createGenerationRuntime({
      env: localEvaluationEnvironment(directory, {
        ALIBABA_IMAGE_ENABLED: 'true',
      }),
    }),
    /ALIBABA_DASHSCOPE_API_KEY is required/,
  );
  await assert.rejects(
    createGenerationRuntime({
      env: localEvaluationEnvironment(directory, {
        ALIBABA_VIDEO_ENABLED: 'true',
      }),
    }),
    /ALIBABA_DASHSCOPE_API_KEY is required/,
  );
  await assert.rejects(
    createGenerationRuntime({
      env: localEvaluationEnvironment(directory, {
        VOLC_LENS_OPR_ENABLED: 'true',
      }),
    }),
    /VOLC_ACCESS_KEY_ID is required/,
  );
  await assert.rejects(
    createGenerationRuntime({
      env: localEvaluationEnvironment(directory, {
        VOLC_LENS_OPR_ENABLED: 'true',
        VOLC_ACCESS_KEY_ID: 'test-only-access-key',
      }),
    }),
    /VOLC_SECRET_ACCESS_KEY is required/,
  );
});

test('runtime exposes only capabilities for providers explicitly enabled', async (t) => {
  const scenarios = [
    {
      name: 'baidu',
      env: {
        BAIDU_IMAGE_REPAIR_ENABLED: 'true',
        BAIDU_API_KEY: 'test-only-api-key',
        BAIDU_SECRET_KEY: 'test-only-secret-key',
      },
      enabled: ['optimizeAiRepair'],
    },
    {
      name: 'alibaba',
      env: {
        ALIBABA_IMAGE_ENABLED: 'true',
        ALIBABA_DASHSCOPE_API_KEY: 'test-only-dashscope-key',
      },
      enabled: [
        'optimizeOldPhoto',
        'styleAiRedraw',
        'cleanupRemovePasserby',
        'cleanupBrushRemove',
      ],
    },
    {
      name: 'alibaba-video',
      env: {
        ALIBABA_VIDEO_ENABLED: 'true',
        ALIBABA_DASHSCOPE_API_KEY: 'test-only-dashscope-key',
      },
      enabled: ['motionAiNatural'],
    },
    {
      name: 'volcengine',
      env: {
        VOLC_LENS_OPR_ENABLED: 'true',
        VOLC_ACCESS_KEY_ID: 'test-only-access-key',
        VOLC_SECRET_ACCESS_KEY: 'test-only-secret-key',
      },
      enabled: [],
    },
  ];

  for (const scenario of scenarios) {
    await t.test(scenario.name, async (t) => {
      const directory = await mkdtemp(
        join(tmpdir(), `yingjian-${scenario.name}-runtime-`),
      );
      t.after(() => rm(directory, { recursive: true, force: true }));
      const runtime = await createGenerationRuntime({
        env: localEvaluationEnvironment(directory, scenario.env),
        fetchImpl: async () => { throw new Error('network must not be used'); },
      });
      t.after(() => runtime.close());

      const states = await discoverCapabilityStates(runtime);
      const expectedEnabled = new Set(scenario.enabled);
      for (const [capability, enabled] of Object.entries(states)) {
        assert.equal(enabled, expectedEnabled.has(capability), capability);
      }
    });
  }
});

test('loopback evaluation runtime starts only with signed offers and all fixed limits', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'yingjian-local-runtime-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const runtime = await createGenerationRuntime({
    env: localEvaluationEnvironment(directory),
    fetchImpl: async () => { throw new Error('network must not be used'); },
  });
  t.after(() => runtime.close());
  assert.equal(typeof runtime.handler, 'function');
});
