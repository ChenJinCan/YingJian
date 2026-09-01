import { inflateSync } from 'node:zlib';

const PNG_SIGNATURE = Buffer.from('89504e470d0a1a0a', 'hex');
const MAX_DIMENSION = 8000;
const MAX_PIXELS = 40_000_000;

class ImageProbeError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
    this.status = 422;
  }
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function validateDimensions(width, height) {
  if (
    !Number.isInteger(width) ||
    !Number.isInteger(height) ||
    width <= 0 ||
    height <= 0 ||
    width > MAX_DIMENSION ||
    height > MAX_DIMENSION ||
    width * height > MAX_PIXELS
  ) {
    throw new ImageProbeError('image_dimensions_invalid');
  }
}

function probePng(bytes, { inspectBlackWhite = true } = {}) {
  let offset = PNG_SIGNATURE.length;
  let header = null;
  const compressed = [];
  let ended = false;
  while (offset + 12 <= bytes.length) {
    const length = bytes.readUInt32BE(offset);
    const end = offset + 12 + length;
    if (end > bytes.length) {
      throw new ImageProbeError('image_header_invalid');
    }
    const typeBytes = bytes.subarray(offset + 4, offset + 8);
    const type = typeBytes.toString('ascii');
    const data = bytes.subarray(offset + 8, offset + 8 + length);
    const expectedCrc = bytes.readUInt32BE(offset + 8 + length);
    if (crc32(Buffer.concat([typeBytes, data])) !== expectedCrc) {
      throw new ImageProbeError('image_header_invalid');
    }
    if (type === 'IHDR') {
      if (header || length !== 13) {
        throw new ImageProbeError('image_header_invalid');
      }
      header = {
        width: data.readUInt32BE(0),
        height: data.readUInt32BE(4),
        bitDepth: data[8],
        colorType: data[9],
        compression: data[10],
        filter: data[11],
        interlace: data[12],
      };
    } else if (type === 'IDAT') {
      compressed.push(data);
    } else if (type === 'IEND') {
      ended = true;
      offset = end;
      break;
    }
    offset = end;
  }
  if (!header || !ended || offset !== bytes.length || compressed.length === 0) {
    throw new ImageProbeError('image_header_invalid');
  }
  validateDimensions(header.width, header.height);
  if (
    header.bitDepth !== 8 ||
    ![0, 2, 4, 6].includes(header.colorType) ||
    header.compression !== 0 ||
    header.filter !== 0 ||
    header.interlace !== 0
  ) {
    throw new ImageProbeError('image_encoding_unsupported');
  }
  if (!inspectBlackWhite) {
    return {
      format: 'png',
      mimeType: 'image/png',
      ...header,
      isBlackWhite: false,
    };
  }
  const channels = { 0: 1, 2: 3, 4: 2, 6: 4 }[header.colorType];
  const stride = header.width * channels;
  const expectedBytes = (stride + 1) * header.height;
  let inflated;
  try {
    inflated = inflateSync(Buffer.concat(compressed), {
      maxOutputLength: expectedBytes,
    });
  } catch {
    throw new ImageProbeError('image_decode_failed');
  }
  if (inflated.length !== expectedBytes) {
    throw new ImageProbeError('image_decode_failed');
  }
  const pixels = Buffer.alloc(stride * header.height);
  for (let y = 0; y < header.height; y += 1) {
    const rowStart = y * (stride + 1);
    const filter = inflated[rowStart];
    if (filter > 4) {
      throw new ImageProbeError('image_decode_failed');
    }
    for (let x = 0; x < stride; x += 1) {
      const raw = inflated[rowStart + 1 + x];
      const outputOffset = y * stride + x;
      const left = x >= channels ? pixels[outputOffset - channels] : 0;
      const up = y > 0 ? pixels[outputOffset - stride] : 0;
      const upLeft = y > 0 && x >= channels ? pixels[outputOffset - stride - channels] : 0;
      let reconstructed = raw;
      if (filter === 1) reconstructed += left;
      if (filter === 2) reconstructed += up;
      if (filter === 3) reconstructed += Math.floor((left + up) / 2);
      if (filter === 4) {
        const prediction = left + up - upLeft;
        const leftDistance = Math.abs(prediction - left);
        const upDistance = Math.abs(prediction - up);
        const diagonalDistance = Math.abs(prediction - upLeft);
        reconstructed +=
          leftDistance <= upDistance && leftDistance <= diagonalDistance
            ? left
            : upDistance <= diagonalDistance
              ? up
              : upLeft;
      }
      pixels[outputOffset] = reconstructed & 0xff;
    }
  }
  let isBlackWhite = header.colorType === 0 || header.colorType === 2;
  if (isBlackWhite) {
    for (let offset = 0; offset < pixels.length; offset += channels) {
      const value = pixels[offset];
      if (value !== 0 && value !== 255) {
        isBlackWhite = false;
        break;
      }
      if (channels === 3 && (pixels[offset + 1] !== value || pixels[offset + 2] !== value)) {
        isBlackWhite = false;
        break;
      }
    }
  }
  return { format: 'png', mimeType: 'image/png', ...header, isBlackWhite };
}

