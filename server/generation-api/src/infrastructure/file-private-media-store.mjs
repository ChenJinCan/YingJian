import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readFile, readdir, rename, unlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

import { probeImage } from '../security/image-probe.mjs';
import { probeMp4 } from '../security/mp4-probe.mjs';

const MAX_MEDIA_BYTES = 25 * 1024 * 1024;
const MAX_RETENTION_MILLISECONDS = 24 * 60 * 60 * 1000;
const SOURCE_MIME_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/bmp',
]);
const STORED_MIME_TYPES = new Set([...SOURCE_MIME_TYPES, 'video/mp4']);

class MediaStoreError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
    this.status =
      code === 'media_not_found' ? 404 : code === 'media_expired' ? 410 : 422;
  }
}

function digest(value) {
  return createHash('sha256').update(value).digest('hex');
}

function assertIdentifier(value) {
  if (typeof value !== 'string' || value.length === 0 || value.length > 256) {
    throw new MediaStoreError('media_identifier_invalid');
  }
}

export class FilePrivateMediaStore {
  constructor({
    rootDirectory,
    remoteDownloader,
    onExpired,
    retentionMilliseconds = MAX_RETENTION_MILLISECONDS,
    now = () => new Date(),
  }) {
    if (typeof rootDirectory !== 'string' || rootDirectory.length === 0) {
      throw new TypeError('rootDirectory is required.');
    }
    if (!remoteDownloader || typeof remoteDownloader.download !== 'function') {
      throw new TypeError('remoteDownloader is required.');
    }
    if (typeof onExpired !== 'function') {
      throw new TypeError('onExpired is required.');
    }
    if (!Number.isInteger(retentionMilliseconds) || retentionMilliseconds <= 0) {
      throw new TypeError('retentionMilliseconds must be a positive integer.');
    }
    if (retentionMilliseconds > MAX_RETENTION_MILLISECONDS) {
      throw new TypeError('retentionMilliseconds cannot exceed 24 hours.');
    }
    this.rootDirectory = rootDirectory;
    this.remoteDownloader = remoteDownloader;
    this.onExpired = onExpired;
    this.retentionMilliseconds = retentionMilliseconds;
    this.now = now;
    this.expirationTimer = null;
    this.nextExpiration = null;
  }

