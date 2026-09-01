import assert from 'node:assert/strict';
import test from 'node:test';

import {
  ALIBABA_IMAGE_TO_VIDEO_MODEL,
  AlibabaImageToVideoProvider,
  isAlibabaImageToVideoCapability,
} from '../src/providers/alibaba-image-to-video.mjs';

function recordingFetch(responseBody = {
  output: { task_id: 'ali-video-task-1', task_status: 'PENDING' },
  request_id: 'ali-video-request-1',
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

function providerWith(transport) {
  return new AlibabaImageToVideoProvider({
    apiKey: 'server-only-key',
    workspaceId: 'workspace-123',
    fetchImpl: transport.fetchImpl,
  });
}

const expectedRecipes = Object.freeze({
  motionAiNatural: Object.freeze({
    seed: 41010,
    prompt:
      '保持原始照片的主体身份、构图与场景内容不变，让照片中的原有内容产生自然、轻微、连续的动态；固定相机位置、单段连续画面；不得新增、删除或替换画面元素，不得切镜、旋转或大幅移动。',
  }),
});

for (const [capability, recipe] of Object.entries(expectedRecipes)) {
  test(`${capability} submits only its fixed silent 720P recipe`, async () => {
    const transport = recordingFetch();
    const provider = providerWith(transport);

    const result = await provider.submit({
      capability,
      sourceUri: 'data:image/jpeg;base64,c291cmNl',
    });

    assert.equal(transport.calls.length, 1);
    const call = transport.calls[0];
    assert.equal(
      call.url,
      'https://workspace-123.cn-beijing.maas.aliyuncs.com/api/v1/services/aigc/video-generation/video-synthesis',
    );
    assert.equal(call.init.headers.authorization, 'Bearer server-only-key');
    assert.equal(call.init.headers['x-dashscope-async'], 'enable');
    assert.deepEqual(JSON.parse(call.init.body), {
      model: 'wan2.6-i2v-flash',
      input: {
        prompt: recipe.prompt,
        img_url: 'data:image/jpeg;base64,c291cmNl',
      },
      parameters: {
        resolution: '720P',
        duration: 3,
        audio: false,
        prompt_extend: false,
        watermark: true,
        seed: recipe.seed,
      },
    });
    assert.equal(result.model, ALIBABA_IMAGE_TO_VIDEO_MODEL);
    assert.equal(result.providerTaskId, 'ali-video-task-1');
    assert.equal(result.providerCancelable, true);
  });
}

test('the motion provider rejects unrelated capabilities without a request', async () => {
  const transport = recordingFetch();
  const provider = providerWith(transport);

  await assert.rejects(
    provider.submit({
      capability: 'styleAiRedraw',
      sourceUri: 'data:image/jpeg;base64,c291cmNl',
    }),
    (error) => error.code === 'capability_mismatch',
  );
  assert.equal(transport.calls.length, 0);
  assert.equal(isAlibabaImageToVideoCapability('motionAiNatural'), true);
  assert.equal(isAlibabaImageToVideoCapability('motionSubtle'), false);
  assert.equal(isAlibabaImageToVideoCapability('styleAiRedraw'), false);
});

test('the motion provider reads the provider video URL without exposing the API key', async () => {
  const transport = recordingFetch({
    output: {
      task_id: 'ali-video-task-1',
      task_status: 'SUCCEEDED',
      video_url:
        'https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/result.mp4?Expires=1',
    },
    usage: {
      output_video_duration: 3,
      video_count: 1,
      SR: 720,
    },
    request_id: 'ali-video-query-1',
  });
  const provider = providerWith(transport);

  const result = await provider.observe({ providerTaskId: 'ali-video-task-1' });

  assert.equal(
    transport.calls[0].url,
    'https://workspace-123.cn-beijing.maas.aliyuncs.com/api/v1/tasks/ali-video-task-1',
  );
  assert.deepEqual(result, {
    kind: 'succeeded',
    providerStatus: 'SUCCEEDED',
    providerRequestId: 'ali-video-query-1',
    providerCancelable: false,
    output: {
      kind: 'remote-url',
      url:
        'https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/result.mp4?Expires=1',
      mediaKind: 'image_motion',
      expectedMimeType: 'video/mp4',
      expectedCodec: 'h264',
      expectedDurationMilliseconds: 3000,
      expectedResolutionTier: 720,
      providerReportedDurationMilliseconds: 3000,
      providerReportedResolutionTier: 720,
    },
  });
  assert.equal(JSON.stringify(result).includes('server-only-key'), false);
});

test('the motion provider cancels only PENDING tasks', async () => {
  const transport = recordingFetch({
    output: { task_id: 'ali-video-task-1', task_status: 'CANCELED' },
    request_id: 'ali-video-cancel-1',
  });
  const provider = providerWith(transport);

  assert.deepEqual(
    await provider.cancel({
      providerTaskId: 'ali-video-task-1',
      providerStatus: 'RUNNING',
    }),
    { providerCancelled: false, reason: 'provider_not_pending' },
  );
  assert.equal(transport.calls.length, 0);

  const result = await provider.cancel({
    providerTaskId: 'ali-video-task-1',
    providerStatus: 'PENDING',
  });
  assert.equal(transport.calls.length, 1);
  assert.equal(result.providerCancelled, true);
  assert.equal(result.providerStatus, 'CANCELED');
});