function probeJpeg(bytes) {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) {
    throw new ImageProbeError('image_header_invalid');
  }
  let offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 0xff) {
      offset += 1;
      continue;
    }
    const marker = bytes[offset + 1];
    offset += 2;
    if (marker === 0xd9 || marker === 0xda) break;
    const length = bytes.readUInt16BE(offset);
    if (length < 2 || offset + length > bytes.length) {
      throw new ImageProbeError('image_header_invalid');
    }
    if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb].includes(marker)) {
      if (length < 7) throw new ImageProbeError('image_header_invalid');
      const height = bytes.readUInt16BE(offset + 3);
      const width = bytes.readUInt16BE(offset + 5);
      validateDimensions(width, height);
      return {
        format: 'jpeg',
        mimeType: 'image/jpeg',
        width,
        height,
        isBlackWhite: false,
      };
    }
    offset += length;
  }
  throw new ImageProbeError('image_header_invalid');
}

function probeWebp(bytes) {
  if (
    bytes.length < 30 ||
    bytes.toString('ascii', 0, 4) !== 'RIFF' ||
    bytes.toString('ascii', 8, 12) !== 'WEBP'
  ) {
    throw new ImageProbeError('image_header_invalid');
  }
  const declaredSize = bytes.readUInt32LE(4) + 8;
  if (declaredSize !== bytes.length) {
    throw new ImageProbeError('image_header_invalid');
  }
  const kind = bytes.toString('ascii', 12, 16);
  let width;
  let height;
  if (kind === 'VP8X') {
    width = 1 + bytes.readUIntLE(24, 3);
    height = 1 + bytes.readUIntLE(27, 3);
  } else {
    throw new ImageProbeError('image_encoding_unsupported');
  }
  validateDimensions(width, height);
  return {
    format: 'webp',
    mimeType: 'image/webp',
    width,
    height,
    isBlackWhite: false,
  };
}

function probeBmp(bytes) {
  if (bytes.length < 54 || bytes.toString('ascii', 0, 2) !== 'BM') {
    throw new ImageProbeError('image_header_invalid');
  }
  if (bytes.readUInt32LE(2) !== bytes.length || bytes.readUInt32LE(14) < 40) {
    throw new ImageProbeError('image_header_invalid');
  }
  const width = Math.abs(bytes.readInt32LE(18));
  const height = Math.abs(bytes.readInt32LE(22));
  validateDimensions(width, height);
  return {
    format: 'bmp',
    mimeType: 'image/bmp',
    width,
    height,
    isBlackWhite: false,
  };
}

export function probeImage(
  bytes,
  { declaredMimeType, inspectBlackWhite = true },
) {
  if (!Buffer.isBuffer(bytes) || bytes.length === 0) {
    throw new ImageProbeError('image_header_invalid');
  }
  let result;
  if (bytes.subarray(0, 8).equals(PNG_SIGNATURE)) {
    result = probePng(bytes, { inspectBlackWhite });
  } else if (bytes[0] === 0xff && bytes[1] === 0xd8) {
    result = probeJpeg(bytes);
  } else if (bytes.toString('ascii', 0, 4) === 'RIFF') {
    result = probeWebp(bytes);
  } else if (bytes.toString('ascii', 0, 2) === 'BM') {
    result = probeBmp(bytes);
  } else {
    throw new ImageProbeError('image_header_invalid');
  }
  if (result.mimeType !== declaredMimeType) {
    throw new ImageProbeError('image_mime_mismatch');
  }
  return {
    format: result.format,
    mimeType: result.mimeType,
    width: result.width,
    height: result.height,
    byteLength: bytes.length,
    isBlackWhite: result.isBlackWhite,
  };
}
