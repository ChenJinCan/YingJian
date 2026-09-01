import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { FilePrivateMediaStore } from '../src/infrastructure/file-private-media-store.mjs';
import { FileTaskRepository } from '../src/infrastructure/file-task-repository.mjs';
import { pngFixture } from './image-fixtures.mjs';
import { mp4Fixture } from './mp4-fixture.mjs';

test('private file media is scoped to its authenticated owner', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'yingjian-media-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const store = new FilePrivateMediaStore({
    rootDirectory: directory,
    remoteDownloader: { download: async () => { throw new Error('not expected'); } },
    onExpired: async () => {},
  });
  const source = pngFixture({ width: 2, height: 2 });
  await store.putSource({
    ownerId: 'owner-a',
    mediaId: 'source-1',
    mimeType: 'image/png',
    data: source,
  });
  const resolved = await store.resolveInput({
    ownerId: 'owner-a',
    mediaId: 'source-1',
  });
  assert.match(resolved.sha256, /^[a-f0-9]{64}$/);
  assert.equal(resolved.providerUri, `data:image/png;base64,${source.toString('base64')}`);
  const downloaded = await store.read({ ownerId: 'owner-a', mediaId: 'source-1' });
  assert.equal(downloaded.mimeType, 'image/png');
  assert.deepEqual(downloaded.data, source);
  await assert.rejects(
    store.resolveInput({ ownerId: 'owner-b', mediaId: 'source-1' }),
    (error) => error.code === 'media_not_found',
  );
});

test('provider output reserves storage after download size is known and before persistence', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'yingjian-result-media-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const store = new FilePrivateMediaStore({
    rootDirectory: directory,
    remoteDownloader: { download: async () => { throw new Error('not expected'); } },
    onExpired: async () => {},
  });
  const result = pngFixture({ width: 2, height: 2 });
  const events = [];
  const stored = await store.storeProviderOutput({
    ownerId: 'owner-a',
    taskId: 'task-result',
    output: {
      kind: 'base64',
      mimeType: 'image/png',
      data: result.toString('base64'),
    },
    async reserveStorage({ mediaId, byteLength }) {
      events.push(['reserve', mediaId, byteLength]);
    },
    async commitStorage() { events.push(['commit']); },
    async releaseStorage() { events.push(['release']); },
  });
  assert.equal(stored.mediaId, 'task-result-result');
  assert.deepEqual(events, [
    ['reserve', 'task-result-result', result.length],
    ['commit'],
  ]);
});

test('provider video output is probed as H.264 MP4 before private persistence', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'yingjian-video-result-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const result = mp4Fixture();
  const store = new FilePrivateMediaStore({
    rootDirectory: directory,
    remoteDownloader: {
      download: async () => ({ data: result, mimeType: 'video/mp4' }),
    },
    onExpired: async () => {},
  });
  await store.storeProviderOutput({
    ownerId: 'owner-a',
    taskId: 'video-task',
    output: {
      kind: 'remote-url',
      url: 'https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/video.mp4',
      mediaKind: 'image_motion',
      expectedMimeType: 'video/mp4',
      expectedCodec: 'h264',
      expectedDurationMilliseconds: 3000,
    },
    async reserveStorage() {},
    async commitStorage() {},
    async releaseStorage() {},
  });

  const stored = await store.read({
    ownerId: 'owner-a',
    mediaId: 'video-task-result',
  });
  assert.equal(stored.mimeType, 'video/mp4');
  assert.equal(stored.mediaKind, 'imageMotion');
  assert.equal(stored.width, 1280);
  assert.equal(stored.height, 720);
  assert.equal(stored.durationMilliseconds, 3000);
  assert.equal(stored.codec, 'h264');
});

