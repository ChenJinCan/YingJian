import { createHash } from 'node:crypto';

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

function integerMetadata(value) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : null;
}

function mediaMetadata(object) {
  const metadata = object?.customMetadata ?? {};
  const size = integerMetadata(metadata.size);
  const width = integerMetadata(metadata.width);
  const height = integerMetadata(metadata.height);
  return {
    ownerId: metadata.ownerId,
    mediaId: metadata.mediaId,
    storageReservationId: metadata.storageReservationId,
    mimeType: metadata.mimeType ?? object?.httpMetadata?.contentType,
    size,
    sha256: metadata.sha256,
    format: metadata.format,
    mediaKind: metadata.mediaKind,
    width,
    height,
    durationMilliseconds: integerMetadata(metadata.durationMilliseconds),
    codec: metadata.codec || null,
    isBlackWhite: metadata.isBlackWhite === 'true',
    createdAt: metadata.createdAt,
    expiresAt: metadata.expiresAt,
  };
}

/** Private R2 media store. No bucket URL or signed R2 credential is exposed. */
export class R2PrivateMediaStore {
  constructor({
    bucket,
    remoteDownloader,
    onExpired,
    retentionMilliseconds = MAX_RETENTION_MILLISECONDS,
    now = () => new Date(),
  }) {
    if (
      !bucket ||
      typeof bucket.put !== 'function' ||
      typeof bucket.get !== 'function' ||
      typeof bucket.delete !== 'function' ||
      typeof bucket.list !== 'function'
    ) {
      throw new TypeError('bucket is required.');
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
    this.bucket = bucket;
    this.remoteDownloader = remoteDownloader;
    this.onExpired = onExpired;
    this.retentionMilliseconds = retentionMilliseconds;
    this.now = now;
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
    // Upload validation only needs trusted dimensions/format. Full PNG pixel
    // expansion is deferred until the media is explicitly used as a mask.
    const image = probeImage(bytes, {
      declaredMimeType: mimeType,
      inspectBlackWhite: false,
    });
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

  async #putVerifiedMedia({
    ownerId,
    mediaId,
    storageReservationId,
    mimeType,
    bytes,
    media,
  }) {
    const createdAt = this.now();
    const expiresAt = new Date(
      createdAt.getTime() + this.retentionMilliseconds,
    ).toISOString();
    const sha256 = digest(bytes);
    const stored = await this.bucket.put(this.#key(ownerId, mediaId), bytes, {
      httpMetadata: {
        contentType: mimeType,
        cacheControl: 'no-store',
      },
      customMetadata: {
        ownerId,
        mediaId,
        storageReservationId,
        mimeType,
        size: String(bytes.length),
        sha256,
        mediaKind: media.mediaKind,
        format: media.format,
        width: String(media.width),
        height: String(media.height),
        durationMilliseconds:
          media.durationMilliseconds === null
            ? ''
            : String(media.durationMilliseconds),
        codec: media.codec ?? '',
        isBlackWhite: String(media.isBlackWhite === true),
        createdAt: createdAt.toISOString(),
        expiresAt,
      },
      sha256,
      storageClass: 'Standard',
    });
    if (!stored) throw new MediaStoreError('media_persist_failed');
    return {
      mediaId,
      sha256,
      mediaKind: media.mediaKind,
      width: media.width,
      height: media.height,
      durationMilliseconds: media.durationMilliseconds,
      expiresAt,
    };
  }

  async resolveInput({ ownerId, mediaId, purpose = 'source' }) {
    const media = await this.read({ ownerId, mediaId });
    let isBlackWhite = media.isBlackWhite;
    if (purpose === 'mask') {
      isBlackWhite = probeImage(media.data, {
        declaredMimeType: media.mimeType,
        inspectBlackWhite: true,
      }).isBlackWhite;
    }
    return {
      sha256: media.sha256,
      providerUri: `data:${media.mimeType};base64,${media.data.toString('base64')}`,
      format: media.format,
      width: media.width,
      height: media.height,
      byteLength: media.byteLength,
      isBlackWhite,
    };
  }

  async read({ ownerId, mediaId }) {
    assertIdentifier(ownerId);
    assertIdentifier(mediaId);
    const key = this.#key(ownerId, mediaId);
    const object = await this.bucket.get(key);
    if (!object?.body) throw new MediaStoreError('media_not_found');
    const metadata = mediaMetadata(object);
    if (metadata.ownerId !== ownerId || metadata.mediaId !== mediaId) {
      throw new MediaStoreError('media_integrity_failed');
    }
    const expiration = Date.parse(metadata.expiresAt);
    if (!Number.isFinite(expiration) || this.now().getTime() >= expiration) {
      await this.#expireObject({ key, metadata });
      throw new MediaStoreError('media_expired');
    }
    const bytes = Buffer.from(await object.arrayBuffer());
    if (
      !STORED_MIME_TYPES.has(metadata.mimeType) ||
      metadata.size !== bytes.length ||
      metadata.sha256 !== digest(bytes) ||
      (metadata.mediaKind !== 'image' && metadata.mediaKind !== 'imageMotion') ||
      !Number.isInteger(metadata.width) ||
      !Number.isInteger(metadata.height) ||
      metadata.width <= 0 ||
      metadata.height <= 0 ||
      typeof metadata.format !== 'string' ||
      (metadata.mediaKind === 'imageMotion' &&
        (!Number.isInteger(metadata.durationMilliseconds) ||
          metadata.durationMilliseconds <= 0 ||
          metadata.codec !== 'h264' ||
          metadata.mimeType !== 'video/mp4')) ||
      (metadata.mediaKind === 'image' &&
        !SOURCE_MIME_TYPES.has(metadata.mimeType))
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
      isBlackWhite: metadata.isBlackWhite,
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
      if (
        typeof output.data !== 'string' ||
        !/^[A-Za-z0-9+/]*={0,2}$/.test(output.data)
      ) {
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
    if (bytes.length === 0 || bytes.length > MAX_MEDIA_BYTES) {
      throw new MediaStoreError('media_size_invalid');
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
    return this.sweepExpired();
  }

  async sweepExpired() {
    let cursor;
    do {
      const page = await this.bucket.list({
        prefix: 'media/',
        limit: 1000,
        ...(cursor ? { cursor } : {}),
        include: ['customMetadata'],
      });
      for (const object of page.objects ?? []) {
        const metadata = mediaMetadata(object);
        const expiration = Date.parse(metadata.expiresAt);
        if (!Number.isFinite(expiration)) {
          await this.bucket.delete(object.key);
          continue;
        }
        if (this.now().getTime() >= expiration) {
          await this.#expireObject({ key: object.key, metadata });
        }
      }
      cursor = page.truncated ? page.cursor : undefined;
    } while (cursor);
  }

  close() {}

  #key(ownerId, mediaId) {
    return `media/${digest(ownerId)}/${digest(mediaId)}`;
  }

  async #expireObject({ key, metadata }) {
    if (
      typeof metadata.ownerId !== 'string' ||
      typeof metadata.mediaId !== 'string' ||
      !Number.isInteger(metadata.size) ||
      metadata.size <= 0
    ) {
      await this.bucket.delete(key);
      return;
    }
    await this.onExpired({
      ownerId: metadata.ownerId,
      mediaId: metadata.mediaId,
      reservationId: metadata.storageReservationId ?? metadata.mediaId,
      byteLength: metadata.size,
    });
    await this.bucket.delete(key);
  }
}
