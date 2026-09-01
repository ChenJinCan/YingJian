import { fetchProviderJson } from './bounded-provider-fetch.mjs';
import { ProviderError } from './provider-error.mjs';

export const ALIBABA_IMAGE_TO_VIDEO_MODEL = 'wan2.6-i2v-flash';

const VIDEO_DURATION_SECONDS = 3;
const VIDEO_RESOLUTION = '720P';

const MOTION_RECIPES = Object.freeze({
  motionAiNatural: Object.freeze({
    prompt:
      '保持原始照片的主体身份、构图与场景内容不变，让照片中的原有内容产生自然、轻微、连续的动态；固定相机位置、单段连续画面；不得新增、删除或替换画面元素，不得切镜、旋转或大幅移动。',
    seed: 41010,
  }),
});

export function isAlibabaImageToVideoCapability(capability) {
  return Object.hasOwn(MOTION_RECIPES, capability);
}

export class AlibabaImageToVideoProvider {
  constructor({ apiKey, workspaceId, fetchImpl }) {
    if (typeof apiKey !== 'string' || apiKey.length === 0) {
      throw new TypeError('apiKey is required.');
    }
    if (!/^[A-Za-z0-9-]+$/.test(workspaceId ?? '')) {
      throw new TypeError('workspaceId is required and must be a safe host label.');
    }
    if (typeof fetchImpl !== 'function') {
      throw new TypeError('fetchImpl is required.');
    }
    this.apiKey = apiKey;
    this.baseUrl = `https://${workspaceId}.cn-beijing.maas.aliyuncs.com`;
    this.fetchImpl = fetchImpl;
    this.name = 'alibaba';
    this.cancelPolicy = 'pending-only';
  }

  async submit({ capability, sourceUri }) {
    const recipe = MOTION_RECIPES[capability];
    if (!recipe) {
      throw new ProviderError(
        'Alibaba image-to-video provider received an unsupported capability.',
        { code: 'capability_mismatch', status: 400 },
      );
    }
    if (typeof sourceUri !== 'string' || sourceUri.length === 0) {
      throw new ProviderError('A source image is required.', {
        code: 'source_media_required',
        status: 400,
      });
    }

    const payload = await this.#requestJson(
      '/api/v1/services/aigc/video-generation/video-synthesis',
      {
        method: 'POST',
        headers: this.#headers({ asynchronous: true, json: true }),
        body: JSON.stringify({
          model: ALIBABA_IMAGE_TO_VIDEO_MODEL,
          input: {
            prompt: recipe.prompt,
            img_url: sourceUri,
          },
          parameters: {
            resolution: VIDEO_RESOLUTION,
            duration: VIDEO_DURATION_SECONDS,
            audio: false,
            prompt_extend: false,
            watermark: true,
            seed: recipe.seed,
          },
        }),
      },
      30_000,
    );
    const taskId = payload?.output?.task_id;
    const providerStatus = payload?.output?.task_status;
    if (typeof taskId !== 'string' || typeof providerStatus !== 'string') {
      throw new ProviderError('Alibaba did not return an asynchronous task.', {
        code: String(payload?.code ?? 'provider_invalid_response'),
      });
    }
    return {
      kind: 'accepted',
      provider: 'alibaba',
      model: ALIBABA_IMAGE_TO_VIDEO_MODEL,
      providerTaskId: taskId,
      providerStatus,
      providerRequestId: String(payload.request_id ?? ''),
      providerCancelable: providerStatus === 'PENDING',
    };
  }

  async cancel({ providerTaskId, providerStatus }) {
    if (providerStatus !== 'PENDING') {
      return {
        providerCancelled: false,
        reason: 'provider_not_pending',
      };
    }
    const payload = await this.#requestJson(
      `/api/v1/tasks/${encodeURIComponent(providerTaskId)}/cancel`,
      {
        method: 'POST',
        headers: this.#headers(),
      },
      15_000,
    );
    const status = payload?.output?.task_status;
    return {
      providerCancelled: status === 'CANCELED',
      providerStatus: String(status ?? 'UNKNOWN'),
      providerRequestId: String(payload.request_id ?? ''),
    };
  }

  async observe({ providerTaskId }) {
    const payload = await this.#requestJson(
      `/api/v1/tasks/${encodeURIComponent(providerTaskId)}`,
      {
        method: 'GET',
        headers: this.#headers(),
      },
      15_000,
    );
    const providerStatus = String(payload?.output?.task_status ?? 'UNKNOWN');
    const common = {
      providerStatus,
      providerRequestId: String(payload.request_id ?? ''),
      providerCancelable: providerStatus === 'PENDING',
    };
    if (providerStatus === 'SUCCEEDED') {
      const url = payload?.output?.video_url;
      if (typeof url !== 'string' || url.length === 0) {
        throw new ProviderError('Alibaba task succeeded without a video URL.', {
          code: 'provider_invalid_response',
        });
      }
      return {
        kind: 'succeeded',
        ...common,
        output: {
          kind: 'remote-url',
          url,
          mediaKind: 'image_motion',
          expectedMimeType: 'video/mp4',
          expectedCodec: 'h264',
          expectedDurationMilliseconds: VIDEO_DURATION_SECONDS * 1000,
          expectedResolutionTier: 720,
          providerReportedDurationMilliseconds: Number.isInteger(
            payload?.usage?.output_video_duration,
          )
            ? payload.usage.output_video_duration * 1000
            : null,
          providerReportedResolutionTier: Number.isInteger(payload?.usage?.SR)
            ? payload.usage.SR
            : null,
        },
      };
    }
    if (providerStatus === 'FAILED' || providerStatus === 'UNKNOWN') {
      return {
        kind: 'failed',
        ...common,
        errorCode: String(payload?.output?.code ?? payload?.code ?? 'provider_failed'),
      };
    }
    if (providerStatus === 'CANCELED') {
      return { kind: 'canceled', ...common };
    }
    return { kind: providerStatus === 'RUNNING' ? 'running' : 'pending', ...common };
  }

  #headers({ asynchronous = false, json = false } = {}) {
    return {
      authorization: `Bearer ${this.apiKey}`,
      ...(json ? { 'content-type': 'application/json' } : {}),
      ...(asynchronous ? { 'x-dashscope-async': 'enable' } : {}),
    };
  }

  #requestJson(path, init, timeoutMilliseconds) {
    return fetchProviderJson({
      fetchImpl: this.fetchImpl,
      url: `${this.baseUrl}${path}`,
      init,
      timeoutMilliseconds,
      maxResponseBytes: 1024 * 1024,
    });
  }
}
