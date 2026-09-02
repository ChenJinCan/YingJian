import assert from 'node:assert/strict';
import test from 'node:test';

import { createGenerationHttpHandler as createRawGenerationHttpHandler } from '../src/http/generation-http-handler.mjs';
import { HmacOfferAuthority } from '../src/security/hmac-offer-authority.mjs';

const OFFER_IDS = {
  optimizeAiRepair: 'optimize-ai-repair@1:credit-1',
  optimizeOldPhoto: 'optimize-old-photo@1:credit-1',
  styleAiRedraw: 'style-ai-redraw@1:credit-1',
  cleanupRemovePasserby: 'cleanup-remove-passerby-mask@1:credit-1',
  cleanupBrushRemove: 'cleanup-brush-remove-mask@1:credit-1',
  motionAiNatural: 'motion-ai-natural@1:credit-1',
};

const testOfferAuthority = {
  issue({ capability }) {
    return {
      id: OFFER_IDS[capability],
      creditCost: 1,
      expiresAt: '2026-09-01T03:15:00.000Z',
    };
  },
  verify({ offerId, capability, policyVersion }) {
    if (policyVersion !== 1) {
      const error = new Error('policy_version_unsupported');
      error.code = 'policy_version_unsupported';
      error.status = 409;
      throw error;
    }
    if (offerId !== OFFER_IDS[capability]) {
      const error = new Error('offer_mismatch');
      error.code = 'offer_mismatch';
      error.status = 409;
      throw error;
    }
    return { creditCost: 1, expiresAt: '2026-09-01T03:15:00.000Z' };
  },
};

const allowingUsageGuard = {
  async reserveGeneration() {},
  async settleGeneration() {},
  async releaseGeneration() {},
  async reserveStorage() {},
  async commitStorage() {},
  async releaseStorage() {},
  async expireStorage() {},
};

function createGenerationHttpHandler(options) {
  return createRawGenerationHttpHandler({
    offerAuthority: testOfferAuthority,
    usageGuard: allowingUsageGuard,
    ...options,
  });
}

function validMedia(overrides = {}) {
  return {
    sha256: 'a'.repeat(64),
    providerUri: 'data:image/jpeg;base64,c291cmNl',
    byteLength: 1024,
    width: 1024,
    height: 1024,
    format: 'jpeg',
    isBlackWhite: false,
    ...overrides,
  };
}

function memoryTaskRepository() {
  const byCreation = new Map();
  const byId = new Map();
  return {
    async reserve({ creationKey, fingerprint, task }) {
      const existing = byCreation.get(creationKey);
      if (existing) {
        if (existing.fingerprint !== fingerprint) {
          return { kind: 'conflict', task: existing };
        }
        return { kind: 'existing', task: existing };
      }
      const initial = { ...task, version: 1 };
      byCreation.set(creationKey, initial);
      byId.set(task.id, initial);
      return { kind: 'created', task: initial };
    },
    async compareAndSet({ ownerId, taskId, expectedVersion, task }) {
      const current = byId.get(taskId);
      if (!current || current.ownerId !== ownerId) return { kind: 'missing', task: null };
      if (current.version !== expectedVersion) return { kind: 'conflict', task: current };
      const updated = { ...task, version: expectedVersion + 1 };
      byCreation.set(updated.creationKey, updated);
      byId.set(updated.id, updated);
      return { kind: 'updated', task: updated };
    },
    async get({ ownerId, taskId }) {
      const task = byId.get(taskId);
      return task?.ownerId === ownerId ? task : null;
    },
    async getByCreation({ ownerId, creationKey }) {
      const task = byCreation.get(creationKey);
      return task?.ownerId === ownerId ? task : null;
    },
  };
}

function createRequest(body) {
  return new Request('http://localhost/v1/generation-tasks', {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: 'Bearer user' },
    body: JSON.stringify({
      ...body,
      consent: body.consent
        ? {
            ...body.consent,
            offerId: body.consent.offerId ?? OFFER_IDS[body.capability],
          }
        : body.consent,
    }),
  });
}

test('HTTP task creation requires injected auth, repository, and private media storage', () => {
  assert.throws(
    () => createGenerationHttpHandler({ providers: {} }),
    /authenticator is required/,
  );
  assert.throws(
    () =>
      createGenerationHttpHandler({
        authenticator: async () => ({ ownerId: 'user-1' }),
        providers: {},
      }),
    /taskRepository is required/,
  );
  assert.throws(
    () =>
      createGenerationHttpHandler({
        authenticator: async () => ({ ownerId: 'user-1' }),
        taskRepository: memoryTaskRepository(),
        providers: {},
      }),
    /mediaStore is required/,
  );
  assert.throws(
    () =>
      createRawGenerationHttpHandler({
        authenticator: async () => ({ ownerId: 'user-1' }),
        taskRepository: memoryTaskRepository(),
        mediaStore: { resolveInput() {}, storeProviderOutput() {} },
        providers: {},
        offerAuthority: testOfferAuthority,
      }),
    /usageGuard is required/,
  );
  assert.throws(
    () =>
      createRawGenerationHttpHandler({
        authenticator: async () => ({ ownerId: 'user-1' }),
        taskRepository: memoryTaskRepository(),
        mediaStore: { resolveInput() {}, storeProviderOutput() {} },
        providers: {},
        usageGuard: allowingUsageGuard,
      }),
    /offerAuthority is required/,
  );
});