test('private media expires within 24 hours, is deleted, and releases storage accounting', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'yingjian-expired-media-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  let currentTime = new Date('2026-09-01T03:00:00Z');
  const expired = [];
  const store = new FilePrivateMediaStore({
    rootDirectory: directory,
    remoteDownloader: { download: async () => { throw new Error('not expected'); } },
    retentionMilliseconds: 1000,
    now: () => currentTime,
    async onExpired(value) { expired.push(value); },
  });
  const source = pngFixture({ width: 2, height: 2 });
  await store.putSource({
    ownerId: 'owner-a',
    mediaId: 'expiring-source',
    mimeType: 'image/png',
    data: source,
  });
  await store.putSource({
    ownerId: 'owner-a',
    mediaId: 'expired-without-read',
    mimeType: 'image/png',
    data: source,
  });
  currentTime = new Date('2026-09-01T03:00:01Z');
  await assert.rejects(
    store.read({ ownerId: 'owner-a', mediaId: 'expiring-source' }),
    (error) => error.code === 'media_expired' && error.status === 410,
  );
  assert.deepEqual(expired, [{
    ownerId: 'owner-a',
    mediaId: 'expiring-source',
    reservationId: 'expiring-source',
    byteLength: source.length,
  }]);
  await store.sweepExpired();
  assert.equal(expired.length, 2);
  assert.equal(expired[1].mediaId, 'expired-without-read');
  await assert.rejects(
    store.read({ ownerId: 'owner-a', mediaId: 'expiring-source' }),
    (error) => error.code === 'media_not_found',
  );
  await assert.rejects(
    store.read({ ownerId: 'owner-a', mediaId: 'expired-without-read' }),
    (error) => error.code === 'media_not_found',
  );
  assert.throws(
    () => new FilePrivateMediaStore({
      rootDirectory: directory,
      remoteDownloader: { download: async () => {} },
      onExpired: async () => {},
      retentionMilliseconds: 24 * 60 * 60 * 1000 + 1,
    }),
    /retentionMilliseconds cannot exceed 24 hours/,
  );
});

test('file task repository returns duplicates and rejects fingerprint conflicts', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'yingjian-tasks-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const repository = new FileTaskRepository({ rootDirectory: directory });
  const task = {
    id: 'task-1',
    ownerId: 'owner-a',
    creationKey: 'owner-a:creation-1:optimizeAiRepair',
    fingerprint: 'fingerprint-a',
  };

  assert.equal(
    (await repository.reserve({
      creationKey: task.creationKey,
      fingerprint: task.fingerprint,
      task,
    })).kind,
    'created',
  );
  assert.equal(
    (await repository.reserve({
      creationKey: task.creationKey,
      fingerprint: task.fingerprint,
      task: { ...task, id: 'task-2' },
    })).kind,
    'existing',
  );
  assert.equal(
    (await repository.reserve({
      creationKey: task.creationKey,
      fingerprint: 'fingerprint-b',
      task: { ...task, id: 'task-3', fingerprint: 'fingerprint-b' },
    })).kind,
    'conflict',
  );
  assert.deepEqual(await repository.get({ ownerId: 'owner-a', taskId: 'task-1' }), {
    ...task,
    version: 1,
  });
  assert.equal(await repository.get({ ownerId: 'owner-b', taskId: 'task-1' }), null);
});

test('file task repository uses append-only CAS so concurrent writers cannot overwrite', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'yingjian-task-cas-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const repository = new FileTaskRepository({ rootDirectory: directory });
  const initial = {
    id: 'task-cas',
    ownerId: 'owner-a',
    creationKey: 'owner-a:creation-cas:styleAiRedraw',
    fingerprint: 'fingerprint-cas',
    state: 'pending',
  };
  const reserved = await repository.reserve({
    creationKey: initial.creationKey,
    fingerprint: initial.fingerprint,
    task: initial,
  });
  assert.equal(reserved.task.version, 1);

  const [first, second] = await Promise.all([
    repository.compareAndSet({
      ownerId: 'owner-a',
      taskId: 'task-cas',
      expectedVersion: 1,
      task: { ...reserved.task, state: 'succeeded' },
    }),
    repository.compareAndSet({
      ownerId: 'owner-a',
      taskId: 'task-cas',
      expectedVersion: 1,
      task: { ...reserved.task, state: 'canceled' },
    }),
  ]);

  assert.deepEqual(
    [first.kind, second.kind].sort(),
    ['conflict', 'updated'],
  );
  const latest = await repository.get({ ownerId: 'owner-a', taskId: 'task-cas' });
  assert.equal(latest.version, 2);
  assert.ok(latest.state === 'succeeded' || latest.state === 'canceled');
});
