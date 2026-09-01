import { createHash, randomUUID } from 'node:crypto';
import { link, mkdir, readFile, readdir, unlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

function digest(value) {
  return createHash('sha256').update(value).digest('hex');
}

function versionFilename(version) {
  return `${String(version).padStart(16, '0')}.json`;
}

function assertTaskIdentity(task, { ownerId, taskId }) {
  if (task?.ownerId !== ownerId || task?.id !== taskId) {
    throw new TypeError('Task identity cannot change.');
  }
}

async function writeExclusive(destination, contents) {
  const temporary = `${destination}.${randomUUID()}.tmp`;
  try {
    await writeFile(temporary, contents, {
      flag: 'wx',
      mode: 0o600,
      flush: true,
    });
    await link(temporary, destination);
  } finally {
    await unlink(temporary).catch((error) => {
      if (error?.code !== 'ENOENT') throw error;
    });
  }
}

export class FileTaskRepository {
  constructor({ rootDirectory }) {
    if (typeof rootDirectory !== 'string' || rootDirectory.length === 0) {
      throw new TypeError('rootDirectory is required.');
    }
    this.rootDirectory = rootDirectory;
  }

  async reserve({ creationKey, fingerprint, task }) {
    await this.#ensureDirectories();
    const initial = { ...task, version: 1 };
    const taskDirectory = this.#taskDirectory(task.id);
    await mkdir(taskDirectory, { recursive: true, mode: 0o700 });
    try {
      await writeExclusive(
        join(taskDirectory, versionFilename(1)),
        JSON.stringify(initial),
      );
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
    }

    const indexPath = join(this.rootDirectory, 'creation', `${digest(creationKey)}.json`);
    try {
      await writeExclusive(
        indexPath,
        JSON.stringify({
          creationKey,
          fingerprint,
          ownerId: initial.ownerId,
          taskId: initial.id,
        }),
      );
      return { kind: 'created', task: initial };
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
    }
    const index = JSON.parse(await readFile(indexPath, 'utf8'));
    const existing = await this.get({ ownerId: index.ownerId, taskId: index.taskId });
    if (!existing) {
      throw new Error('Task creation index points to a missing task.');
    }
    return index.fingerprint === fingerprint
      ? { kind: 'existing', task: existing }
      : { kind: 'conflict', task: existing };
  }

  async compareAndSet({ ownerId, taskId, expectedVersion, task }) {
    if (!Number.isInteger(expectedVersion) || expectedVersion <= 0) {
      throw new TypeError('expectedVersion must be a positive integer.');
    }
    assertTaskIdentity(task, { ownerId, taskId });
    const current = await this.get({ ownerId, taskId });
    if (!current) return { kind: 'missing', task: null };
    if (current.version !== expectedVersion) {
      return { kind: 'conflict', task: current };
    }
    const updated = { ...task, version: expectedVersion + 1 };
    try {
      await writeExclusive(
        join(this.#taskDirectory(taskId), versionFilename(updated.version)),
        JSON.stringify(updated),
      );
      return { kind: 'updated', task: updated };
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      return {
        kind: 'conflict',
        task: await this.get({ ownerId, taskId }),
      };
    }
  }

  async get({ ownerId, taskId }) {
    let filenames;
    try {
      filenames = await readdir(this.#taskDirectory(taskId));
    } catch (error) {
      if (error?.code === 'ENOENT') return null;
      throw error;
    }
    const versions = filenames
      .filter((name) => /^\d{16}\.json$/.test(name))
      .sort();
    if (versions.length === 0) return null;
    const task = JSON.parse(
      await readFile(join(this.#taskDirectory(taskId), versions.at(-1)), 'utf8'),
    );
    return task.ownerId === ownerId && task.id === taskId ? task : null;
  }

  #taskDirectory(taskId) {
    return join(this.rootDirectory, 'tasks', digest(taskId));
  }

  async #ensureDirectories() {
    await mkdir(join(this.rootDirectory, 'tasks'), { recursive: true, mode: 0o700 });
    await mkdir(join(this.rootDirectory, 'creation'), { recursive: true, mode: 0o700 });
  }
}