test('an unauthenticated request is rejected before media or providers are touched', async () => {
  let mediaTouched = false;
  const handler = createGenerationHttpHandler({
    authenticator: async () => null,
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput() {
        mediaTouched = true;
      },
      async storeProviderOutput() {
        mediaTouched = true;
      },
    },
    providers: {},
  });

  const response = await handler(
    createRequest({
      creationId: 'creation-1',
      capability: 'optimizeAiRepair',
      colorMode: null,
      sourceMediaId: 'source-1',
      consent: {
        uploadConfirmed: true,
        costConfirmed: true,
        policyVersion: 1,
      },
    }),
  );

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: { code: 'unauthorized' } });
  assert.equal(mediaTouched, false);
});

test('capability discovery reports the old-photo feature gate without choosing for the user', async () => {
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput() {},
      async storeProviderOutput() {},
    },
    providers: {
      baidu: { cancelPolicy: 'none', submit() {} },
      alibaba: { cancelPolicy: 'pending-only', submit() {} },
      volcengine: { cancelPolicy: 'none', enabled: false, submit() {} },
    },
    now: () => new Date('2026-09-01T03:00:00Z'),
  });

  const response = await handler(
    new Request('http://localhost/v1/generation-capabilities', {
      headers: { authorization: 'Bearer user' },
    }),
  );

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.capabilities.length, 6);
  assert.equal(body.mediaRetentionHours, 24);
  assert.deepEqual(
    body.capabilities.find((item) => item.capability === 'optimizeOldPhoto'),
    {
      capability: 'optimizeOldPhoto',
      enabled: false,
      provider: 'volcengine',
      model: 'lens_opr',
      recipeVersion: 'optimize-old-photo@1',
      providerCancelable: false,
      cancelBoundary: 'not_provider_cancelable',
      offer: {
        id: 'optimize-old-photo@1:credit-1',
        creditCost: 1,
        expiresAt: '2026-09-01T03:15:00.000Z',
      },
    },
  );
  assert.equal(
    body.capabilities.find((item) => item.capability === 'styleAiRedraw').enabled,
    true,
  );
});

test('a disabled provider cannot create a task or fall back to another provider', async () => {
  let mediaTouched = false;
  let usageTouched = false;
  let providerTouched = false;
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput() {
        mediaTouched = true;
      },
      async storeProviderOutput() {
        mediaTouched = true;
      },
    },
    providers: {
      alibaba: {
        cancelPolicy: 'pending-only',
        async submit() {
          providerTouched = true;
        },
      },
    },
    usageGuard: {
      ...allowingUsageGuard,
      async reserveGeneration() {
        usageTouched = true;
      },
    },
  });

  const response = await handler(
    createRequest({
      creationId: 'disabled-baidu',
      capability: 'optimizeAiRepair',
      sourceMediaId: 'source-1',
      consent: {
        uploadConfirmed: true,
        costConfirmed: true,
        policyVersion: 1,
      },
    }),
  );

  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), {
    error: { code: 'capability_not_configured' },
  });
  assert.equal(mediaTouched, false);
  assert.equal(usageTouched, false);
  assert.equal(providerTouched, false);
});

test('task creation enforces the signed offer expiry and exact policy version', async () => {
  let currentTime = new Date('2026-09-01T03:00:00Z');
  const authority = new HmacOfferAuthority({
    signingKey: '0123456789abcdef0123456789abcdef',
    ttlMilliseconds: 1000,
    nonceFactory: () => 'offer-test',
  });
  const handler = createRawGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput() { return validMedia(); },
      async storeProviderOutput() {},
    },
    providers: { baidu: { cancelPolicy: 'none', async submit() {} } },
    offerAuthority: authority,
    usageGuard: allowingUsageGuard,
    now: () => currentTime,
  });
  const catalog = await handler(new Request(
    'http://localhost/v1/generation-capabilities',
    { headers: { authorization: 'Bearer user' } },
  ));
  const offer = (await catalog.json()).capabilities.find(
    (item) => item.capability === 'optimizeAiRepair',
  ).offer;
  currentTime = new Date('2026-09-01T03:00:01Z');
  const expired = await handler(new Request('http://localhost/v1/generation-tasks', {
    method: 'POST',
    headers: { authorization: 'Bearer user', 'content-type': 'application/json' },
    body: JSON.stringify({
      creationId: 'expired-offer',
      capability: 'optimizeAiRepair',
      sourceMediaId: 'source-1',
      consent: {
        offerId: offer.id,
        uploadConfirmed: true,
        costConfirmed: true,
        policyVersion: 1,
      },
    }),
  }));
  assert.equal(expired.status, 409);
  assert.equal((await expired.json()).error.code, 'offer_expired');

  const unsupportedPolicy = await handler(new Request(
    'http://localhost/v1/generation-tasks',
    {
      method: 'POST',
      headers: { authorization: 'Bearer user', 'content-type': 'application/json' },
      body: JSON.stringify({
        creationId: 'wrong-policy',
        capability: 'optimizeAiRepair',
        sourceMediaId: 'source-1',
        consent: {
          offerId: offer.id,
          uploadConfirmed: true,
          costConfirmed: true,
          policyVersion: 999,
        },
      }),
    },
  ));
  assert.equal(unsupportedPolicy.status, 409);
  assert.equal(
    (await unsupportedPolicy.json()).error.code,
    'policy_version_unsupported',
  );
});

