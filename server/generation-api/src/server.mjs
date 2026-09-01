import { createServer } from 'node:http';

import { createNodeHttpListener } from './http/node-http-listener.mjs';
import { createGenerationRuntime } from './runtime.mjs';

const host = process.env.GENERATION_HOST || '127.0.0.1';
const port = Number(process.env.GENERATION_PORT || 8787);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('GENERATION_PORT must be an integer from 1 to 65535.');
}
if (
  process.env.GENERATION_ALLOW_SHARED_BEARER_AUTH === 'true' &&
  host !== '127.0.0.1' &&
  host !== '::1' &&
  host !== 'localhost'
) {
  throw new Error('Shared bearer authentication may bind only to loopback.');
}

const { handler } = await createGenerationRuntime();
const server = createServer(createNodeHttpListener(handler));
server.listen(port, host, () => {
  process.stdout.write(`Generation API listening on ${host}:${port}\n`);
});
