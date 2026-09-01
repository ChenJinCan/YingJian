import { createHash, createHmac } from 'node:crypto';

import { fetchProviderJson } from './bounded-provider-fetch.mjs';
import { ProviderError } from './provider-error.mjs';

const HOST = 'visual.volcengineapi.com';
const ENDPOINT = `https://${HOST}/?Action=LensOpr&Version=2024-06-06`;
const REGION = 'cn-beijing';
const SERVICE = 'cv';
const SIGNED_HEADERS = 'content-type;host;x-content-sha256;x-date';

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function hmac(key, value) {
  return createHmac('sha256', key).update(value).digest();
}

function utcTimestamp(date) {
  return date.toISOString().replace(/[:-]|\.\d{3}/g, '');
}

export function signVolcengineRequest({
  accessKeyId,
  secretAccessKey,
  body,
  date,
}) {
  const requestDate = utcTimestamp(date);
  const shortDate = requestDate.slice(0, 8);
  const payloadHash = sha256(body);
  const canonicalHeaders =
    `content-type:application/json\n` +
    `host:${HOST}\n` +
    `x-content-sha256:${payloadHash}\n` +
    `x-date:${requestDate}\n`;
  const canonicalRequest =
    `POST\n/\nAction=LensOpr&Version=2024-06-06\n` +
    `${canonicalHeaders}\n${SIGNED_HEADERS}\n${payloadHash}`;
  const credentialScope = `${shortDate}/${REGION}/${SERVICE}/request`;
  const stringToSign =
    `HMAC-SHA256\n${requestDate}\n${credentialScope}\n` +
    sha256(canonicalRequest);
  const dateKey = hmac(secretAccessKey, shortDate);
  const regionKey = hmac(dateKey, REGION);
  const serviceKey = hmac(regionKey, SERVICE);
  const signingKey = hmac(serviceKey, 'request');
  const signature = createHmac('sha256', signingKey)
    .update(stringToSign)
    .digest('hex');
  return {
    'content-type': 'application/json',
    host: HOST,
    'x-content-sha256': payloadHash,
    'x-date': requestDate,
    authorization:
      `HMAC-SHA256 Credential=${accessKeyId}/${credentialScope}, ` +
      `SignedHeaders=${SIGNED_HEADERS}, Signature=${signature}`,
  };
}

export class VolcengineOldPhotoProvider {
  constructor({
    accessKeyId,
    secretAccessKey,
    fetchImpl,
    enabled = false,
    now = () => new Date(),
  }) {
    if (enabled === true && (typeof accessKeyId !== 'string' || accessKeyId.length === 0)) {
      throw new TypeError('accessKeyId is required.');
    }
    if (
      enabled === true &&
      (typeof secretAccessKey !== 'string' || secretAccessKey.length === 0)
    ) {
      throw new TypeError('secretAccessKey is required.');
    }
    if (typeof fetchImpl !== 'function') {
      throw new TypeError('fetchImpl is required.');
    }
    this.accessKeyId = accessKeyId;
    this.secretAccessKey = secretAccessKey;
    this.fetchImpl = fetchImpl;
    this.enabled = enabled === true;
    this.now = now;
    this.name = 'volcengine';
    this.cancelPolicy = 'none';
  }

  async submit({ capability, sourceUri, colorMode }) {
    if (capability !== 'optimizeOldPhoto') {
      throw new ProviderError('Old photo provider received another capability.', {
        code: 'capability_mismatch',
        status: 400,
      });
    }
    if (!this.enabled) {
      throw new ProviderError('Old photo repair is not enabled.', {
        code: 'capability_disabled',
        status: 503,
      });
    }
    if (colorMode !== 'preserve' && colorMode !== 'colorize') {
      throw new ProviderError('An explicit old-photo color mode is required.', {
        code: 'color_mode_required',
        status: 400,
      });
    }
    const dataMatch = /^data:([^;,]+);base64,(.+)$/s.exec(sourceUri);
    const requestBody = {
      req_key: 'lens_opr',
      ...(dataMatch
        ? { binary_data_base64: [dataMatch[2]] }
        : { image_urls: [sourceUri] }),
      // 2 asks the provider to decide whether to colorize. It is forbidden.
      if_color: colorMode === 'colorize' ? 1 : 0,
    };
    const body = JSON.stringify(requestBody);
    const headers = signVolcengineRequest({
      accessKeyId: this.accessKeyId,
      secretAccessKey: this.secretAccessKey,
      body,
      date: this.now(),
    });
    const payload = await fetchProviderJson({
      fetchImpl: this.fetchImpl,
      url: ENDPOINT,
      init: {
        method: 'POST',
        headers,
        body,
      },
      timeoutMilliseconds: 30_000,
      maxResponseBytes: 30 * 1024 * 1024,
    });
    const output = payload?.data?.binary_data_base64?.[0];
    if (Number(payload?.code) !== 10000 || typeof output !== 'string') {
      throw new ProviderError('Volcengine old photo repair did not return an image.', {
        code: String(payload?.code ?? 'provider_invalid_response'),
      });
    }
    return {
      kind: 'succeeded',
      provider: 'volcengine',
      model: 'lens_opr',
      providerRequestId: String(payload.request_id ?? ''),
      providerCancelable: false,
      output: {
        kind: 'base64',
        mimeType: 'image/jpeg',
        data: output,
      },
    };
  }
}