test('authenticated private media can be uploaded and downloaded without exposing a provider URL', async () => {
  const stored = new Map();
  const mediaStore = {
    async resolveInput() {},
    async storeProviderOutput() {},
    async putSource({ ownerId, mediaId, mimeType, data }) {
      assert.equal(ownerId, 'user-1');
      stored.set(mediaId, {
        mimeType,
        data: Buffer.from(data),
        mediaKind: 'image',
        width: 2,
        height: 2,
      });
      return { mediaId, sha256: 'd'.repeat(64) };
    },
    async read({ ownerId, mediaId }) {
      assert.equal(ownerId, 'user-1');
      const value = stored.get(mediaId);
      return { ...value, sha256: 'd'.repeat(64) };
    },
  };
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: memoryTaskRepository(),
    mediaStore,
    providers: {},
    mediaIdFactory: () => 'media-1',
  });

  const upload = await handler(
    new Request('http://localhost/v1/private-media', {
      method: 'POST',
      headers: {
        authorization: 'Bearer user',
        'content-type': 'image/png',
      },
      body: Buffer.from('private-image'),
    }),
  );
  assert.equal(upload.status, 201);
  assert.deepEqual(await upload.json(), {
    media: { id: 'media-1', sha256: 'd'.repeat(64) },
  });

  const download = await handler(
    new Request('http://localhost/v1/private-media/media-1', {
      headers: { authorization: 'Bearer user' },
    }),
  );
  assert.equal(download.status, 200);
  assert.equal(download.headers.get('content-type'), 'image/png');
  assert.equal(download.headers.get('x-content-sha256'), 'd'.repeat(64));
  assert.equal(download.headers.get('x-media-kind'), 'image');
  assert.equal(download.headers.get('x-media-width'), '2');
  assert.equal(download.headers.get('x-media-height'), '2');
  assert.equal(Buffer.from(await download.arrayBuffer()).toString(), 'private-image');
});

test('explicit AI repair consent creates one authenticated task and stores the sync result privately', async () => {
  const providerCalls = [];
  const storedOutputs = [];
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput({ ownerId, mediaId }) {
        assert.equal(ownerId, 'user-1');
        assert.equal(mediaId, 'source-1');
        return validMedia();
      },
      async storeProviderOutput(value) {
        storedOutputs.push(value);
        return { mediaId: 'private-result-1', sha256: 'b'.repeat(64) };
      },
    },
    providers: {
      baidu: {
        cancelPolicy: 'none',
        async submit(input) {
          providerCalls.push(input);
          return {
            kind: 'succeeded',
            provider: 'baidu',
            model: 'image_definition_enhance',
            providerRequestId: 'baidu-request-1',
            providerCancelable: false,
            output: {
              kind: 'base64',
              mimeType: 'image/jpeg',
              data: 'repaired-base64',
            },
          };
        },
      },
    },
    idFactory: () => 'task-1',
    now: () => new Date('2026-09-01T03:00:00Z'),
  });

  const response = await handler(
    createRequest({
      creationId: 'creation-1',
      capability: 'optimizeAiRepair',
      sourceMediaId: 'source-1',
      consent: {
        uploadConfirmed: true,
        costConfirmed: true,
        policyVersion: 1,
      },
    }),
  );

  assert.equal(response.status, 201);
  const body = await response.json();
  assert.deepEqual(providerCalls, [
    {
      capability: 'optimizeAiRepair',
      sourceUri: 'data:image/jpeg;base64,c291cmNl',
    },
  ]);
  assert.equal(storedOutputs.length, 1);
  assert.equal(storedOutputs[0].ownerId, 'user-1');
  assert.equal(storedOutputs[0].taskId, 'task-1');
  assert.deepEqual(body, {
    task: {
      id: 'task-1',
      requestId: 'creation-1',
      creationId: 'creation-1',
      capability: 'optimizeAiRepair',
      colorMode: null,
      offerId: 'optimize-ai-repair@1:credit-1',
      sourceMediaId: 'source-1',
      sourceSha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      sourceUploadSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      maskSha256: null,
      maskUploadSha256: null,
      inputIdentity: null,
      recipeVersion: 'optimize-ai-repair@1',
      provider: 'baidu',
      model: 'image_definition_enhance',
      state: 'succeeded',
      providerStatus: 'SUCCEEDED',
      providerCancelable: false,
      providerCancellation: 'not_available',
      usageState: 'settled',
      usageDisposition: 'settle',
      resultMediaId: 'private-result-1',
      errorCode: null,
      createdAt: '2026-09-01T03:00:00.000Z',
      updatedAt: '2026-09-01T03:00:00.000Z',
    },
  });
});

