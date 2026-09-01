import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { Readable } from 'node:stream';
import test from 'node:test';

import { HmacOfferAuthority } from '../src/security/hmac-offer-authority.mjs';
import { LocalFixedUsageGuard } from '../src/security/local-fixed-usage-guard.mjs';
import { probeImage } from '../src/security/image-probe.mjs';
import { probeMp4 } from '../src/security/mp4-probe.mjs';
import { createAlibabaResultDownloader } from '../src/security/restricted-result-downloader.mjs';
import { fetchProviderJson } from '../src/providers/bounded-provider-fetch.mjs';
import { pngFixture } from './image-fixtures.mjs';
import { mp4Fixture } from './mp4-fixture.mjs';

test('signed offers are owner-bound, expire, and require policy version 1', () => {
  const authority = new HmacOfferAuthority({
    signingKey: '0123456789abcdef0123456789abcdef',
    ttlMilliseconds: 15 * 60 * 1000,
  });
  const issuedAt = new Date('2026-09-01T03:00:00Z');
  const offer = authority.issue({
    ownerId: 'owner-a',
    capability: 'optimizeAiRepair',
    creditCost: 1,
    policyVersion: 1,
    now: issuedAt,
  });

  assert.equal(offer.creditCost, 1);
  assert.equal(offer.expiresAt, '2026-09-01T03:15:00.000Z');
  assert.equal(
    authority.verify({
      offerId: offer.id,
      ownerId: 'owner-a',
      capability: 'optimizeAiRepair',
      policyVersion: 1,
      now: new Date('2026-09-01T03:14:59Z'),
    }).creditCost,
    1,
  );
  assert.throws(
    () =>
      authority.verify({
        offerId: offer.id,
        ownerId: 'owner-a',
        capability: 'optimizeAiRepair',
        policyVersion: 1,
        now: new Date('2026-09-01T03:15:00Z'),
      }),
    (error) => error.code === 'offer_expired',
  );
  assert.throws(
    () =>
      authority.verify({
        offerId: offer.id,
        ownerId: 'owner-b',
        capability: 'optimizeAiRepair',
        policyVersion: 1,
        now: issuedAt,
      }),
    (error) => error.code === 'offer_mismatch',
  );
  assert.throws(
    () =>
      authority.verify({
        offerId: offer.id,
        ownerId: 'owner-a',
        capability: 'optimizeAiRepair',
        policyVersion: 999,
        now: issuedAt,
      }),
    (error) => error.code === 'policy_version_unsupported',
  );
});

test('provider JSON fetch has a deadline and streaming response cap', async () => {
  await assert.rejects(
    fetchProviderJson({
      fetchImpl: async () => new Response(Buffer.from('123456')),
      url: 'https://provider.example',
      init: { method: 'POST' },
      timeoutMilliseconds: 1000,
      maxResponseBytes: 5,
    }),
    (error) => error.code === 'provider_response_too_large',
  );

  await assert.rejects(
    fetchProviderJson({
      fetchImpl: (_url, init) =>
        new Promise((_resolve, reject) => {
          init.signal.addEventListener('abort', () => reject(init.signal.reason));
        }),
      url: 'https://provider.example',
      init: { method: 'POST' },
      timeoutMilliseconds: 5,
      maxResponseBytes: 100,
    }),
    (error) => error.code === 'provider_timeout' && error.billingDisposition === 'hold',
  );

  await assert.rejects(
    fetchProviderJson({
      fetchImpl: async () => Response.json({ code: 'InvalidParameter' }, { status: 400 }),
      url: 'https://provider.example',
      init: { method: 'POST' },
      timeoutMilliseconds: 1000,
      maxResponseBytes: 100,
    }),
    (error) =>
      error.code === 'provider_rejected' &&
      error.billingDisposition === 'release' &&
      !error.message.includes('InvalidParameter'),
  );
});

