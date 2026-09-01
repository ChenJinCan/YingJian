import {
  createHash,
  createHmac,
  randomUUID,
  timingSafeEqual,
} from 'node:crypto';

const CURRENT_POLICY_VERSION = 1;

class OfferError extends Error {
  constructor(code, status = 409) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

function ownerIdentity(ownerId) {
  return createHash('sha256').update(ownerId).digest('hex');
}

export class HmacOfferAuthority {
  constructor({ signingKey, ttlMilliseconds = 15 * 60 * 1000, nonceFactory = randomUUID }) {
    if (typeof signingKey !== 'string' || Buffer.byteLength(signingKey) < 32) {
      throw new TypeError('signingKey must contain at least 32 bytes.');
    }
    if (!Number.isInteger(ttlMilliseconds) || ttlMilliseconds < 1000) {
      throw new TypeError('ttlMilliseconds must be a positive integer.');
    }
    this.signingKey = signingKey;
    this.ttlMilliseconds = ttlMilliseconds;
    this.nonceFactory = nonceFactory;
  }

  issue({ ownerId, capability, creditCost, policyVersion, now }) {
    if (policyVersion !== CURRENT_POLICY_VERSION) {
      throw new OfferError('policy_version_unsupported');
    }
    const issuedAt = now.getTime();
    const expiresAt = issuedAt + this.ttlMilliseconds;
    const payload = {
      owner: ownerIdentity(ownerId),
      capability,
      creditCost,
      policyVersion,
      issuedAt,
      expiresAt,
      nonce: this.nonceFactory(),
    };
    const encoded = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const signature = createHmac('sha256', this.signingKey)
      .update(encoded)
      .digest('base64url');
    return {
      id: `${encoded}.${signature}`,
      creditCost,
      expiresAt: new Date(expiresAt).toISOString(),
    };
  }

  verify({ offerId, ownerId, capability, policyVersion, now }) {
    if (policyVersion !== CURRENT_POLICY_VERSION) {
      throw new OfferError('policy_version_unsupported');
    }
    const [encoded, providedSignature, extra] = String(offerId).split('.');
    if (!encoded || !providedSignature || extra) {
      throw new OfferError('offer_invalid');
    }
    const expectedSignature = createHmac('sha256', this.signingKey)
      .update(encoded)
      .digest();
    let receivedSignature;
    try {
      receivedSignature = Buffer.from(providedSignature, 'base64url');
    } catch {
      throw new OfferError('offer_invalid');
    }
    if (
      receivedSignature.length !== expectedSignature.length ||
      !timingSafeEqual(receivedSignature, expectedSignature)
    ) {
      throw new OfferError('offer_invalid');
    }
    let payload;
    try {
      payload = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));
    } catch {
      throw new OfferError('offer_invalid');
    }
    if (
      payload.owner !== ownerIdentity(ownerId) ||
      payload.capability !== capability ||
      payload.policyVersion !== CURRENT_POLICY_VERSION ||
      !Number.isInteger(payload.creditCost) ||
      payload.creditCost <= 0
    ) {
      throw new OfferError('offer_mismatch');
    }
    if (!Number.isFinite(payload.expiresAt) || now.getTime() >= payload.expiresAt) {
      throw new OfferError('offer_expired');
    }
    return {
      creditCost: payload.creditCost,
      expiresAt: new Date(payload.expiresAt).toISOString(),
    };
  }
}

export { CURRENT_POLICY_VERSION };