test('GET observes an Alibaba task once and imports a succeeded result into private media', async () => {
  const repository = memoryTaskRepository();
  const storedOutputs = [];
  const provider = {
    cancelPolicy: 'pending-only',
    async submit() {
      return {
        kind: 'accepted',
        provider: 'alibaba',
        model: 'wan2.7-image',
        providerTaskId: 'ali-task-1',
        providerStatus: 'PENDING',
        providerRequestId: 'ali-create-1',
        providerCancelable: true,
      };
    },
    async observe(input) {
      assert.deepEqual(input, { providerTaskId: 'ali-task-1' });
      return {
        kind: 'succeeded',
        providerStatus: 'SUCCEEDED',
        providerRequestId: 'ali-query-1',
        providerCancelable: false,
        output: {
          kind: 'remote-url',
          url: 'https://provider.example/temporary-result.png',
        },
      };
    },
  };
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: repository,
    mediaStore: {
      async resolveInput() {
        return validMedia();
      },
      async storeProviderOutput(value) {
        storedOutputs.push(value);
        return { mediaId: 'private-result-2', sha256: 'b'.repeat(64) };
      },
    },
    providers: { alibaba: provider },
    idFactory: () => 'task-1',
    now: () => new Date('2026-09-01T03:00:00Z'),
  });
  const created = await handler(
    createRequest({
      creationId: 'creation-2',
      capability: 'styleAiRedraw',
      sourceMediaId: 'source-1',
      styleDefinition: '用户确认的电影感风格定义',
      styleDefinitionConfirmed: true,
      consent: {
        uploadConfirmed: true,
        costConfirmed: true,
        policyVersion: 1,
      },
    }),
  );
  assert.equal(created.status, 201);

  const observed = await handler(
    new Request('http://localhost/v1/generation-tasks/task-1', {
      headers: { authorization: 'Bearer user' },
    }),
  );

  assert.equal(observed.status, 200);
  const body = await observed.json();
  assert.equal(body.task.state, 'succeeded');
  assert.equal(body.task.resultMediaId, 'private-result-2');
  assert.equal(body.task.providerCancelable, false);
  assert.equal(storedOutputs.length, 1);
  assert.equal(storedOutputs[0].ownerId, 'user-1');
  assert.equal(storedOutputs[0].taskId, 'task-1');
});

test('a RUNNING Alibaba task stays running and never claims local cancellation', async () => {
  let providerCancelCalls = 0;
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput() {
        return validMedia();
      },
      async storeProviderOutput() {
        throw new Error('not expected');
      },
    },
    providers: {
      alibaba: {
        cancelPolicy: 'pending-only',
        async submit() {
          return {
            kind: 'accepted',
            provider: 'alibaba',
            model: 'wan2.7-image',
            providerTaskId: 'ali-running-1',
            providerStatus: 'RUNNING',
            providerRequestId: 'ali-create-1',
            providerCancelable: false,
          };
        },
        async cancel() {
          providerCancelCalls += 1;
          return { providerCancelled: true, providerStatus: 'CANCELED' };
        },
      },
    },
    idFactory: () => 'task-running',
    now: () => new Date('2026-09-01T03:00:00Z'),
  });
  await handler(
    createRequest({
      creationId: 'creation-running',
      capability: 'styleAiRedraw',
      sourceMediaId: 'source-1',
      styleDefinition: '用户确认的风格',
      styleDefinitionConfirmed: true,
      consent: {
        uploadConfirmed: true,
        costConfirmed: true,
        policyVersion: 1,
      },
    }),
  );

  const response = await handler(
    new Request('http://localhost/v1/generation-tasks/task-running/cancel', {
      method: 'POST',
      headers: { authorization: 'Bearer user' },
    }),
  );

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.task.state, 'running');
  assert.equal(body.task.providerStatus, 'RUNNING');
  assert.equal(body.task.providerCancelable, false);
  assert.equal(body.task.providerCancellation, 'not_available');
  assert.equal(providerCancelCalls, 0);
});

test('a stale PENDING cancel response that reports RUNNING preserves the real task and held usage', async () => {
  const usageEvents = [];
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput() { return validMedia(); },
      async storeProviderOutput() { throw new Error('not expected'); },
    },
    usageGuard: {
      ...allowingUsageGuard,
      async reserveGeneration() { usageEvents.push('reserve'); },
      async releaseGeneration() { usageEvents.push('release'); },
    },
    providers: {
      alibaba: {
        cancelPolicy: 'pending-only',
        async submit() {
          return {
            kind: 'accepted',
            providerTaskId: 'ali-stale-pending',
            providerStatus: 'PENDING',
            providerRequestId: 'ali-create-stale',
            providerCancelable: true,
          };
        },
        async cancel() {
          return {
            providerCancelled: false,
            providerStatus: 'RUNNING',
            providerRequestId: 'ali-cancel-race',
          };
        },
      },
    },
    idFactory: () => 'task-stale-pending',
  });
  await handler(createRequest({
    creationId: 'creation-stale-pending',
    capability: 'styleAiRedraw',
    sourceMediaId: 'source-1',
    styleDefinition: '确认风格',
    styleDefinitionConfirmed: true,
    consent: { uploadConfirmed: true, costConfirmed: true, policyVersion: 1 },
  }));
  const response = await handler(new Request(
    'http://localhost/v1/generation-tasks/task-stale-pending/cancel',
    { method: 'POST', headers: { authorization: 'Bearer user' } },
  ));
  assert.equal(response.status, 200);
  const task = (await response.json()).task;
  assert.equal(task.state, 'running');
  assert.equal(task.providerStatus, 'RUNNING');
  assert.equal(task.providerCancelable, false);
  assert.equal(task.providerCancellation, 'not_available');
  assert.deepEqual(usageEvents, ['reserve']);
});

