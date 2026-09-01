const MAX_REQUEST_BYTES = 25 * 1024 * 1024;

async function readRequestBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_REQUEST_BYTES) {
      const error = new Error('request_too_large');
      error.status = 413;
      throw error;
    }
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

export function createNodeHttpListener(handler) {
  if (typeof handler !== 'function') {
    throw new TypeError('handler is required.');
  }
  return async function nodeHttpListener(incoming, outgoing) {
    try {
      const method = incoming.method ?? 'GET';
      const body = method === 'GET' || method === 'HEAD' ? null : await readRequestBody(incoming);
      const request = new Request(`http://localhost${incoming.url ?? '/'}`, {
        method,
        headers: incoming.headers,
        ...(body && body.length > 0 ? { body } : {}),
      });
      const response = await handler(request);
      outgoing.statusCode = response.status;
      for (const [name, value] of response.headers) {
        outgoing.setHeader(name, value);
      }
      outgoing.end(Buffer.from(await response.arrayBuffer()));
    } catch (error) {
      outgoing.statusCode = error?.status === 413 ? 413 : 500;
      outgoing.setHeader('content-type', 'application/json');
      outgoing.setHeader('cache-control', 'no-store');
      outgoing.end(
        JSON.stringify({
          error: {
            code: error?.status === 413 ? 'request_too_large' : 'internal_error',
          },
        }),
      );
    }
  };
}
