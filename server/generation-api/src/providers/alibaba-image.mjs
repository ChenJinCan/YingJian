import { fetchProviderJson } from './bounded-provider-fetch.mjs';
import { ProviderError } from './provider-error.mjs';

const STYLE_SEED = 42001;
const MASK_RECIPES = Object.freeze({
  cleanupRemovePasserby: Object.freeze({
    prompt:
      '移除白色遮罩区域内的人物，并仅依据遮罩周围可见背景自然补全；不要修改遮罩外内容。',
    seed: 43001,
  }),
  cleanupBrushRemove: Object.freeze({
    prompt:
      '移除白色遮罩区域内的内容，并仅依据遮罩周围可见背景自然补全；不要修改遮罩外内容。',
    seed: 43002,
  }),
});

export class AlibabaImageProvider {
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

  async submit(input) {
    const { capability, sourceUri, styleDefinition } = input;
    if (capability in MASK_RECIPES) {
      return this.#submitMaskedEdit(input);
    }
    if (capability !== 'styleAiRedraw') {
      throw new ProviderError(
        'Alibaba image provider received an unsupported capability.',
        {
          code: 'capability_mismatch',
          status: 400,
        },
      );
    }
    if (typeof styleDefinition !== 'string' || styleDefinition.trim().length === 0) {
      throw new ProviderError('A confirmed style definition is required.', {
        code: 'style_definition_required',
        status: 400,
      });
    }
    const body = {
      model: 'wan2.7-image',
      input: {
        messages: [
          {
            role: 'user',
            content: [
              { image: sourceUri },
              { text: styleDefinition },
            ],
          },
        ],
      },
      parameters: {
        enable_sequential: false,
        size: '2K',
        n: 1,
        seed: STYLE_SEED,
        watermark: true,
      },
    };
    return this.#submitAsync(
      '/api/v1/services/aigc/image-generation/generation',
      body,
      'wan2.7-image',
    );
  }

  async #submitMaskedEdit({ capability, sourceUri, maskUri }) {
    if (typeof maskUri !== 'string' || maskUri.length === 0) {
      throw new ProviderError('A user supplied mask is required.', {
        code: 'mask_required',
        status: 400,
      });
    }
    const recipe = MASK_RECIPES[capability];
    return this.#submitAsync(
      '/api/v1/services/aigc/image2image/image-synthesis',
      {
        model: 'wanx2.1-imageedit',
        input: {
          function: 'description_edit_with_mask',
          prompt: recipe.prompt,
          base_image_url: sourceUri,
          mask_image_url: maskUri,
        },
        parameters: {
          n: 1,
          seed: recipe.seed,
          watermark: true,
        },
      },
      'wanx2.1-imageedit',
    );
  }

  async cancel({ providerTaskId, providerStatus }) {
    if (providerStatus !== 'PENDING') {
      return {
        providerCancelled: false,
        reason: 'provider_not_pending',
      };
    }
    const payload = await fetchProviderJson({
      fetchImpl: this.fetchImpl,
      url: `${this.baseUrl}/api/v1/tasks/${encodeURIComponent(providerTaskId)}/cancel`,
      init: {
        method: 'POST',
        headers: {
          authorization: `Bearer ${this.apiKey}`,
          'content-type': 'application/json',
        },
      },
      timeoutMilliseconds: 15_000,
      maxResponseBytes: 1024 * 1024,
    });
    const status = payload?.output?.task_status;
    return {
      providerCancelled: status === 'CANCELED',
      providerStatus: String(status ?? 'UNKNOWN'),
      providerRequestId: String(payload.request_id ?? ''),
    };
  }

  async observe({ providerTaskId }) {
    const payload = await fetchProviderJson({
      fetchImpl: this.fetchImpl,
      url: `${this.baseUrl}/api/v1/tasks/${encodeURIComponent(providerTaskId)}`,
      init: {
        method: 'GET',
        headers: {
          authorization: `Bearer ${this.apiKey}`,
        },
      },
      timeoutMilliseconds: 15_000,
      maxResponseBytes: 1024 * 1024,
    });
    const providerStatus = String(payload?.output?.task_status ?? 'UNKNOWN');
    const common = {
      providerStatus,
      providerRequestId: String(payload.request_id ?? ''),
      providerCancelable: providerStatus === 'PENDING',
    };
    if (providerStatus === 'SUCCEEDED') {
      const url =
        payload?.output?.results?.[0]?.url ??
        payload?.output?.choices
          ?.flatMap((choice) => choice?.message?.content ?? [])
          .find((content) => content?.type === 'image')?.image;
      if (typeof url !== 'string') {
        throw new ProviderError('Alibaba task succeeded without an output URL.', {
          code: 'provider_invalid_response',
        });
      }
      return {
        kind: 'succeeded',
        ...common,
        output: { kind: 'remote-url', url },
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

  async #submitAsync(path, body, model) {
    const payload = await fetchProviderJson({
      fetchImpl: this.fetchImpl,
      url: `${this.baseUrl}${path}`,
      init: {
        method: 'POST',
        headers: {
          authorization: `Bearer ${this.apiKey}`,
          'content-type': 'application/json',
          'x-dashscope-async': 'enable',
        },
        body: JSON.stringify(body),
      },
      timeoutMilliseconds: 30_000,
      maxResponseBytes: 1024 * 1024,
    });
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
      model,
      providerTaskId: taskId,
      providerStatus,
      providerRequestId: String(payload.request_id ?? ''),
      providerCancelable: providerStatus === 'PENDING',
    };
  }
}
