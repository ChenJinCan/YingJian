import { timingSafeEqual } from 'node:crypto';

export function createLocalSharedBearerAuthenticator({ bearerToken, ownerId }) {
  if (typeof bearerToken !== 'string' || bearerToken.length < 16) {
    throw new TypeError('bearerToken is required and must be at least 16 characters.');
  }
  if (typeof ownerId !== 'string' || ownerId.length === 0) {
    throw new TypeError('ownerId is required.');
  }
  const expected = Buffer.from(`Bearer ${bearerToken}`);
  return async function authenticateLocalRequest(request) {
    const received = Buffer.from(request.headers.get('authorization') ?? '');
    if (received.length !== expected.length) {
      return null;
    }
    return timingSafeEqual(received, expected) ? { ownerId } : null;
  };
}
