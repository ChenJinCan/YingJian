import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { D1TaskRepository } from '../src/infrastructure/d1-task-repository.mjs';
import { D1UsageGuard } from '../src/security/d1-usage-guard.mjs';
import { TestD1Database } from './cloudflare-d1-test-binding.mjs';

const schema = await readFile(
  new URL('../migrations/0001_generation_mvp.sql', import.meta.url),
  'utf8',
);

function database(t) {
  const value = new TestD1Database(schema);
  t.after(() => value.close());
  return value;
}

test('D1 task repository persists idempotency and compare-and-set versions', async (t) => {
  const db = database(t);
  const repository = new D1TaskRepository({ database: db });
  const task = {
    id: 'task-1',
    ownerId: 'install:owner-a',
    creationKey: 'install:owner-a:create-1:optimizeAiRepair',
    fingerprint: 'fingerprint-a',
    state: 'created',
    createdAt: '2026-09-01T00:00:00.000Z',
    updatedAt: '2026-09-01T00:00:00.000Z',
  };
  const created = await repository.reserve({
    creationKey: task.creationKey,
    fingerprint: task.fingerprint,
    task,
  });
  assert.equal(created.kind, 'created');
  assert.equal(created.task.version, 1);
  assert.equal(
    (await repository.reserve({
      creationKey: task.creationKey,
      fingerprint: task.fingerprint,
      task: { ...task, id: 'task-ignored' },
    })).kind,
    'existing',
  );
  assert.equal(
    (await repository.reserve({
      creationKey: task.creationKey,
      fingerprint: 'other-fingerprint',
      task: {
        ...task,
        id: 'task-conflict',
        fingerprint: 'other-fingerprint',
      },
    })).kind,
    'conflict',
  );
  const [first, second] = await Promise.all([
    repository.compareAndSet({
      ownerId: task.ownerId,
      taskId: task.id,
      expectedVersion: 1,
      task: { ...created.task, state: 'succeeded' },
    }),
    repository.compareAndSet({
      ownerId: task.ownerId,
      taskId: task.id,
      expectedVersion: 1,
      task: { ...created.task, state: 'canceled' },
    }),
  ]);
  assert.deepEqual([first.kind, second.kind].sort(), ['conflict', 'updated']);
  assert.equal(
    (await repository.get({ ownerId: task.ownerId, taskId: task.id })).version,
    2,
  );
});

test('D1 usage guard atomically enforces enrolled credits and storage', async (t) => {
  const db = database(t);
  await db
    .prepare(
      `INSERT INTO usage_accounts
        (owner_id, credit_limit, status, created_at_ms, updated_at_ms)
       VALUES (?, 2, 'active', 0, 0)`,
    )
    .bind('install:owner-a')
    .run();
  const guard = new D1UsageGuard({
    database: db,
    maxCreditsPerOwner: 5,
    maxConcurrentGenerationsPerOwner: 2,
    maxGenerationReservationsPerWindow: 5,
    maxGlobalGenerationReservationsPerWindow: 50,
    rateWindowMilliseconds: 60_000,
    maxStorageBytesPerOwner: 100,
    now: () => new Date('2026-09-01T00:00:00.000Z'),
  });
  assert.equal(
    (await guard.reserveGeneration({
      ownerId: 'install:owner-a',
      reservationId: 'generation-1',
      fingerprint: 'fingerprint-1',
      creditCost: 1,
    })).kind,
    'reserved',
  );
  assert.equal(
    (await guard.reserveGeneration({
      ownerId: 'install:owner-a',
      reservationId: 'generation-1',
      fingerprint: 'fingerprint-1',
      creditCost: 1,
    })).kind,
    'existing',
  );
  assert.equal(
    (await guard.settleGeneration({
      ownerId: 'install:owner-a',
      reservationId: 'generation-1',
    })).kind,
    'settled',
  );
  await guard.reserveGeneration({
    ownerId: 'install:owner-a',
    reservationId: 'generation-2',
    fingerprint: 'fingerprint-2',
    creditCost: 1,
  });
  await assert.rejects(
    guard.reserveGeneration({
      ownerId: 'install:owner-a',
      reservationId: 'generation-3',
      fingerprint: 'fingerprint-3',
      creditCost: 1,
    }),
    (error) => error.code === 'generation_credit_exhausted' && error.status === 402,
  );
  await assert.rejects(
    guard.reserveGeneration({
      ownerId: 'install:not-enrolled',
      reservationId: 'generation-x',
      fingerprint: 'fingerprint-x',
      creditCost: 1,
    }),
    (error) => error.code === 'generation_entitlement_required',
  );
  assert.equal(
    (await guard.reserveStorage({
      ownerId: 'install:owner-a',
      reservationId: 'media-1',
      bytes: 60,
    })).kind,
    'reserved',
  );
  await guard.commitStorage({
    ownerId: 'install:owner-a',
    reservationId: 'media-1',
  });
  await assert.rejects(
    guard.reserveStorage({
      ownerId: 'install:owner-a',
      reservationId: 'media-2',
      bytes: 41,
    }),
    (error) => error.code === 'storage_quota_exceeded',
  );
  await guard.expireStorage({
    ownerId: 'install:owner-a',
    reservationId: 'media-1',
  });
  assert.equal(
    (await guard.reserveStorage({
      ownerId: 'install:owner-a',
      reservationId: 'media-2',
      bytes: 41,
    })).kind,
    'reserved',
  );
});

test('D1 usage guard atomically caps generation reservations across all owners', async (t) => {
  const db = database(t);
  for (const ownerId of ['install:owner-a', 'install:owner-b']) {
    await db
      .prepare(
        `INSERT INTO usage_accounts
          (owner_id, credit_limit, status, created_at_ms, updated_at_ms)
         VALUES (?, 5, 'active', 0, 0)`,
      )
      .bind(ownerId)
      .run();
  }
  let now = new Date('2026-09-01T00:00:00.000Z');
  const guard = new D1UsageGuard({
    database: db,
    maxCreditsPerOwner: 5,
    maxConcurrentGenerationsPerOwner: 5,
    maxGenerationReservationsPerWindow: 5,
    maxGlobalGenerationReservationsPerWindow: 1,
    rateWindowMilliseconds: 60_000,
    maxStorageBytesPerOwner: 100,
    now: () => now,
  });
  const outcomes = await Promise.allSettled([
    guard.reserveGeneration({
      ownerId: 'install:owner-a',
      reservationId: 'generation-a',
      fingerprint: 'fingerprint-a',
      creditCost: 1,
    }),
    guard.reserveGeneration({
      ownerId: 'install:owner-b',
      reservationId: 'generation-b',
      fingerprint: 'fingerprint-b',
      creditCost: 1,
    }),
  ]);

  assert.equal(outcomes.filter(({ status }) => status === 'fulfilled').length, 1);
  const rejectedIndex = outcomes.findIndex(({ status }) => status === 'rejected');
  const rejected = outcomes[rejectedIndex];
  assert.equal(rejected?.reason.code, 'generation_global_rate_exceeded');
  assert.equal(rejected?.reason.status, 429);

  now = new Date('2026-09-01T00:01:00.001Z');
  const blockedOwnerId = rejectedIndex === 0
    ? 'install:owner-a'
    : 'install:owner-b';
  assert.equal(
    (await guard.reserveGeneration({
      ownerId: blockedOwnerId,
      reservationId: 'generation-after-window',
      fingerprint: 'fingerprint-after-window',
      creditCost: 1,
    })).kind,
    'reserved',
  );
});