function fakeHttpsRequest({ statusCode = 200, headers = {}, chunks = [] }) {
  return (_url, _options, callback) => {
    const request = new EventEmitter();
    request.setTimeout = () => request;
    request.destroy = (error) => {
      if (error) queueMicrotask(() => request.emit('error', error));
    };
    request.end = () => {
      const response = Readable.from(chunks);
      response.statusCode = statusCode;
      response.headers = headers;
      queueMicrotask(() => callback(response));
    };
    return request;
  };
}

test('Alibaba result downloader rejects private DNS and enforces streaming limits', async () => {
  const privateDownloader = createAlibabaResultDownloader({
    lookupImpl: async () => [{ address: '127.0.0.1', family: 4 }],
    requestImpl: () => {
      throw new Error('request must not start');
    },
    maxBytes: 5,
    timeoutMilliseconds: 1000,
  });
  await assert.rejects(
    privateDownloader.download(
      'https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/result.png',
    ),
    (error) => error.code === 'provider_output_address_forbidden',
  );
  await assert.rejects(
    privateDownloader.download('https://127.0.0.1/result.png'),
    (error) => error.code === 'provider_output_host_forbidden',
  );

  const boundedDownloader = createAlibabaResultDownloader({
    lookupImpl: async () => [{ address: '8.8.8.8', family: 4 }],
    requestImpl: fakeHttpsRequest({
      headers: { 'content-type': 'image/png' },
      chunks: [Buffer.from('123'), Buffer.from('456')],
    }),
    maxBytes: 5,
    timeoutMilliseconds: 1000,
  });
  await assert.rejects(
    boundedDownloader.download(
      'https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/result.png',
    ),
    (error) => error.code === 'provider_output_too_large',
  );

  const redirectDownloader = createAlibabaResultDownloader({
    lookupImpl: async () => [{ address: '8.8.8.8', family: 4 }],
    requestImpl: fakeHttpsRequest({
      statusCode: 302,
      headers: { location: 'https://other.example/result.png' },
    }),
    maxBytes: 5,
    timeoutMilliseconds: 1000,
  });
  await assert.rejects(
    redirectDownloader.download(
      'https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/result.png',
    ),
    (error) => error.code === 'provider_output_redirect_forbidden',
  );
});

test('Alibaba result deadline covers DNS and rejects IPv4-mapped loopback', { timeout: 1000 }, async () => {
  const mappedDownloader = createAlibabaResultDownloader({
    lookupImpl: async () => [{ address: '::ffff:7f00:1', family: 6 }],
    requestImpl: () => { throw new Error('request must not start'); },
    timeoutMilliseconds: 10,
  });
  await assert.rejects(
    mappedDownloader.download(
      'https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/result.png',
    ),
    (error) => error.code === 'provider_output_address_forbidden',
  );

  const dnsTimeoutDownloader = createAlibabaResultDownloader({
    lookupImpl: async () => new Promise(() => {}),
    requestImpl: () => { throw new Error('request must not start'); },
    timeoutMilliseconds: 10,
  });
  await assert.rejects(
    dnsTimeoutDownloader.download(
      'https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/result.png',
    ),
    (error) => error.code === 'provider_output_timeout' && error.status === 504,
  );
});

test('image probing rejects disguised files and identifies strict black-white PNG masks', () => {
  assert.throws(
    () => probeImage(Buffer.from('not-an-image'), { declaredMimeType: 'image/jpeg' }),
    (error) => error.code === 'image_header_invalid',
  );
  const source = probeImage(pngFixture({ width: 2, height: 1 }), {
    declaredMimeType: 'image/png',
  });
  assert.deepEqual(source, {
    format: 'png',
    mimeType: 'image/png',
    width: 2,
    height: 1,
    byteLength: source.byteLength,
    isBlackWhite: false,
  });
  const mask = probeImage(
    pngFixture({ width: 2, height: 1, grayscalePixels: [0, 255] }),
    { declaredMimeType: 'image/png' },
  );
  assert.equal(mask.isBlackWhite, true);
  const gray = probeImage(
    pngFixture({ width: 2, height: 1, grayscalePixels: [0, 128] }),
    { declaredMimeType: 'image/png' },
  );
  assert.equal(gray.isBlackWhite, false);
  assert.throws(
    () => probeImage(pngFixture({}), { declaredMimeType: 'image/jpeg' }),
    (error) => error.code === 'image_mime_mismatch',
  );
});

