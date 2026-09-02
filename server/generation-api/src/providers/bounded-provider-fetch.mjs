import { ProviderError } from './provider-error.mjs';

export class ProviderConcurrencyGate {
  constructor({ maximumConcurrent }) {
    if (!Number.isInteger(maximumConcurrent) || maximumConcurrent <= 0) {
      throw new TypeError('maximumConcurrent must be a positive integer.');
    }
    this.maximumConcurrent = maximumConcurrent;
    this.active = 0;
    this.queue = [];
  }

  async acquire() {
    if (this.active >= this.maximumConcurrent) {
      await new Promise((resolve) =>
        this.queue.push(() => {
          this.active += 1;
          resolve();
        }),
      );
    } else {
      this.active += 1;
    }
    let released = false;
    return () => {
      if (released) return;
      released = true;
      this.active -= 1;
      this.queue.shift()?.();
    };
  }
}

const defaultConcurrencyGate = new ProviderConcurrencyGate({ maximumConcurrent: 32 });

async function executeProviderJson({
  fetchImpl,
  url,
  init,
  timeoutMilliseconds,
  maxResponseBytes,
}) {
  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(new Error('provider_timeout')),
    timeoutMilliseconds,
  );
  try {
    let response;
    try {
      response = await fetchImpl(url, {
        ...init,
        // Cloudflare Workers only support `follow` and `manual`. Keep redirects
        // manual so provider responses cannot move a credentialed request to a
        // different origin, then reject every redirect below.
        redirect: 'manual',
        signal: controller.signal,
      });
    } catch {
      if (controller.signal.aborted) {
        throw new ProviderError('Provider request timed out.', {
          code: 'provider_timeout',
          status: 504,
          billingDisposition: 'hold',
        });
      }
      throw new ProviderError('Provider network request failed.', {
        code: 'provider_network_error',
        billingDisposition: 'hold',
      });
    }

    if (response.status >= 300 && response.status < 400) {
      throw new ProviderError('Provider redirects are forbidden.', {
        code: 'provider_redirect_forbidden',
        billingDisposition: 'hold',
      });
    }

    const contentLength = Number(response.headers.get('content-length') ?? 0);
    if (contentLength > maxResponseBytes) {
      throw new ProviderError('Provider response exceeded its maximum size.', {
        code: 'provider_response_too_large',
        billingDisposition: 'hold',
      });
    }
    const chunks = [];
    let total = 0;
    try {
      if (response.body) {
        const reader = response.body.getReader();
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          total += value.byteLength;
          if (total > maxResponseBytes) {
            await reader.cancel();
            throw new ProviderError('Provider response exceeded its maximum size.', {
              code: 'provider_response_too_large',
              billingDisposition: 'hold',
            });
          }
          chunks.push(Buffer.from(value));
        }
      }
    } catch (error) {
      if (error instanceof ProviderError) throw error;
      if (controller.signal.aborted) {
        throw new ProviderError('Provider request timed out.', {
          code: 'provider_timeout',
          status: 504,
          billingDisposition: 'hold',
        });
      }
      throw new ProviderError('Provider response stream failed.', {
        code: 'provider_invalid_response',
        billingDisposition: 'hold',
      });
    }
    let payload;
    try {
      payload = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    } catch {
      throw new ProviderError('Provider returned a non-JSON response.', {
        code: 'provider_invalid_response',
        billingDisposition: 'hold',
      });
    }
    if (!response.ok) {
      const isClientRejection = response.status >= 400 && response.status < 500;
      throw new ProviderError('Provider request failed.', {
        code: isClientRejection ? 'provider_rejected' : 'provider_http_error',
        status: 502,
        billingDisposition: isClientRejection ? 'release' : 'hold',
      });
    }
    return payload;
  } finally {
    clearTimeout(timeout);
  }
}

export async function fetchProviderJson({
  concurrencyGate = defaultConcurrencyGate,
  ...input
}) {
  if (!concurrencyGate || typeof concurrencyGate.acquire !== 'function') {
    throw new TypeError('concurrencyGate is required.');
  }
  const release = await concurrencyGate.acquire();
  try {
    return await executeProviderJson(input);
  } finally {
    release();
  }
}
