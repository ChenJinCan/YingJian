function assertDatabase(database) {
  if (!database || typeof database.prepare !== 'function') {
    throw new TypeError('database is required.');
  }
}

function parseTaskRow(row) {
  if (!row || typeof row.task_json !== 'string') return null;
  let task;
  try {
    task = JSON.parse(row.task_json);
  } catch {
    throw new Error('Persisted task JSON is invalid.');
  }
  if (
    !task ||
    typeof task !== 'object' ||
    task.id !== row.id ||
    task.ownerId !== row.owner_id ||
    task.creationKey !== row.creation_key ||
    task.fingerprint !== row.fingerprint ||
    task.version !== row.version
  ) {
    throw new Error('Persisted task identity is invalid.');
  }
  return task;
}

function assertTaskIdentity(task, { ownerId, taskId }) {
  if (task?.ownerId !== ownerId || task?.id !== taskId) {
    throw new TypeError('Task identity cannot change.');
  }
}

function changedRows(result) {
  return Number(result?.meta?.changes ?? 0);
}

/**
 * Durable task/idempotency repository backed by a single D1 row per task.
 * The unique creation_key insert is the idempotency decision; CAS updates are
 * guarded by the persisted version so two Worker isolates cannot overwrite one
 * another.
 */
export class D1TaskRepository {
  constructor({ database }) {
    assertDatabase(database);
    this.database = database;
  }

  async reserve({ creationKey, fingerprint, task }) {
    if (
      typeof creationKey !== 'string' ||
      creationKey.length === 0 ||
      typeof fingerprint !== 'string' ||
      fingerprint.length === 0 ||
      !task ||
      typeof task !== 'object'
    ) {
      throw new TypeError('creationKey, fingerprint, and task are required.');
    }
    if (
      task.creationKey !== creationKey ||
      task.fingerprint !== fingerprint ||
      typeof task.id !== 'string' ||
      typeof task.ownerId !== 'string'
    ) {
      throw new TypeError('Task identity must match its reservation.');
    }
    const initial = { ...task, version: 1 };
    const inserted = await this.database
      .prepare(
        `INSERT OR IGNORE INTO generation_tasks
          (id, owner_id, creation_key, fingerprint, version, task_json, created_at, updated_at)
         VALUES (?, ?, ?, ?, 1, ?, ?, ?)`,
      )
      .bind(
        initial.id,
        initial.ownerId,
        creationKey,
        fingerprint,
        JSON.stringify(initial),
        initial.createdAt ?? new Date().toISOString(),
        initial.updatedAt ?? initial.createdAt ?? new Date().toISOString(),
      )
      .run();
    const row = await this.database
      .prepare(
        `SELECT id, owner_id, creation_key, fingerprint, version, task_json
           FROM generation_tasks
          WHERE creation_key = ?`,
      )
      .bind(creationKey)
      .first();
    const existing = parseTaskRow(row);
    if (!existing) {
      throw new Error('Task reservation could not be persisted.');
    }
    if (changedRows(inserted) === 1) {
      return { kind: 'created', task: existing };
    }
    return row.fingerprint === fingerprint
      ? { kind: 'existing', task: existing }
      : { kind: 'conflict', task: existing };
  }

  async compareAndSet({ ownerId, taskId, expectedVersion, task }) {
    if (!Number.isInteger(expectedVersion) || expectedVersion <= 0) {
      throw new TypeError('expectedVersion must be a positive integer.');
    }
    assertTaskIdentity(task, { ownerId, taskId });
    const updated = { ...task, version: expectedVersion + 1 };
    const result = await this.database
      .prepare(
        `UPDATE generation_tasks
            SET version = ?, task_json = ?, updated_at = ?
          WHERE id = ? AND owner_id = ? AND version = ?`,
      )
      .bind(
        updated.version,
        JSON.stringify(updated),
        updated.updatedAt ?? new Date().toISOString(),
        taskId,
        ownerId,
        expectedVersion,
      )
      .run();
    if (changedRows(result) === 1) {
      return { kind: 'updated', task: updated };
    }
    const current = await this.get({ ownerId, taskId });
    return current
      ? { kind: 'conflict', task: current }
      : { kind: 'missing', task: null };
  }

  async get({ ownerId, taskId }) {
    const row = await this.database
      .prepare(
        `SELECT id, owner_id, creation_key, fingerprint, version, task_json
           FROM generation_tasks
          WHERE id = ? AND owner_id = ?`,
      )
      .bind(taskId, ownerId)
      .first();
    return parseTaskRow(row);
  }

  async getByCreation({ ownerId, creationKey }) {
    const row = await this.database
      .prepare(
        `SELECT id, owner_id, creation_key, fingerprint, version, task_json
           FROM generation_tasks
          WHERE creation_key = ? AND owner_id = ?`,
      )
      .bind(creationKey, ownerId)
      .first();
    return parseTaskRow(row);
  }
}
