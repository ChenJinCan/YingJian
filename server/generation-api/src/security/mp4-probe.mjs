const MAX_DIMENSION = 4096;
const MAX_PIXELS = 8_500_000;
const MAX_DURATION_MILLISECONDS = 30_000;

class Mp4ProbeError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
    this.status = 422;
  }
}

function boxes(bytes, start, end) {
  const result = [];
  let offset = start;
  while (offset < end) {
    if (offset + 8 > end) throw new Mp4ProbeError('video_container_invalid');
    const size32 = bytes.readUInt32BE(offset);
    const type = bytes.toString('ascii', offset + 4, offset + 8);
    if (!/^[\x20-\x7e]{4}$/.test(type)) {
      throw new Mp4ProbeError('video_container_invalid');
    }
    let headerSize = 8;
    let size = size32;
    if (size32 === 1) {
      if (offset + 16 > end) throw new Mp4ProbeError('video_container_invalid');
      const extended = bytes.readBigUInt64BE(offset + 8);
      if (extended > BigInt(Number.MAX_SAFE_INTEGER)) {
        throw new Mp4ProbeError('video_container_invalid');
      }
      headerSize = 16;
      size = Number(extended);
    } else if (size32 === 0) {
      size = end - offset;
    }
    if (size < headerSize || offset + size > end) {
      throw new Mp4ProbeError('video_container_invalid');
    }
    result.push({
      type,
      start: offset,
      dataStart: offset + headerSize,
      end: offset + size,
    });
    offset += size;
  }
  return result;
}

function singleChild(bytes, parent, type) {
  const matches = boxes(bytes, parent.dataStart, parent.end).filter(
    (box) => box.type === type,
  );
  if (matches.length !== 1) throw new Mp4ProbeError('video_container_invalid');
  return matches[0];
}

function mediaDuration(bytes, mdhd) {
  const version = bytes[mdhd.dataStart];
  let timescale;
  let duration;
  if (version === 0) {
    if (mdhd.dataStart + 20 > mdhd.end) {
      throw new Mp4ProbeError('video_container_invalid');
    }
    timescale = bytes.readUInt32BE(mdhd.dataStart + 12);
    duration = bytes.readUInt32BE(mdhd.dataStart + 16);
  } else if (version === 1) {
    if (mdhd.dataStart + 32 > mdhd.end) {
      throw new Mp4ProbeError('video_container_invalid');
    }
    timescale = bytes.readUInt32BE(mdhd.dataStart + 20);
    const duration64 = bytes.readBigUInt64BE(mdhd.dataStart + 24);
    if (duration64 > BigInt(Number.MAX_SAFE_INTEGER)) {
      throw new Mp4ProbeError('video_duration_invalid');
    }
    duration = Number(duration64);
  } else {
    throw new Mp4ProbeError('video_container_invalid');
  }
  if (timescale === 0 || duration === 0) {
    throw new Mp4ProbeError('video_duration_invalid');
  }
  const durationMilliseconds = Math.round((duration * 1000) / timescale);
  if (
    !Number.isSafeInteger(durationMilliseconds) ||
    durationMilliseconds <= 0 ||
    durationMilliseconds > MAX_DURATION_MILLISECONDS
  ) {
    throw new Mp4ProbeError('video_duration_invalid');
  }
  return durationMilliseconds;
}

function videoCodec(bytes, mdia) {
  const minf = singleChild(bytes, mdia, 'minf');
  const stbl = singleChild(bytes, minf, 'stbl');
  const stsd = singleChild(bytes, stbl, 'stsd');
  if (stsd.dataStart + 16 > stsd.end) {
    throw new Mp4ProbeError('video_codec_invalid');
  }
  const entryCount = bytes.readUInt32BE(stsd.dataStart + 4);
  if (entryCount < 1) throw new Mp4ProbeError('video_codec_invalid');
  const entries = boxes(bytes, stsd.dataStart + 8, stsd.end);
  if (entries.length !== entryCount) {
    throw new Mp4ProbeError('video_codec_invalid');
  }
  if (!entries.some((entry) => entry.type === 'avc1' || entry.type === 'avc3')) {
    throw new Mp4ProbeError('video_codec_unsupported');
  }
  return 'h264';
}

function videoTrack(bytes, trak) {
  const tkhd = singleChild(bytes, trak, 'tkhd');
  const mdia = singleChild(bytes, trak, 'mdia');
  const hdlr = singleChild(bytes, mdia, 'hdlr');
  if (hdlr.dataStart + 12 > hdlr.end) {
    throw new Mp4ProbeError('video_container_invalid');
  }
  if (bytes.toString('ascii', hdlr.dataStart + 8, hdlr.dataStart + 12) !== 'vide') {
    return null;
  }
  if (tkhd.end - tkhd.dataStart < 8) {
    throw new Mp4ProbeError('video_dimensions_invalid');
  }
  const widthFixed = bytes.readUInt32BE(tkhd.end - 8);
  const heightFixed = bytes.readUInt32BE(tkhd.end - 4);
  const width = widthFixed / 65536;
  const height = heightFixed / 65536;
  if (
    !Number.isInteger(width) ||
    !Number.isInteger(height) ||
    width <= 0 ||
    height <= 0 ||
    width > MAX_DIMENSION ||
    height > MAX_DIMENSION ||
    width * height > MAX_PIXELS
  ) {
    throw new Mp4ProbeError('video_dimensions_invalid');
  }
  const durationMilliseconds = mediaDuration(bytes, singleChild(bytes, mdia, 'mdhd'));
  return {
    width,
    height,
    durationMilliseconds,
    codec: videoCodec(bytes, mdia),
  };
}

export function probeMp4(bytes, { declaredMimeType } = {}) {
  if (!Buffer.isBuffer(bytes) || bytes.length < 24) {
    throw new Mp4ProbeError('video_container_invalid');
  }
  if (declaredMimeType !== 'video/mp4') {
    throw new Mp4ProbeError('video_mime_mismatch');
  }
  const topLevel = boxes(bytes, 0, bytes.length);
  const ftyp = topLevel.find((box) => box.type === 'ftyp');
  const moov = topLevel.find((box) => box.type === 'moov');
  const mdat = topLevel.find((box) => box.type === 'mdat');
  if (!ftyp || !moov || !mdat || ftyp.dataStart + 8 > ftyp.end) {
    throw new Mp4ProbeError('video_container_invalid');
  }
  const majorBrand = bytes.toString('ascii', ftyp.dataStart, ftyp.dataStart + 4);
  if (!/^[A-Za-z0-9 ]{4}$/.test(majorBrand)) {
    throw new Mp4ProbeError('video_container_invalid');
  }
  const tracks = boxes(bytes, moov.dataStart, moov.end)
    .filter((box) => box.type === 'trak')
    .map((trak) => videoTrack(bytes, trak))
    .filter((track) => track !== null);
  if (tracks.length !== 1) throw new Mp4ProbeError('video_track_invalid');
  return {
    format: 'mp4',
    mimeType: 'video/mp4',
    mediaKind: 'imageMotion',
    byteLength: bytes.length,
    ...tracks[0],
  };
}

export { Mp4ProbeError };