test('MP4 probing accepts one H.264 video track and rejects a disguised codec', () => {
  const video = mp4Fixture();
  assert.deepEqual(probeMp4(video, { declaredMimeType: 'video/mp4' }), {
    format: 'mp4',
    mimeType: 'video/mp4',
    mediaKind: 'imageMotion',
    byteLength: video.length,
    width: 1280,
    height: 720,
    durationMilliseconds: 3000,
    codec: 'h264',
  });
  assert.throws(
    () =>
      probeMp4(mp4Fixture({ codec: 'hvc1' }), {
        declaredMimeType: 'video/mp4',
      }),
    (error) => error.code === 'video_codec_unsupported',
  );
  assert.throws(
    () => probeMp4(video, { declaredMimeType: 'application/octet-stream' }),
    (error) => error.code === 'video_mime_mismatch',
  );
});

test('local usage guard reserves atomically, is idempotent, and enforces credit/storage limits', async () => {
  const guard = new LocalFixedUsageGuard({
    maxCreditsPerOwner: 1,
    maxConcurrentGenerationsPerOwner: 1,
    maxGenerationReservationsPerWindow: 10,
    rateWindowMilliseconds: 60_000,
    maxStorageBytesPerOwner: 10,
    now: () => new Date('2026-09-01T03:00:00Z'),
  });

  assert.equal(
    (await guard.reserveGeneration({
      ownerId: 'owner-a',
      reservationId: 'task-1',
      fingerprint: 'fingerprint-a',
      creditCost: 1,
    })).kind,
    'reserved',
  );
  assert.equal(
    (await guard.reserveGeneration({
      ownerId: 'owner-a',
      reservationId: 'task-1',
      fingerprint: 'fingerprint-a',
      creditCost: 1,
    })).kind,
    'existing',
  );
  await assert.rejects(
    guard.reserveGeneration({
      ownerId: 'owner-a',
      reservationId: 'task-1',
      fingerprint: 'fingerprint-b',
      creditCost: 1,
    }),
    (error) => error.code === 'usage_reservation_conflict',
  );
  await assert.rejects(
    guard.reserveGeneration({
      ownerId: 'owner-a',
      reservationId: 'task-2',
      fingerprint: 'fingerprint-2',
      creditCost: 1,
    }),
    (error) => error.code === 'generation_concurrency_exceeded',
  );
  assert.equal(
    (await guard.releaseGeneration({ ownerId: 'owner-a', reservationId: 'task-1' }))
      .kind,
    'released',
  );
  assert.equal(
    (await guard.reserveGeneration({
      ownerId: 'owner-a',
      reservationId: 'task-2',
      fingerprint: 'fingerprint-2',
      creditCost: 1,
    })).kind,
    'reserved',
  );
  await guard.settleGeneration({ ownerId: 'owner-a', reservationId: 'task-2' });
  await assert.rejects(
    guard.reserveGeneration({
      ownerId: 'owner-a',
      reservationId: 'task-3',
      fingerprint: 'fingerprint-3',
      creditCost: 1,
    }),
    (error) => error.code === 'generation_credit_exhausted',
  );

  await guard.reserveStorage({
    ownerId: 'owner-a',
    reservationId: 'media-1',
    bytes: 8,
  });
  await guard.commitStorage({ ownerId: 'owner-a', reservationId: 'media-1' });
  await assert.rejects(
    guard.reserveStorage({
      ownerId: 'owner-a',
      reservationId: 'media-2',
      bytes: 3,
    }),
    (error) => error.code === 'storage_quota_exceeded',
  );
  assert.equal(
    (await guard.expireStorage({ ownerId: 'owner-a', reservationId: 'media-1' })).kind,
    'expired',
  );
  assert.equal(
    (await guard.reserveStorage({
      ownerId: 'owner-a',
      reservationId: 'media-2',
      bytes: 3,
    })).kind,
    'reserved',
  );
});
