import { createCloudflareGenerationRuntime } from './runtime.mjs';

const runtimeByEnvironment = new WeakMap();

function runtimeFor(env) {
  let runtime = runtimeByEnvironment.get(env);
  if (!runtime) {
    runtime = createCloudflareGenerationRuntime({ env });
    runtimeByEnvironment.set(env, runtime);
  }
  return runtime;
}

function json(status, body) {
  return Response.json(body, {
    status,
    headers: {
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    },
  });
}

function hardened(response) {
  const headers = new Headers(response.headers);
  headers.set('x-content-type-options', 'nosniff');
  headers.set('referrer-policy', 'no-referrer');
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

const MAX_RATE_LIMIT_BODY_LENGTH = 16 * 1024;
const INVALID_RATE_LIMIT_IDENTITY = 'invalid-identity';

const RATE_LIMITED_PATHS = new Map([
  [
    '/v1/installation-challenges',
    {
      binding: 'REGISTRATION_RATE_LIMITER',
      field: 'keyId',
      isValid: (value) =>
        typeof value === 'string' && /^[a-f0-9]{64}$/.test(value),
      errorCode: 'registration_rate_limited',
    },
  ],
  [
    '/v1/installations',
    {
      binding: 'REGISTRATION_RATE_LIMITER',
      field: 'keyId',
      isValid: (value) =>
        typeof value === 'string' && /^[a-f0-9]{64}$/.test(value),
      errorCode: 'registration_rate_limited',
    },
  ],
  [
    '/v1/generation-session-challenges',
    {
      binding: 'SESSION_RATE_LIMITER',
      field: 'installationId',
      isValid: (value) =>
        typeof value === 'string' &&
        /^[A-Za-z0-9_-]{16,128}$/.test(value),
      errorCode: 'session_rate_limited',
    },
  ],
  [
    '/v1/generation-sessions',
    {
      binding: 'SESSION_RATE_LIMITER',
      field: 'installationId',
      isValid: (value) =>
        typeof value === 'string' &&
        /^[A-Za-z0-9_-]{16,128}$/.test(value),
      errorCode: 'session_rate_limited',
    },
  ],
]);

async function rateLimitIdentity(request, descriptor) {
  const contentLength = Number(request.headers.get('content-length') ?? 0);
  if (
    Number.isFinite(contentLength) &&
    contentLength > MAX_RATE_LIMIT_BODY_LENGTH
  ) {
    return INVALID_RATE_LIMIT_IDENTITY;
  }
  try {
    const text = await request.clone().text();
    if (text.length === 0 || text.length > MAX_RATE_LIMIT_BODY_LENGTH) {
      return INVALID_RATE_LIMIT_IDENTITY;
    }
    const body = JSON.parse(text);
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      return INVALID_RATE_LIMIT_IDENTITY;
    }
    const value = body[descriptor.field];
    return descriptor.isValid(value) ? value : INVALID_RATE_LIMIT_IDENTITY;
  } catch {
    return INVALID_RATE_LIMIT_IDENTITY;
  }
}

async function identityRateLimitResponse(request, env) {
  const pathname = new URL(request.url).pathname;
  if (request.method !== 'POST') return null;
  const descriptor = RATE_LIMITED_PATHS.get(pathname);
  if (!descriptor) return null;

  const limiter = env[descriptor.binding];
  if (typeof limiter?.limit !== 'function') {
    return json(503, { error: { code: 'service_not_configured' } });
  }
  try {
    const key = await rateLimitIdentity(request, descriptor);
    const result = await limiter.limit({ key });
    return result?.success === true
      ? null
      : json(429, { error: { code: descriptor.errorCode } });
  } catch {
    return json(503, { error: { code: 'service_not_configured' } });
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/healthz') {
      return request.method === 'GET'
        ? json(200, { status: 'ok' })
        : json(405, { error: { code: 'method_not_allowed' } });
    }
    const rateLimited = await identityRateLimitResponse(request, env);
    if (rateLimited) return rateLimited;
    let runtime;
    try {
      runtime = runtimeFor(env);
    } catch {
      return json(503, { error: { code: 'service_not_configured' } });
    }
    const sessionResponse = await runtime.sessionSecurity.handleRequest(request);
    if (sessionResponse) return hardened(sessionResponse);
    return hardened(await runtime.handler(request));
  },

  async scheduled(_controller, env, ctx) {
    const runtime = runtimeFor(env);
    ctx.waitUntil(
      Promise.all([
        runtime.mediaStore.sweepExpired(),
        runtime.sessionSecurity.sweepExpired(),
      ]),
    );
  },
};

export { runtimeFor };
