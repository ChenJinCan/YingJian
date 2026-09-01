const ALLOWED_MIME_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/bmp',
  'video/mp4',
]);

class DownloadError extends Error {
  constructor(code, status = 502) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

function allowedAlibabaHost(hostname) {
  return (
    hostname.endsWith('.oss-cn-beijing.aliyuncs.com') &&
    hostname !== 'oss-cn-beijing.aliyuncs.com'
  );
}

/**
 * Workers do not expose the Node socket lookup pinning used by the local
 * gateway. At the edge we instead allow only Alibaba's exact HTTPS OSS suffix,
 * reject redirects, and use Cloudflare's outbound fetch isolation.
 */
export function createCloudflareAlibabaResultDownloader({
  fetchImpl = globalThis.fetch,
  maxBytes = 25 * 1024 * 1024,
  timeoutMilliseconds = 15_000,
} = {}) {
  if (typeof fetchImpl !== 'function') {
    throw new TypeError('fetchImpl is required.');
  }
  return {
    async download(rawUrl) {
      let url;
      try {
        url = new URL(rawUrl);
      } catch {
        throw new DownloadError('provider_output_url_invalid');
      }
      if (
        url.protocol !== 'https:' ||
        url.port !== '' ||
        url.username !== '' ||
        url.password !== '' ||
        !allowedAlibabaHost(url.hostname)
      ) {
        throw new DownloadError('provider_output_host_forbidden');
      }
      const controller = new AbortController();
      const timeout = setTimeout(
        () => controller.abort(new Error('provider_output_timeout')),
        timeoutMilliseconds,
      );
      try {
        let response;
        try {
          response = await fetchImpl(url, {
            method: 'GET',
            headers: {
              accept: 'image/png,image/jpeg,image/webp,image/bmp,video/mp4',
            },
            redirect: 'error',
            signal: controller.signal,
          });
        } catch {
          throw new DownloadError(
            controller.signal.aborted
              ? 'provider_output_timeout'
              : 'provider_output_download_failed',
            controller.signal.aborted ? 504 : 502,
          );
        }
        if (response.status >= 300 && response.status < 400) {
          throw new DownloadError('provider_output_redirect_forbidden');
        }
        if (!response.ok) {
          throw new DownloadError('provider_output_download_failed');
        }
        const contentLength = Number(
          response.headers.get('content-length') ?? 0,
        );
        if (contentLength > maxBytes) {
          throw new DownloadError('provider_output_too_large');
        }
        const mimeType = String(
          response.headers.get('content-type') ?? '',
        ).split(';', 1)[0];
        if (!ALLOWED_MIME_TYPES.has(mimeType)) {
          throw new DownloadError('provider_output_type_forbidden');
        }
        const chunks = [];
        let total = 0;
        const reader = response.body?.getReader();
        if (!reader) throw new DownloadError('provider_output_download_failed');
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          total += value.byteLength;
          if (total > maxBytes) {
            await reader.cancel();
            throw new DownloadError('provider_output_too_large');
          }
          chunks.push(Buffer.from(value));
        }
        if (total === 0) {
          throw new DownloadError('provider_output_download_failed');
        }
        return { data: Buffer.concat(chunks), mimeType };
      } finally {
        clearTimeout(timeout);
      }
    },
  };
}