  async putSource({
    ownerId,
    mediaId,
    mimeType,
    data,
    storageReservationId = mediaId,
  }) {
    assertIdentifier(ownerId);
    assertIdentifier(mediaId);
    assertIdentifier(storageReservationId);
    if (!SOURCE_MIME_TYPES.has(mimeType)) {
      throw new MediaStoreError('media_type_not_allowed');
    }
    const bytes = Buffer.isBuffer(data) ? data : Buffer.from(data);
    if (bytes.length === 0 || bytes.length > MAX_MEDIA_BYTES) {
      throw new MediaStoreError('media_size_invalid');
    }
    const image = probeImage(bytes, { declaredMimeType: mimeType });
    return this.#putVerifiedMedia({
      ownerId,
      mediaId,
      storageReservationId,
      mimeType,
      bytes,
      media: {
        mediaKind: 'image',
        format: image.format,
        width: image.width,
        height: image.height,
        durationMilliseconds: null,
        codec: null,
        isBlackWhite: image.isBlackWhite,
      },
    });
  }

  async resolveInput({ ownerId, mediaId }) {
    const media = await this.read({ ownerId, mediaId });
    return {
      sha256: media.sha256,
      providerUri: `data:${media.mimeType};base64,${media.data.toString('base64')}`,
      format: media.format,
      width: media.width,
      height: media.height,
      byteLength: media.byteLength,
      isBlackWhite: media.isBlackWhite,
    };
  }

  async read({ ownerId, mediaId }) {
    assertIdentifier(ownerId);
    assertIdentifier(mediaId);
    const directory = await this.#ownerDirectory(ownerId);
    const key = digest(mediaId);
    let metadata;
    try {
      metadata = JSON.parse(await readFile(join(directory, `${key}.json`), 'utf8'));
    } catch (error) {
      if (error?.code === 'ENOENT' || error instanceof SyntaxError) {
        throw new MediaStoreError('media_not_found');
      }
      throw error;
    }
    if (metadata.ownerId !== ownerId || metadata.mediaId !== mediaId) {
      throw new MediaStoreError('media_integrity_failed');
    }
    const expiresAt = Date.parse(metadata.expiresAt);
    if (!Number.isFinite(expiresAt) || this.now().getTime() >= expiresAt) {
      await this.#expire({ ownerId, mediaId, key, directory, metadata });
      throw new MediaStoreError('media_expired');
    }
    let bytes;
    try {
      bytes = await readFile(join(directory, `${key}.bin`));
    } catch (error) {
      if (error?.code === 'ENOENT') throw new MediaStoreError('media_not_found');
      throw error;
    }
    if (
      metadata.mediaId !== mediaId ||
      !STORED_MIME_TYPES.has(metadata.mimeType) ||
      (metadata.mediaKind !== 'image' && metadata.mediaKind !== 'imageMotion') ||
      !Number.isInteger(metadata.width) ||
      !Number.isInteger(metadata.height) ||
      metadata.width <= 0 ||
      metadata.height <= 0 ||
      (metadata.mediaKind === 'imageMotion' &&
        (!Number.isInteger(metadata.durationMilliseconds) ||
          metadata.durationMilliseconds <= 0 ||
          metadata.codec !== 'h264' ||
          metadata.mimeType !== 'video/mp4')) ||
      (metadata.mediaKind === 'image' &&
        !SOURCE_MIME_TYPES.has(metadata.mimeType)) ||
      metadata.sha256 !== digest(bytes)
    ) {
      throw new MediaStoreError('media_integrity_failed');
    }
    return {
      sha256: metadata.sha256,
      mimeType: metadata.mimeType,
      data: bytes,
      format: metadata.format,
      width: metadata.width,
      height: metadata.height,
      mediaKind: metadata.mediaKind,
      durationMilliseconds:
        metadata.mediaKind === 'imageMotion'
          ? metadata.durationMilliseconds
          : null,
      codec: metadata.mediaKind === 'imageMotion' ? metadata.codec : null,
      byteLength: bytes.length,
      isBlackWhite: metadata.isBlackWhite === true,
    };
  }

  async storeProviderOutput({
    ownerId,
    taskId,
    output,
    storageReservationId,
    reserveStorage,
    commitStorage,
    releaseStorage,
  }) {
    if (
      typeof reserveStorage !== 'function' ||
      typeof commitStorage !== 'function' ||
      typeof releaseStorage !== 'function'
    ) {
      throw new TypeError('Provider output storage quota callbacks are required.');
    }
    let bytes;
    let mimeType;
    if (output?.kind === 'base64') {
      mimeType = output.mimeType;
      if (typeof output.data !== 'string' || !/^[A-Za-z0-9+/]*={0,2}$/.test(output.data)) {
        throw new MediaStoreError('provider_output_invalid');
      }
      bytes = Buffer.from(output.data, 'base64');
    } else if (output?.kind === 'remote-url') {
      const downloaded = await this.remoteDownloader.download(output.url);
      mimeType = downloaded.mimeType;
      bytes = downloaded.data;
    } else {
      throw new MediaStoreError('provider_output_invalid');
    }
    const mediaId = `${taskId}-result`;
    await reserveStorage({ mediaId, byteLength: bytes.length });
    let persisted = false;
    try {
      let stored;
      if (output?.mediaKind === 'image_motion') {
        if (
          output.expectedMimeType !== 'video/mp4' ||
          output.expectedCodec !== 'h264' ||
          !Number.isInteger(output.expectedDurationMilliseconds) ||
          output.expectedDurationMilliseconds <= 0 ||
          mimeType !== 'video/mp4'
        ) {
          throw new MediaStoreError('provider_output_invalid');
        }
        const video = probeMp4(bytes, { declaredMimeType: mimeType });
        if (
          video.codec !== output.expectedCodec ||
          Math.abs(
            video.durationMilliseconds - output.expectedDurationMilliseconds,
          ) > 100
        ) {
          throw new MediaStoreError('provider_output_contract_mismatch');
        }
        stored = await this.#putVerifiedMedia({
          ownerId,
          mediaId,
          storageReservationId: storageReservationId ?? mediaId,
          mimeType,
          bytes,
          media: video,
        });
      } else {
        stored = await this.putSource({
          ownerId,
          mediaId,
          mimeType,
          data: bytes,
          storageReservationId: storageReservationId ?? mediaId,
        });
      }
      persisted = true;
      await commitStorage({ mediaId, byteLength: bytes.length });
      return stored;
    } catch (error) {
      if (!persisted) {
        await releaseStorage({ mediaId, byteLength: bytes.length });
      }
      throw error;
    }
  }

  async initializeExpirationSweep() {
    await this.sweepExpired();
  }

  async sweepExpired() {
    this.#clearExpirationTimer();
    await mkdir(this.rootDirectory, { recursive: true, mode: 0o700 });
    const nowMilliseconds = this.now().getTime();
    let nextExpiration = null;
    let retryRequired = false;
    const owners = await readdir(this.rootDirectory, { withFileTypes: true });
    for (const ownerEntry of owners) {
      if (!ownerEntry.isDirectory()) continue;
      const directory = join(this.rootDirectory, ownerEntry.name);
      const entries = await readdir(directory, { withFileTypes: true });
      for (const entry of entries) {
        if (!entry.isFile() || !/^[a-f0-9]{64}\.json$/.test(entry.name)) continue;
        const key = entry.name.slice(0, -5);
        let metadata;
        try {
          metadata = JSON.parse(await readFile(join(directory, entry.name), 'utf8'));
        } catch {
          await this.#deleteMediaFiles({ directory, key });
          continue;
        }
        const expiresAt = Date.parse(metadata.expiresAt);
        if (!Number.isFinite(expiresAt) || expiresAt <= nowMilliseconds) {
          if (
            typeof metadata.ownerId !== 'string' ||
            typeof metadata.mediaId !== 'string' ||
            !Number.isInteger(metadata.size) ||
            metadata.size <= 0
          ) {
            await this.#deleteMediaFiles({ directory, key });
            continue;
          }
          try {
            await this.#expire({
              ownerId: metadata.ownerId,
              mediaId: metadata.mediaId,
              key,
              directory,
              metadata,
            });
          } catch {
            retryRequired = true;
          }
          continue;
        }
        nextExpiration =
          nextExpiration === null ? expiresAt : Math.min(nextExpiration, expiresAt);
      }
    }
    if (retryRequired) {
      nextExpiration = Math.min(
        nextExpiration ?? Number.POSITIVE_INFINITY,
        nowMilliseconds + 60_000,
      );
    }
    if (Number.isFinite(nextExpiration)) this.#scheduleExpiration(nextExpiration);
  }

  close() {
    this.#clearExpirationTimer();
  }

  async #putVerifiedMedia({
    ownerId,
    mediaId,
    storageReservationId,
    mimeType,
    bytes,
    media,
  }) {
    const directory = await this.#ownerDirectory(ownerId);
    const key = digest(mediaId);
    const createdAt = this.now();
    const expiresAt = new Date(
      createdAt.getTime() + this.retentionMilliseconds,
    ).toISOString();
    const metadata = {
      ownerId,
      mediaId,
      storageReservationId,
      mimeType,
      size: bytes.length,
      sha256: digest(bytes),
      mediaKind: media.mediaKind,
      format: media.format,
      width: media.width,
      height: media.height,
      durationMilliseconds: media.durationMilliseconds,
      codec: media.codec,
      isBlackWhite: media.isBlackWhite === true,
      createdAt: createdAt.toISOString(),
      expiresAt,
    };
    await this.#atomicWrite(join(directory, `${key}.bin`), bytes);
    await this.#atomicWrite(
      join(directory, `${key}.json`),
      Buffer.from(JSON.stringify(metadata)),
    );
    this.#scheduleExpiration(expiresAt);
    return {
      mediaId,
      sha256: metadata.sha256,
      mediaKind: metadata.mediaKind,
      width: metadata.width,
      height: metadata.height,
      durationMilliseconds: metadata.durationMilliseconds,
      expiresAt,
    };
  }

  async #ownerDirectory(ownerId) {
    const directory = join(this.rootDirectory, digest(ownerId));
    await mkdir(directory, { recursive: true, mode: 0o700 });
    return directory;
  }

  async #expire({ ownerId, mediaId, key, directory, metadata }) {
    await unlink(join(directory, `${key}.bin`)).catch((error) => {
      if (error?.code !== 'ENOENT') throw error;
    });
    await this.onExpired({
      ownerId,
      mediaId,
      reservationId: metadata.storageReservationId ?? mediaId,
      byteLength: Number(metadata.size ?? 0),
    });
    await unlink(join(directory, `${key}.json`)).catch((error) => {
      if (error?.code !== 'ENOENT') throw error;
    });
  }

  async #deleteMediaFiles({ directory, key }) {
    for (const extension of ['bin', 'json']) {
      await unlink(join(directory, `${key}.${extension}`)).catch((error) => {
        if (error?.code !== 'ENOENT') throw error;
      });
    }
  }

  #scheduleExpiration(value) {
    const expiresAt =
      typeof value === 'string' ? Date.parse(value) : Number(value);
    if (!Number.isFinite(expiresAt)) return;
    if (this.nextExpiration !== null && this.nextExpiration <= expiresAt) return;
    this.#clearExpirationTimer();
    this.nextExpiration = expiresAt;
    const delay = Math.max(0, Math.min(expiresAt - this.now().getTime(), 2_147_483_647));
    this.expirationTimer = setTimeout(() => {
      this.expirationTimer = null;
      this.nextExpiration = null;
      this.sweepExpired().catch(() => {
        this.#scheduleExpiration(this.now().getTime() + 60_000);
      });
    }, delay);
    this.expirationTimer.unref?.();
  }

  #clearExpirationTimer() {
    if (this.expirationTimer) clearTimeout(this.expirationTimer);
    this.expirationTimer = null;
    this.nextExpiration = null;
  }

  async #atomicWrite(destination, bytes) {
    const temporary = `${destination}.${randomUUID()}.tmp`;
    await writeFile(temporary, bytes, { mode: 0o600 });
    await rename(temporary, destination);
  }
}