test('same creation is idempotent, while changing its source is a conflict', async () => {
  let providerCalls = 0;
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput({ mediaId }) {
        return validMedia({
          sha256: mediaId === 'source-1' ? 'a'.repeat(64) : 'c'.repeat(64),
          providerUri: `https://private-media.example/${mediaId}.jpg`,
        });
      },
      async storeProviderOutput() {
        throw new Error('not expected');
      },
    },
    providers: {
      alibaba: {
        cancelPolicy: 'pending-only',
        async submit() {
          providerCalls += 1;
          return {
            kind: 'accepted',
            provider: 'alibaba',
            model: 'wan2.7-image',
            providerTaskId: 'ali-task-1',
            providerStatus: 'PENDING',
            providerRequestId: 'ali-request-1',
            providerCancelable: true,
          };
        },
      },
    },
    idFactory: () => 'task-idempotent',
    now: () => new Date('2026-09-01T03:00:00Z'),
  });
  const requestBody = {
    creationId: 'creation-idempotent',
    capability: 'styleAiRedraw',
    sourceMediaId: 'source-1',
    styleDefinition: '用户确认的风格',
    styleDefinitionConfirmed: true,
    consent: {
      uploadConfirmed: true,
      costConfirmed: true,
      policyVersion: 1,
    },
  };

  assert.equal((await handler(createRequest(requestBody))).status, 201);
  assert.equal((await handler(createRequest(requestBody))).status, 200);
  assert.equal(providerCalls, 1);

  const conflict = await handler(
    createRequest({ ...requestBody, sourceMediaId: 'source-2' }),
  );
  assert.equal(conflict.status, 409);
  assert.deepEqual(await conflict.json(), {
    error: { code: 'idempotency_conflict' },
  });
  assert.equal(providerCalls, 1);
});

test('old-photo color mode is explicit and part of idempotency identity', async () => {
  const providerCalls = [];
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput() {
        return validMedia();
      },
      async storeProviderOutput() {
        return { mediaId: 'old-photo-result', sha256: 'b'.repeat(64) };
      },
    },
    providers: {
      volcengine: {
        enabled: true,
        cancelPolicy: 'none',
        async submit(input) {
          providerCalls.push(input);
          return {
            kind: 'succeeded',
            provider: 'volcengine',
            model: 'lens_opr',
            providerRequestId: 'volc-request',
            providerCancelable: false,
            output: {
              kind: 'base64',
              mimeType: 'image/jpeg',
              data: 'cmVzdWx0',
            },
          };
        },
      },
    },
    idFactory: () => 'old-photo-task',
    now: () => new Date('2026-09-01T03:00:00Z'),
  });
  const base = {
    creationId: 'old-photo-creation',
    capability: 'optimizeOldPhoto',
    sourceMediaId: 'source-1',
    consent: {
      uploadConfirmed: true,
      costConfirmed: true,
      policyVersion: 1,
    },
  };

  assert.equal((await handler(createRequest({ ...base, colorMode: 'preserve' }))).status, 201);
  assert.deepEqual(providerCalls, [
    {
      capability: 'optimizeOldPhoto',
      sourceUri: 'data:image/jpeg;base64,c291cmNl',
      colorMode: 'preserve',
    },
  ]);
  assert.equal((await handler(createRequest({ ...base, colorMode: 'preserve' }))).status, 200);
  assert.equal(
    (await handler(createRequest({ ...base, colorMode: 'colorize' }))).status,
    409,
  );
  assert.equal(providerCalls.length, 1);

  const missing = await handler(
    createRequest({ ...base, creationId: 'old-photo-missing-color' }),
  );
  assert.equal(missing.status, 400);
  assert.deepEqual(await missing.json(), { error: { code: 'color_mode_required' } });
});

test('usage is reserved before a paid provider call and an idempotent replay does not reserve twice', async () => {
  const events = [];
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput() { return validMedia(); },
      async storeProviderOutput() { return { mediaId: 'result-guarded' }; },
    },
    usageGuard: {
      ...allowingUsageGuard,
      async reserveGeneration() { events.push('reserve'); },
      async settleGeneration() { events.push('settle'); },
    },
    providers: {
      baidu: {
        cancelPolicy: 'none',
        async submit() {
          events.push('submit');
          return {
            kind: 'succeeded',
            providerRequestId: 'request-guarded',
            providerCancelable: false,
            output: { kind: 'base64', mimeType: 'image/png', data: 'eA==' },
          };
        },
      },
    },
    idFactory: () => 'task-guarded',
    dispatchIdFactory: () => 'dispatch-guarded',
  });
  const body = {
    creationId: 'creation-guarded',
    capability: 'optimizeAiRepair',
    sourceMediaId: 'source-1',
    consent: { uploadConfirmed: true, costConfirmed: true, policyVersion: 1 },
  };

  assert.equal((await handler(createRequest(body))).status, 201);
  assert.equal((await handler(createRequest(body))).status, 200);
  assert.deepEqual(events, ['reserve', 'submit', 'settle']);
});

