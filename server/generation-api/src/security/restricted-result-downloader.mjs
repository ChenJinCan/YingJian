import { lookup as dnsLookupCallback } from 'node:dns';
import { promisify } from 'node:util';
import { request as httpsRequest } from 'node:https';
import { isIP } from 'node:net';

import { isAllowedAlibabaResultHost } from './alibaba-result-host.mjs';

const defaultLookup = promisify(dnsLookupCallback);

class DownloadError extends Error {
  constructor(code, status = 502) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

function isPublicIpv4(address) {
  const octets = address.split('.').map(Number);
  if (octets.length !== 4 || octets.some((value) => !Number.isInteger(value))) return false;
  const [a, b] = octets;
  if (a === 0 || a === 10 || a === 127 || a >= 224) return false;
  if (a === 100 && b >= 64 && b <= 127) return false;
  if (a === 169 && b === 254) return false;
  if (a === 172 && b >= 16 && b <= 31) return false;
  if (a === 192 && (b === 0 || b === 168)) return false;
  if (a === 198 && (b === 18 || b === 19 || b === 51)) return false;
  if (a === 203 && b === 0) return false;
  return true;
}

function isPublicAddress(address) {
  const family = isIP(address);
  if (family === 4) return isPublicIpv4(address);
  if (family !== 6) return false;
  const normalized = address.toLowerCase();
  if (
    normalized === '::' ||
    normalized === '::1' ||
    normalized.startsWith('fc') ||
    normalized.startsWith('fd') ||
    /^fe[89ab]/.test(normalized) ||
    normalized.startsWith('2001:db8:')
  ) {
    return false;
  }
  const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(normalized);
  if (mapped) return isPublicIpv4(mapped[1]);
  const mappedHex = /^::(?:ffff:)?([0-9a-f]{1,4}):([0-9a-f]{1,4})$/.exec(
    normalized,
  );
  if (mappedHex) {
    const high = Number.parseInt(mappedHex[1], 16);
    const low = Number.parseInt(mappedHex[2], 16);
    return isPublicIpv4(
      `${high >>> 8}.${high & 0xff}.${low >>> 8}.${low & 0xff}`,
    );
  }
  return true;
}

async function withTimeout(promise, timeoutMilliseconds) {
  let timeout;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timeout = setTimeout(
          () => reject(new DownloadError('provider_output_timeout', 504)),
          timeoutMilliseconds,
        );
      }),
    ]);
  } finally {
    clearTimeout(timeout);
  }
}

export function createAlibabaResultDownloader({
  lookupImpl = (hostname) => defaultLookup(hostname, { all: true, verbatim: true }),
  requestImpl = httpsRequest,
  maxBytes = 25 * 1024 * 1024,
  timeoutMilliseconds = 15_000,
} = {}) {
  if (typeof lookupImpl !== 'function' || typeof requestImpl !== 'function') {
    throw new TypeError('lookupImpl and requestImpl are required.');
  }
  return {
    async download(rawUrl) {
      const deadline = Date.now() + timeoutMilliseconds;
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
        isIP(url.hostname) !== 0 ||
        !isAllowedAlibabaResultHost(url.hostname)
      ) {
        throw new DownloadError('provider_output_host_forbidden');
      }
      let addresses;
      try {
        addresses = await withTimeout(
          lookupImpl(url.hostname),
          timeoutMilliseconds,
        );
      } catch (error) {
        if (error instanceof DownloadError) throw error;
        throw new DownloadError('provider_output_dns_failed');
      }
      if (
        !Array.isArray(addresses) ||
        addresses.length === 0 ||
        addresses.some((item) => !isPublicAddress(item.address))
      ) {
        throw new DownloadError('provider_output_address_forbidden');
      }
      const selected = addresses[0];
      return new Promise((resolve, reject) => {
        let settled = false;
        let request;
        const remainingMilliseconds = Math.max(1, deadline - Date.now());
        const totalTimeout = setTimeout(() => {
          if (request) {
            request.destroy(new DownloadError('provider_output_timeout', 504));
          } else {
            fail(new DownloadError('provider_output_timeout', 504));
          }
        }, remainingMilliseconds);
        const fail = (error) => {
          if (settled) return;
          settled = true;
          clearTimeout(totalTimeout);
          reject(error instanceof DownloadError ? error : new DownloadError('provider_output_download_failed'));
        };
        try {
          request = requestImpl(
            url,
            {
              method: 'GET',
              servername: url.hostname,
              lookup: (_hostname, _options, callback) =>
                callback(null, selected.address, selected.family),
              headers: {
                accept: 'image/png,image/jpeg,image/webp,image/bmp,video/mp4',
              },
            },
            (response) => {
              if (settled) {
                response.destroy();
                return;
              }
            const statusCode = Number(response.statusCode ?? 0);
            if (statusCode >= 300 && statusCode < 400) {
              response.destroy();
              fail(new DownloadError('provider_output_redirect_forbidden'));
              return;
            }
            if (statusCode !== 200) {
              response.destroy();
              fail(new DownloadError('provider_output_download_failed'));
              return;
            }
            const contentLength = Number(response.headers['content-length'] ?? 0);
            if (contentLength > maxBytes) {
              response.destroy();
              fail(new DownloadError('provider_output_too_large'));
              return;
            }
            const chunks = [];
            let total = 0;
            response.on('data', (chunk) => {
              total += chunk.length;
              if (total > maxBytes) {
                response.destroy();
                fail(new DownloadError('provider_output_too_large'));
                return;
              }
              chunks.push(chunk);
            });
            response.once('error', fail);
            response.once('aborted', () => fail(new DownloadError('provider_output_download_failed')));
            response.once('end', () => {
              if (settled) return;
              settled = true;
              clearTimeout(totalTimeout);
              resolve({
                data: Buffer.concat(chunks),
                mimeType: String(response.headers['content-type'] ?? '').split(';', 1)[0],
              });
            });
            },
          );
        } catch (error) {
          fail(error);
          return;
        }
        request.once('error', fail);
        request.setTimeout(remainingMilliseconds, () => {
          request.destroy(new DownloadError('provider_output_timeout', 504));
        });
        request.end();
      });
    },
  };
}
