function box(type, ...payloads) {
  const payload = Buffer.concat(payloads);
  const header = Buffer.alloc(8);
  header.writeUInt32BE(header.length + payload.length, 0);
  header.write(type, 4, 4, 'ascii');
  return Buffer.concat([header, payload]);
}

export function mp4Fixture({
  width = 1280,
  height = 720,
  durationMilliseconds = 3000,
  codec = 'avc1',
} = {}) {
  const tkhd = Buffer.alloc(84);
  tkhd.writeUInt32BE(width * 65536, tkhd.length - 8);
  tkhd.writeUInt32BE(height * 65536, tkhd.length - 4);

  const mdhd = Buffer.alloc(24);
  mdhd.writeUInt32BE(1000, 12);
  mdhd.writeUInt32BE(durationMilliseconds, 16);

  const hdlr = Buffer.alloc(24);
  hdlr.write('vide', 8, 4, 'ascii');

  const entryCount = Buffer.alloc(4);
  entryCount.writeUInt32BE(1);
  const stsd = box(
    'stsd',
    Buffer.alloc(4),
    entryCount,
    box(codec),
  );
  const stbl = box('stbl', stsd);
  const minf = box('minf', stbl);
  const mdia = box('mdia', box('mdhd', mdhd), box('hdlr', hdlr), minf);
  const trak = box('trak', box('tkhd', tkhd), mdia);
  const moov = box('moov', trak);
  const ftyp = box('ftyp', Buffer.from('isom\0\0\0\0isom', 'binary'));
  const mdat = box('mdat', Buffer.from([0]));
  return Buffer.concat([ftyp, moov, mdat]);
}
