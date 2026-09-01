class CapabilityMediaError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
    this.status = 422;
  }
}

const MEBIBYTE = 1024 * 1024;

const SOURCE_POLICIES = Object.freeze({
  optimizeAiRepair: {
    maxBytes: 10 * MEBIBYTE,
    maxBase64Bytes: 10 * MEBIBYTE,
    minDimension: 10,
    maxDimension: 5000,
    maxAspectRatio: 4,
    allowedFormats: new Set(['jpeg', 'png', 'bmp']),
  },
  optimizeOldPhoto: {
    maxBytes: 10 * MEBIBYTE,
    minDimension: 10,
    maxDimension: 8000,
    maxAspectRatio: 8,
    allowedFormats: new Set(['jpeg', 'png', 'webp', 'bmp']),
  },
  styleAiRedraw: {
    maxBytes: 20 * MEBIBYTE,
    minDimension: 240,
    maxDimension: 8000,
    maxAspectRatio: 8,
    allowedFormats: new Set(['jpeg', 'png', 'webp', 'bmp']),
  },
  cleanupRemovePasserby: {
    maxBytes: 10 * MEBIBYTE,
    minDimension: 512,
    maxDimension: 4096,
    maxAspectRatio: 8,
    allowedFormats: new Set(['jpeg', 'png', 'webp', 'bmp']),
    requiresMask: true,
  },
  cleanupBrushRemove: {
    maxBytes: 10 * MEBIBYTE,
    minDimension: 512,
    maxDimension: 4096,
    maxAspectRatio: 8,
    allowedFormats: new Set(['jpeg', 'png', 'webp', 'bmp']),
    requiresMask: true,
  },
  motionAiNatural: {
    maxBytes: 20 * MEBIBYTE,
    minDimension: 240,
    maxDimension: 8000,
    maxAspectRatio: 8,
    allowedFormats: new Set(['jpeg', 'png', 'webp', 'bmp']),
  },
});

function validateMetadata(media, prefix, policy) {
  if (
    !media ||
    !Number.isInteger(media.byteLength) ||
    !Number.isInteger(media.width) ||
    !Number.isInteger(media.height) ||
    media.byteLength <= 0 ||
    media.width <= 0 ||
    media.height <= 0 ||
    typeof media.format !== 'string'
  ) {
    throw new CapabilityMediaError(`${prefix}_media_invalid`);
  }
  if (media.byteLength > policy.maxBytes) {
    throw new CapabilityMediaError(`${prefix}_media_too_large`);
  }
  if (
    policy.maxBase64Bytes &&
    Math.ceil(media.byteLength / 3) * 4 > policy.maxBase64Bytes
  ) {
    throw new CapabilityMediaError(`${prefix}_media_too_large`);
  }
  if (policy.allowedFormats && !policy.allowedFormats.has(media.format)) {
    throw new CapabilityMediaError(`${prefix}_format_unsupported`);
  }
  if (
    media.width < policy.minDimension ||
    media.height < policy.minDimension ||
    media.width > policy.maxDimension ||
    media.height > policy.maxDimension ||
    Math.max(media.width, media.height) / Math.min(media.width, media.height) >
      policy.maxAspectRatio
  ) {
    throw new CapabilityMediaError(`${prefix}_dimensions_unsupported`);
  }
}

export function validateCapabilityMedia({ capability, source, mask = null }) {
  const policy = SOURCE_POLICIES[capability];
  if (!policy) {
    throw new CapabilityMediaError('unsupported_capability');
  }
  validateMetadata(source, 'source', policy);
  if (!policy.requiresMask) {
    return;
  }
  validateMetadata(mask, 'mask', policy);
  if (mask.format !== 'png') {
    throw new CapabilityMediaError('mask_png_required');
  }
  if (mask.width !== source.width || mask.height !== source.height) {
    throw new CapabilityMediaError('mask_dimensions_mismatch');
  }
  if (mask.isBlackWhite !== true) {
    throw new CapabilityMediaError('mask_black_white_required');
  }
}

export { CapabilityMediaError };
