import assert from 'node:assert/strict';
import test from 'node:test';

import { R2PrivateMediaStore } from '../src/infrastructure/r2-private-media-store.mjs';
import { pngFixture } from './image-fixtures.mjs';
import { mp4Fixture } from './mp4-fixture.mjs';

class TestR2Bucket {
  constructor() {
    this.objects = new Map();
  }

  async put(key, value, options = {}) {
    const bytes = Buffer.from(value);
    const stored = {
      key,
      bytes,
      customMetadata: { ...(options.customMetadata ?? {}) },
      httpMetadata: { ...(options.httpMetadata ?? {}) },
      storageClass: options.storageClass,
    };
    this.objects.set(key, stored);
    return { ...stored, size: bytes.length };
  }

  async get(key) {
    const stored = this.objects.get(key);
    if (!stored) return null;
    return {
      key,
      body: {},
      customMetadata: { ...stored.customMetadata },
      httpMetadata: { ...stored.httpMetadata },
      async arrayBuffer() {
        return stored.bytes.buffer.slice(
          stored.bytes.byteOffset,
          stored.bytes.byteOffset + stored.bytes.byteLength,
        );
      },
    };
  }

  async delete(key) {
    this.objects.delete(key);
  }

  async list({ prefix = '' } = {}) {
    return {
      objects: [...this.objects.values()]
        .filter((item) => item.key.startsWith(prefix))
        .map((item) => ({
          key: item.key,
          customMetadata: { ...item.customMetadata },
          httpMetadata: { ...item.httpMetadata },
        })),
      truncated: false,
    };
  }
}

test('R2 media remains private per owner and expands PNG pixels only for an explicit mask', async () => {
  const bucket = new TestR2Bucket();
  const store = new R2PrivateMediaStore({
    bucket,
    remoteDownloader: { download: async () => { throw new Error('not used'); } },
    onExpired: async () => {},
  });
  const mask = pngFixture({
    width: 2,
    height: 2,
    grayscalePixels: [0, 255, 255, 0],
  });
  await store.putSource({
    ownerId: 'install:owner-a',
    mediaId: 'mask-1',
    mimeType: 'image/png',
    data: mask,
  });
  const source = await store.resolveInput({
    ownerId: 'install:owner-a',
    mediaId: 'mask-1',
    purpose: 'source',
  });
  const explicitMask = await store.resolveInput({
    ownerId: 'install:owner-a',
    mediaId: 'mask-1',
    purpose: 'mask',
  });
  assert.equal(source.isBlackWhite, false);
  assert.equal(explicitMask.isBlackWhite, true);
  await assert.rejects(
    store.read({ ownerId: 'install:owner-b', mediaId: 'mask-1' }),
    (error) => error.code === 'media_not_found',
  );
  const [stored] = [...bucket.objects.values()];
  assert.equal(stored.storageClass, 'Standard');
  assert.equal(stored.httpMetadata.cacheControl, 'no-store');
});

test('R2 cron expiry releases accounting and deletes private bytes', async () => {
  const bucket = new TestR2Bucket();
  let current = new Date('2026-09-01T00:00:00.000Z');
  const expired = [];
  const store = new R2PrivateMediaStore({
    bucket,
    remoteDownloader: { download: async () => { throw new Error('not used'); } },
    retentionMilliseconds: 1000,
    now: () => current,
    async onExpired(value) { expired.push(value); },
  });
  await store.putSource({
    ownerId: 'install:owner-a',
    mediaId: 'source-1',
    mimeType: 'image/png',
    data: pngFixture({ width: 2, height: 2 }),
  });
  current = new Date('2026-09-01T00:00:01.000Z');
  await store.sweepExpired();
  assert.equal(bucket.objects.size, 0);
  assert.deepEqual(expired.map(({ ownerId, reservationId }) => ({
    ownerId,
    reservationId,
  })), [{ ownerId: 'install:owner-a', reservationId: 'source-1' }]);
});

test('R2 provider output accepts only the explicit H.264 image-motion contract', async () => {
  const bucket = new TestR2Bucket();
  const video = mp4Fixture();
  const events = [];
  const store = new R2PrivateMediaStore({
    bucket,
    remoteDownloader: {
      download: async () => ({ data: video, mimeType: 'video/mp4' }),
    },
    onExpired: async () => {},
  });
  const stored = await store.storeProviderOutput({
    ownerId: 'install:owner-a',
    taskId: 'motion-task',
    output: {
      kind: 'remote-url',
      url: 'https://result.oss-cn-beijing.aliyuncs.com/video.mp4',
      mediaKind: 'image_motion',
      expectedMimeType: 'video/mp4',
      expectedCodec: 'h264',
      expectedDurationMilliseconds: 3000,
    },
    async reserveStorage() { events.push('reserve'); },
    async commitStorage() { events.push('commit'); },
    async releaseStorage() { events.push('release'); },
  });
  assert.equal(stored.mediaKind, 'imageMotion');
  assert.equal(stored.durationMilliseconds, 3000);
  assert.deepEqual(events, ['reserve', 'commit']);
  const read = await store.read({
    ownerId: 'install:owner-a',
    mediaId: 'motion-task-result',
  });
  assert.equal(read.mimeType, 'video/mp4');
  assert.equal(read.codec, 'h264');
  assert.equal(read.mediaKind, 'imageMotion');
});
