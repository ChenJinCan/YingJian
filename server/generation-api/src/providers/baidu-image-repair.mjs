import { fetchProviderJson } from './bounded-provider-fetch.mjs';
import { ProviderError } from './provider-error.mjs';

const ENDPOINT =
  'https://aip.baidubce.com/rest/2.0/image-process/v1/image_definition_enhance';
const TOKEN_ENDPOINT = 'https://aip.baidubce.com/oauth/2.0/token';

export function createBaiduAccessTokenProvider({
  apiKey,
  secretKey,
  fetchImpl,
  now = () => new Date(),
}) {
  if (typeof apiKey !== 'string' || apiKey.length === 0) {
    throw new TypeError('apiKey is required.');
  }
  if (typeof secretKey !== 'string' || secretKey.length === 0) {
    throw new TypeError('secretKey is required.');
  }
  if (typeof fetchImpl !== 'function') {
    throw new TypeError('fetchImpl is required.');
  }
  let cachedToken = null;
  let expiresAt = 0;
  return async function getBaiduAccessToken() {
    if (cachedToken && now().getTime() < expiresAt) {
      return cachedToken;
    }
    const url = new URL(TOKEN_ENDPOINT);
    url.searchParams.set('grant_type', 'client_credentials');
    url.searchParams.set('client_id', apiKey);
    url.searchParams.set('client_secret', secretKey);
    const payload = await fetchProviderJson({
      fetchImpl,
      url,
      init: { method: 'POST' },
      timeoutMilliseconds: 5000,
      maxResponseBytes: 64 * 1024,
    });
    if (typeof payload.access_token !== 'string') {
      throw new ProviderError('Baidu OAuth did not return an access token.', {
        code: String(payload.error ?? 'provider_auth_failed'),
      });
    }
    cachedToken = payload.access_token;
    const lifetimeSeconds = Math.max(0, Number(payload.expires_in) || 0);
    expiresAt = now().getTime() + Math.max(0, lifetimeSeconds - 60) * 1000;
    return cachedToken;
  };
}

export class BaiduImageRepairProvider {
  constructor({ fetchImpl, accessTokenProvider }) {
    if (typeof fetchImpl !== 'function') {
      throw new TypeError('fetchImpl is required.');
    }
    if (typeof accessTokenProvider !== 'function') {
      throw new TypeError('accessTokenProvider is required.');
    }
    this.fetchImpl = fetchImpl;
    this.accessTokenProvider = accessTokenProvider;
    this.name = 'baidu';
    this.cancelPolicy = 'none';
  }

  async submit({ capability, sourceUri }) {
    if (capability !== 'optimizeAiRepair') {
      throw new ProviderError('Baidu AI repair received another capability.', {
        code: 'capability_mismatch',
        status: 400,
      });
    }
    const token = await this.accessTokenProvider();
    const requestUrl = new URL(ENDPOINT);
    requestUrl.searchParams.set('access_token', token);
    const form = new URLSearchParams();
    const dataMatch = /^data:([^;,]+);base64,(.+)$/s.exec(sourceUri);
    if (dataMatch) {
      form.set('image', dataMatch[2]);
    } else if (/^https:\/\//.test(sourceUri)) {
      form.set('url', sourceUri);
    } else {
      throw new ProviderError('Baidu AI repair needs a data URI or HTTPS URL.', {
        code: 'invalid_provider_input',
        status: 400,
      });
    }

    const body = await fetchProviderJson({
      fetchImpl: this.fetchImpl,
      url: requestUrl,
      init: {
        method: 'POST',
        headers: {
          'content-type': 'application/x-www-form-urlencoded',
        },
        body: form.toString(),
      },
      timeoutMilliseconds: 30_000,
      maxResponseBytes: 20 * 1024 * 1024,
    });
    if (body.error_code || typeof body.image !== 'string') {
      throw new ProviderError('Baidu AI repair did not return an image.', {
        code: String(body.error_code ?? 'provider_invalid_response'),
        billingDisposition: body.error_code ? 'release' : 'hold',
      });
    }
    return {
      kind: 'succeeded',
      provider: 'baidu',
      model: 'image_definition_enhance',
      providerRequestId: String(body.log_id ?? ''),
      providerCancelable: false,
      output: {
        kind: 'base64',
        mimeType: 'image/jpeg',
        data: body.image,
      },
    };
  }
}