test('a synchronous provider success is settled even when private result import fails', async () => {
  const events = [];
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput() { return validMedia(); },
      async storeProviderOutput() { throw new Error('storage failed'); },
    },
    usageGuard: {
      ...allowingUsageGuard,
      async reserveGeneration() { events.push('reserve'); },
      async settleGeneration() { events.push('settle'); },
      async releaseGeneration() { events.push('release'); },
    },
    providers: {
      baidu: {
        cancelPolicy: 'none',
        async submit() {
          events.push('submit');
          return {
            kind: 'succeeded',
            providerRequestId: 'paid-success',
            providerCancelable: false,
            output: { kind: 'base64', mimeType: 'image/png', data: 'eA==' },
          };
        },
      },
    },
    idFactory: () => 'task-result-failed',
  });
  const response = await handler(createRequest({
    creationId: 'creation-result-failed',
    capability: 'optimizeAiRepair',
    sourceMediaId: 'source-1',
    consent: { uploadConfirmed: true, costConfirmed: true, policyVersion: 1 },
  }));
  assert.equal(response.status, 502);
  assert.equal((await response.json()).error.code, 'result_import_failed');
  assert.deepEqual(events, ['reserve', 'submit', 'settle']);
});

test('a durable dispatch intent prevents a second submit after post-submit persistence failure', async () => {
  const repository = memoryTaskRepository();
  const compareAndSet = repository.compareAndSet;
  let casCalls = 0;
  let failOnce = true;
  repository.compareAndSet = async (input) => {
    casCalls += 1;
    if (failOnce && casCalls === 2) {
      failOnce = false;
      throw new Error('simulated persistence crash window');
    }
    return compareAndSet(input);
  };
  let submits = 0;
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: repository,
    mediaStore: {
      async resolveInput() { return validMedia(); },
      async storeProviderOutput() { throw new Error('not expected'); },
    },
    providers: {
      alibaba: {
        cancelPolicy: 'pending-only',
        async submit() {
          submits += 1;
          return {
            kind: 'accepted',
            providerTaskId: 'accepted-but-not-recorded',
            providerRequestId: 'provider-request',
            providerStatus: 'PENDING',
            providerCancelable: true,
          };
        },
      },
    },
    idFactory: () => 'task-dispatch',
    dispatchIdFactory: () => 'dispatch-attempt-1',
  });
  const body = {
    creationId: 'creation-dispatch',
    capability: 'styleAiRedraw',
    sourceMediaId: 'source-1',
    styleDefinition: '用户确认的风格',
    styleDefinitionConfirmed: true,
    consent: { uploadConfirmed: true, costConfirmed: true, policyVersion: 1 },
  };

  assert.equal((await handler(createRequest(body))).status, 502);
  const replay = await handler(createRequest(body));
  assert.equal(replay.status, 200);
  assert.equal((await replay.json()).task.errorCode, 'dispatch_reconciliation_required');
  const reconciliation = await handler(
    new Request(
      'http://localhost/v1/generation-tasks/by-creation/creation-dispatch' +
        '?capability=styleAiRedraw',
      { headers: { authorization: 'Bearer user' } },
    ),
  );
  assert.equal(reconciliation.status, 200);
  assert.equal(
    (await reconciliation.json()).task.errorCode,
    'dispatch_reconciliation_required',
  );
  assert.equal(submits, 1);
});

test('an expired unknown dispatch stops locking the client while its credit remains held', async () => {
  let currentTime = new Date('2026-09-01T03:00:00.000Z');
  let submits = 0;
  const usageEvents = [];
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput() { return validMedia(); },
      async storeProviderOutput() { throw new Error('not expected'); },
    },
    usageGuard: {
      ...allowingUsageGuard,
      async reserveGeneration() { usageEvents.push('reserve'); },
      async settleGeneration() { usageEvents.push('settle'); },
      async releaseGeneration() { usageEvents.push('release'); },
    },
    providers: {
      alibaba: {
        cancelPolicy: 'pending-only',
        async submit() {
          submits += 1;
          throw new Error('provider outcome is unknown');
        },
      },
    },
    idFactory: () => 'task-unknown-outcome',
    dispatchIdFactory: () => 'dispatch-unknown-outcome',
    dispatchReconciliationWindowMilliseconds: 1_000,
    now: () => currentTime,
  });
  const body = {
    creationId: 'creation-unknown-outcome',
    capability: 'styleAiRedraw',
    sourceMediaId: 'source-1',
    styleDefinition: '用户确认的风格',
    styleDefinitionConfirmed: true,
    consent: { uploadConfirmed: true, costConfirmed: true, policyVersion: 1 },
  };

  const failed = await handler(createRequest(body));
  assert.equal(failed.status, 502);
  assert.equal(
    (await failed.json()).error.code,
    'dispatch_reconciliation_required',
  );

  currentTime = new Date('2026-09-01T03:00:01.001Z');
  const reconciliation = await handler(
    new Request(
      'http://localhost/v1/generation-tasks/by-creation/' +
        'creation-unknown-outcome?capability=styleAiRedraw',
      { headers: { authorization: 'Bearer user' } },
    ),
  );
  assert.equal(reconciliation.status, 200);
  const reconciledTask = (await reconciliation.json()).task;
  assert.equal(reconciledTask.errorCode, 'provider_outcome_unknown');
  assert.equal(reconciledTask.usageState, 'reserved');
  assert.equal(reconciledTask.usageDisposition, 'hold');

  const replay = await handler(createRequest(body));
  assert.equal(replay.status, 200);
  assert.equal((await replay.json()).task.errorCode, 'provider_outcome_unknown');
  assert.equal(submits, 1);
  assert.deepEqual(usageEvents, ['reserve']);
});

