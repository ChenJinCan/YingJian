import { readFile } from 'node:fs/promises';

import { FilePrivateMediaStore } from './infrastructure/file-private-media-store.mjs';

const [ownerId, mediaId, mimeType, filePath] = process.argv.slice(2);
if (!ownerId || !mediaId || !mimeType || !filePath) {
  throw new Error(
    'Usage: npm run import-media -- <owner-id> <media-id> <mime-type> <file-path>',
  );
}
if (!process.env.GENERATION_MEDIA_DIRECTORY) {
  throw new Error('GENERATION_MEDIA_DIRECTORY is required.');
}
const store = new FilePrivateMediaStore({
  rootDirectory: process.env.GENERATION_MEDIA_DIRECTORY,
  remoteDownloader: {
    download: async () => {
      throw new Error('Remote downloads are unavailable in the import command.');
    },
  },
  onExpired: async () => {},
});
const result = await store.putSource({
  ownerId,
  mediaId,
  mimeType,
  data: await readFile(filePath),
});
process.stdout.write(`${JSON.stringify(result)}\n`);
