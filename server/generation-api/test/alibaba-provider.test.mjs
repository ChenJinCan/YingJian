import assert from 'node:assert/strict';
import test from 'node:test';

import { AlibabaImageProvider } from '../src/providers/alibaba-image.mjs';

function recordingFetch(responseBody = {
  output: { task_id: 'ali-task-1', task_status: 'PENDING' },
  request_id: 'ali-request-1',
}) {
  const calls = [];
  return {
    calls,
    fetchImpl: async (url, init) => {
      calls.push({ url: String(url), init });
      return Response.json(responseBody);
    },
  };
}

function assertNoAutomaticParameters(body) {
  const serialized = JSON.stringify(body);
  assert.equal(serialized.includes('prompt_extend'), false);
  assert.equal(serialized.includes('auto'), false);
  assert.equal(serialized.includes('fallback'), false);
}

test('AI style redraw uses the fixed wan2.7-image recipe and confirmed style text', async () => {
  const transport = recordingFetch();
  const provider = new AlibabaImageProvider({
    apiKey: 'server-only-key',
    workspaceId: 'workspace-123',
    fetchImpl: transport.fetchImpl,
  });

  const result = await provider.submit({
    capability: 'styleAiRedraw',
    sourceUri: 'data:image/jpeg;base64,c291cmNl',
    styleDefinition: '保留人物身份和构图，转换为克制的日系胶片风格。',
  });

  assert.equal(transport.calls.length, 1);
  const call = transport.calls[0];
  assert.equal(
    call.url,
    'https://workspace-123.cn-beijing.maas.aliyuncs.com/api/v1/services/aigc/image-generation/generation',
  );
  assert.equal(call.init.headers.authorization, 'Bearer server-only-key');
  assert.equal(call.init.headers['x-dashscope-async'], 'enable');
  const body = JSON.parse(call.init.body);
  assert.deepEqual(body, {
    model: 'wan2.7-image',
    input: {
      messages: [
        {
          role: 'user',
          content: [
            { image: 'data:image/jpeg;base64,c291cmNl' },
            { text: '保留人物身份和构图，转换为克制的日系胶片风格。' },
          ],
        },
      ],
    },
    parameters: {
      enable_sequential: false,
      size: '2K',
      n: 1,
      seed: 42001,
      watermark: true,
    },
  });
  assertNoAutomaticParameters(body);
  assert.equal(result.kind, 'accepted');
  assert.equal(result.providerTaskId, 'ali-task-1');
  assert.equal(result.providerStatus, 'PENDING');
  assert.equal(result.providerCancelable, true);
});

test('passerby cleanup edits only the user supplied mask with a fixed prompt', async () => {
  const transport = recordingFetch();
  const provider = new AlibabaImageProvider({
    apiKey: 'server-only-key',
    workspaceId: 'workspace-123',
    fetchImpl: transport.fetchImpl,
  });

  await provider.submit({
    capability: 'cleanupRemovePasserby',
    sourceUri: 'data:image/jpeg;base64,c291cmNl',
    maskUri: 'data:image/png;base64,bWFzaw==',
  });

  const call = transport.calls[0];
  assert.equal(
    call.url,
    'https://workspace-123.cn-beijing.maas.aliyuncs.com/api/v1/services/aigc/image2image/image-synthesis',
  );
  const body = JSON.parse(call.init.body);
  assert.deepEqual(body, {
    model: 'wanx2.1-imageedit',
    input: {
      function: 'description_edit_with_mask',
      prompt:
        '移除白色遮罩区域内的人物，并仅依据遮罩周围可见背景自然补全；不要修改遮罩外内容。',
      base_image_url: 'data:image/jpeg;base64,c291cmNl',
      mask_image_url: 'data:image/png;base64,bWFzaw==',
    },
    parameters: {
      n: 1,
      seed: 43001,
      watermark: true,
    },
  });
  assertNoAutomaticParameters(body);
});

test('brush cleanup has its own fixed recipe and never expands the mask', async () => {
  const transport = recordingFetch();
  const provider = new AlibabaImageProvider({
    apiKey: 'server-only-key',
    workspaceId: 'workspace-123',
    fetchImpl: transport.fetchImpl,
  });

  await provider.submit({
    capability: 'cleanupBrushRemove',
    sourceUri: 'https://private-media.example/source.jpg',
    maskUri: 'https://private-media.example/exact-user-mask.png',
  });

  const body = JSON.parse(transport.calls[0].init.body);
  assert.equal(
    body.input.prompt,
    '移除白色遮罩区域内的内容，并仅依据遮罩周围可见背景自然补全；不要修改遮罩外内容。',
  );
  assert.equal(
    body.input.mask_image_url,
    'https://private-media.example/exact-user-mask.png',
  );
  assert.deepEqual(body.parameters, {
    n: 1,
    seed: 43002,
    watermark: true,
  });
  assertNoAutomaticParameters(body);
});

test('Alibaba sends provider cancellation only while a task is PENDING', async () => {
  const transport = recordingFetch({
    output: { task_id: 'ali-task-1', task_status: 'CANCELED' },
    request_id: 'ali-cancel-request',
  });
  const provider = new AlibabaImageProvider({
    apiKey: 'server-only-key',
    workspaceId: 'workspace-123',
    fetchImpl: transport.fetchImpl,
  });

  const running = await provider.cancel({
    providerTaskId: 'ali-task-1',
    providerStatus: 'RUNNING',
  });
  assert.deepEqual(running, {
    providerCancelled: false,
    reason: 'provider_not_pending',
  });
  assert.equal(transport.calls.length, 0);

  const pending = await provider.cancel({
    providerTaskId: 'ali-task-1',
    providerStatus: 'PENDING',
  });
  assert.equal(transport.calls.length, 1);
  assert.equal(
    transport.calls[0].url,
    'https://workspace-123.cn-beijing.maas.aliyuncs.com/api/v1/tasks/ali-task-1/cancel',
  );
  assert.equal(transport.calls[0].init.method, 'POST');
  assert.deepEqual(pending, {
    providerCancelled: true,
    providerStatus: 'CANCELED',
    providerRequestId: 'ali-cancel-request',
  });
});

test('Alibaba task lookup returns the exact provider result for private import', async () => {
  const transport = recordingFetch({
    output: {
      task_id: 'ali-task-1',
      task_status: 'SUCCEEDED',
      choices: [
        {
          message: {
            content: [
              {
                type: 'image',
                image: 'https://provider.example/temporary-result.png',
              },
            ],
          },
        },
      ],
    },
    request_id: 'ali-query-request',
  });
  const provider = new AlibabaImageProvider({
    apiKey: 'server-only-key',
    workspaceId: 'workspace-123',
    fetchImpl: transport.fetchImpl,
  });

  const result = await provider.observe({ providerTaskId: 'ali-task-1' });

  assert.equal(
    transport.calls[0].url,
    'https://workspace-123.cn-beijing.maas.aliyuncs.com/api/v1/tasks/ali-task-1',
  );
  assert.equal(transport.calls[0].init.method, 'GET');
  assert.deepEqual(result, {
    kind: 'succeeded',
    providerStatus: 'SUCCEEDED',
    providerRequestId: 'ali-query-request',
    providerCancelable: false,
    output: {
      kind: 'remote-url',
      url: 'https://provider.example/temporary-result.png',
    },
  });
});