test('creation reconciliation cannot read another owner task', async () => {
  const handler = createGenerationHttpHandler({
    authenticator: async (request) => ({
      ownerId:
        request.headers.get('authorization') === 'Bearer other'
          ? 'user-2'
          : 'user-1',
    }),
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput() { return validMedia(); },
      async storeProviderOutput() { throw new Error('not expected'); },
    },
    providers: {
      alibaba: {
        cancelPolicy: 'pending-only',
        async submit() {
          return {
            kind: 'accepted',
            providerTaskId: 'owner-scoped-task',
            providerRequestId: 'owner-scoped-request',
            providerStatus: 'PENDING',
            providerCancelable: true,
          };
        },
      },
    },
    idFactory: () => 'task-owner-scoped',
  });
  const creationId = 'creation-owner-scoped';
  const created = await handler(createRequest({
    creationId,
    capability: 'styleAiRedraw',
    sourceMediaId: 'source-1',
    styleDefinition: '用户确认的风格',
    styleDefinitionConfirmed: true,
    consent: { uploadConfirmed: true, costConfirmed: true, policyVersion: 1 },
  }));
  assert.equal(created.status, 201);

  const response = await handler(
    new Request(
      `http://localhost/v1/generation-tasks/by-creation/${creationId}` +
        '?capability=styleAiRedraw',
      { headers: { authorization: 'Bearer other' } },
    ),
  );
  assert.equal(response.status, 404);
  assert.equal((await response.json()).error.code, 'task_not_found');
});

test('a live dispatch lease lets a concurrent idempotent request observe without corrupting the task', async () => {
  let markSubmitStarted;
  let finishSubmit;
  const submitStarted = new Promise((resolve) => { markSubmitStarted = resolve; });
  const submitGate = new Promise((resolve) => { finishSubmit = resolve; });
  let submits = 0;
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput() { return validMedia(); },
      async storeProviderOutput() { throw new Error('not expected'); },
    },
    providers: {
      alibaba: {
        cancelPolicy: 'pending-only',
        async submit() {
          submits += 1;
          markSubmitStarted();
          await submitGate;
          return {
            kind: 'accepted',
            providerTaskId: 'ali-live-dispatch',
            providerRequestId: 'ali-live-request',
            providerStatus: 'PENDING',
            providerCancelable: true,
          };
        },
      },
    },
    idFactory: () => 'task-live-dispatch',
    dispatchIdFactory: () => 'dispatch-live',
    now: () => new Date('2026-09-01T03:00:00Z'),
  });
  const requestBody = {
    creationId: 'creation-live-dispatch',
    capability: 'styleAiRedraw',
    sourceMediaId: 'source-1',
    styleDefinition: '确认风格',
    styleDefinitionConfirmed: true,
    consent: { uploadConfirmed: true, costConfirmed: true, policyVersion: 1 },
  };
  const first = handler(createRequest(requestBody));
  await submitStarted;
  const replay = await handler(createRequest(requestBody));
  assert.equal(replay.status, 200);
  assert.notEqual((await replay.json()).task.errorCode, 'dispatch_reconciliation_required');
  finishSubmit();
  assert.equal((await first).status, 201);
  assert.equal(submits, 1);
});

test('a usage rejection is persisted as terminal before any provider dispatch', async () => {
  let submits = 0;
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput() { return validMedia(); },
      async storeProviderOutput() { throw new Error('not expected'); },
    },
    usageGuard: {
      ...allowingUsageGuard,
      async reserveGeneration() {
        const error = new Error('generation_concurrency_exceeded');
        error.code = 'generation_concurrency_exceeded';
        error.status = 429;
        throw error;
      },
    },
    providers: {
      alibabaMotion: {
        cancelPolicy: 'pending-only',
        async submit() {
          submits += 1;
          throw new Error('must not dispatch');
        },
      },
    },
    idFactory: () => 'task-concurrency-rejected',
  });
  const body = {
    creationId: 'creation-concurrency-rejected',
    capability: 'motionAiNatural',
    sourceMediaId: 'source-1',
    consent: { uploadConfirmed: true, costConfirmed: true, policyVersion: 1 },
  };

  const created = await handler(createRequest(body));
  assert.equal(created.status, 429);
  assert.equal((await created.json()).error.code, 'generation_concurrency_exceeded');

  const reconciliation = await handler(
    new Request(
      'http://localhost/v1/generation-tasks/by-creation/' +
        'creation-concurrency-rejected?capability=motionAiNatural',
      { headers: { authorization: 'Bearer user' } },
    ),
  );
  assert.equal(reconciliation.status, 200);
  const task = (await reconciliation.json()).task;
  assert.equal(task.state, 'rejected');
  assert.equal(task.errorCode, 'generation_concurrency_exceeded');
  assert.equal(task.usageState, 'unreserved');
  assert.equal(task.usageDisposition, 'release');
  assert.equal(submits, 0);
});

