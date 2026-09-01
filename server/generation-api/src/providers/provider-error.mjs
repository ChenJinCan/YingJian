export class ProviderError extends Error {
  constructor(
    message,
    { code = 'provider_error', status = 502, billingDisposition = 'hold' } = {},
  ) {
    super(message);
    this.name = 'ProviderError';
    this.code = code;
    this.status = status;
    this.billingDisposition = billingDisposition;
  }
}

export async function readProviderJson(response) {
  let body;
  try {
    body = await response.json();
  } catch {
    throw new ProviderError('Provider returned a non-JSON response.', {
      code: 'provider_invalid_response',
    });
  }
  if (!response.ok) {
    throw new ProviderError('Provider request failed.', {
      code: String(body?.error_code ?? body?.code ?? 'provider_http_error'),
      status: 502,
    });
  }
  return body;
}