test('private upload reserves owner storage before persistence and commits after success', async () => {
  const events = [];
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput() {},
      async storeProviderOutput() {},
      async putSource() {
        events.push('persist');
        return { mediaId: 'media-quota', sha256: 'd'.repeat(64) };
      },
    },
    usageGuard: {
      ...allowingUsageGuard,
      async reserveStorage() { events.push('reserve-storage'); },
      async commitStorage() { events.push('commit-storage'); },
    },
    providers: {},
    mediaIdFactory: () => 'media-quota',
  });
  const response = await handler(new Request('http://localhost/v1/private-media', {
    method: 'POST',
    headers: { authorization: 'Bearer user', 'content-type': 'image/png' },
    body: Buffer.from('test-image-bytes'),
  }));
  assert.equal(response.status, 201);
  assert.deepEqual(events, ['reserve-storage', 'persist', 'commit-storage']);
});

test('cleanup rejects a non-binary or wrong-sized mask before reserving or calling Alibaba', async () => {
  let reserves = 0;
  let submits = 0;
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: memoryTaskRepository(),
    mediaStore: {
      async resolveInput({ mediaId }) {
        return mediaId === 'source-1'
          ? validMedia({ format: 'png', width: 1024, height: 1024 })
          : validMedia({ format: 'png', width: 1023, height: 1024, isBlackWhite: false });
      },
      async storeProviderOutput() {},
    },
    usageGuard: {
      ...allowingUsageGuard,
      async reserveGeneration() { reserves += 1; },
    },
    providers: {
      alibaba: { cancelPolicy: 'pending-only', async submit() { submits += 1; } },
    },
  });
  const response = await handler(createRequest({
    creationId: 'creation-mask-invalid',
    capability: 'cleanupBrushRemove',
    sourceMediaId: 'source-1',
    maskMediaId: 'mask-1',
    consent: { uploadConfirmed: true, costConfirmed: true, policyVersion: 1 },
  }));
  assert.equal(response.status, 422);
  assert.equal((await response.json()).error.code, 'mask_dimensions_mismatch');
  assert.equal(reserves, 0);
  assert.equal(submits, 0);
});

test('observe and cancel use CAS so a stale cancellation cannot overwrite result import', async () => {
  const repository = memoryTaskRepository();
  let releaseObserve;
  let releaseCancel;
  let markImportStarted;
  let finishImport;
  const observeGate = new Promise((resolve) => { releaseObserve = resolve; });
  const cancelGate = new Promise((resolve) => { releaseCancel = resolve; });
  const importStarted = new Promise((resolve) => { markImportStarted = resolve; });
  const importGate = new Promise((resolve) => { finishImport = resolve; });
  const provider = {
    cancelPolicy: 'pending-only',
    async submit() {
      return {
        kind: 'accepted',
        providerTaskId: 'ali-cas',
        providerRequestId: 'ali-create-cas',
        providerStatus: 'PENDING',
        providerCancelable: true,
      };
    },
    async observe() {
      await observeGate;
      return {
        kind: 'succeeded',
        providerStatus: 'SUCCEEDED',
        providerRequestId: 'ali-observe-cas',
        providerCancelable: false,
        output: { kind: 'remote-url', url: 'https://allowed.invalid/result.png' },
      };
    },
    async cancel() {
      await cancelGate;
      return { providerCancelled: true, providerStatus: 'CANCELED' };
    },
  };
  const handler = createGenerationHttpHandler({
    authenticator: async () => ({ ownerId: 'user-1' }),
    taskRepository: repository,
    mediaStore: {
      async resolveInput() { return validMedia(); },
      async storeProviderOutput() {
        markImportStarted();
        await importGate;
        return { mediaId: 'cas-result' };
      },
    },
    providers: { alibaba: provider },
    idFactory: () => 'task-cas-race',
    dispatchIdFactory: () => 'dispatch-cas-race',
  });
  await handler(createRequest({
    creationId: 'creation-cas-race',
    capability: 'styleAiRedraw',
    sourceMediaId: 'source-1',
    styleDefinition: '确认风格',
    styleDefinitionConfirmed: true,
    consent: { uploadConfirmed: true, costConfirmed: true, policyVersion: 1 },
  }));

  const observing = handler(new Request(
    'http://localhost/v1/generation-tasks/task-cas-race',
    { headers: { authorization: 'Bearer user' } },
  ));
  const canceling = handler(new Request(
    'http://localhost/v1/generation-tasks/task-cas-race/cancel',
    { method: 'POST', headers: { authorization: 'Bearer user' } },
  ));
  releaseObserve();
  await importStarted;
  releaseCancel();
  const canceled = await canceling;
  assert.notEqual((await canceled.json()).task.state, 'canceled');
  finishImport();
  assert.equal((await (await observing).json()).task.state, 'succeeded');

  const final = await handler(new Request(
    'http://localhost/v1/generation-tasks/task-cas-race',
    { headers: { authorization: 'Bearer user' } },
  ));
  assert.equal((await final.json()).task.state, 'succeeded');
});
