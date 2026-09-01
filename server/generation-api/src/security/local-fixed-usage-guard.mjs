class UsageGuardError extends Error {
  constructor(code, status) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

function positiveInteger(value, name) {
  if (!Number.isInteger(value) || value <= 0) {
    throw new TypeError(`${name} must be a positive integer.`);
  }
  return value;
}

export class LocalFixedUsageGuard {
  constructor({
    maxCreditsPerOwner,
    maxConcurrentGenerationsPerOwner,
    maxGenerationReservationsPerWindow,
    rateWindowMilliseconds,
    maxStorageBytesPerOwner,
    now = () => new Date(),
  }) {
    this.maxCreditsPerOwner = positiveInteger(maxCreditsPerOwner, 'maxCreditsPerOwner');
    this.maxConcurrent = positiveInteger(
      maxConcurrentGenerationsPerOwner,
      'maxConcurrentGenerationsPerOwner',
    );
    this.maxReservationsPerWindow = positiveInteger(
      maxGenerationReservationsPerWindow,
      'maxGenerationReservationsPerWindow',
    );
    this.rateWindowMilliseconds = positiveInteger(
      rateWindowMilliseconds,
      'rateWindowMilliseconds',
    );
    this.maxStorageBytesPerOwner = positiveInteger(
      maxStorageBytesPerOwner,
      'maxStorageBytesPerOwner',
    );
    this.now = now;
    this.owners = new Map();
    this.tail = Promise.resolve();
  }

  reserveGeneration(input) {
    return this.#exclusive(() => {
      const ledger = this.#owner(input.ownerId);
      const existing = ledger.generations.get(input.reservationId);
      if (existing) {
        if (
          existing.fingerprint !== input.fingerprint ||
          existing.creditCost !== input.creditCost
        ) {
          throw new UsageGuardError('usage_reservation_conflict', 409);
        }
        return { kind: 'existing', reservationId: input.reservationId };
      }
      const now = this.now().getTime();
      ledger.rateEvents = ledger.rateEvents.filter(
        (timestamp) => now - timestamp < this.rateWindowMilliseconds,
      );
      if (ledger.rateEvents.length >= this.maxReservationsPerWindow) {
        throw new UsageGuardError('generation_rate_exceeded', 429);
      }
      const reserved = [...ledger.generations.values()].filter(
        (item) => item.state === 'reserved',
      );
      if (reserved.length >= this.maxConcurrent) {
        throw new UsageGuardError('generation_concurrency_exceeded', 429);
      }
      const reservedCredits = reserved.reduce((sum, item) => sum + item.creditCost, 0);
      if (
        ledger.spentCredits + reservedCredits + input.creditCost >
        this.maxCreditsPerOwner
      ) {
        throw new UsageGuardError('generation_credit_exhausted', 402);
      }
      ledger.rateEvents.push(now);
      ledger.generations.set(input.reservationId, {
        fingerprint: input.fingerprint,
        creditCost: input.creditCost,
        state: 'reserved',
      });
      return { kind: 'reserved', reservationId: input.reservationId };
    });
  }

  settleGeneration({ ownerId, reservationId }) {
    return this.#exclusive(() => {
      const reservation = this.#reservation(ownerId, reservationId);
      if (reservation.state === 'settled') {
        return { kind: 'existing' };
      }
      if (reservation.state === 'released') {
        throw new UsageGuardError('usage_reservation_released', 409);
      }
      reservation.state = 'settled';
      this.#owner(ownerId).spentCredits += reservation.creditCost;
      return { kind: 'settled' };
    });
  }

  releaseGeneration({ ownerId, reservationId }) {
    return this.#exclusive(() => {
      const reservation = this.#reservation(ownerId, reservationId);
      if (reservation.state === 'released') {
        return { kind: 'existing' };
      }
      if (reservation.state === 'settled') {
        return { kind: 'already_settled' };
      }
      reservation.state = 'released';
      return { kind: 'released' };
    });
  }

  reserveStorage({ ownerId, reservationId, bytes }) {
    return this.#exclusive(() => {
      positiveInteger(bytes, 'bytes');
      const ledger = this.#owner(ownerId);
      const existing = ledger.storage.get(reservationId);
      if (existing) {
        if (existing.bytes !== bytes) {
          throw new UsageGuardError('storage_reservation_conflict', 409);
        }
        return { kind: 'existing' };
      }
      const reservedBytes = [...ledger.storage.values()]
        .filter((item) => item.state === 'reserved')
        .reduce((sum, item) => sum + item.bytes, 0);
      if (ledger.storageBytes + reservedBytes + bytes > this.maxStorageBytesPerOwner) {
        throw new UsageGuardError('storage_quota_exceeded', 413);
      }
      ledger.storage.set(reservationId, { bytes, state: 'reserved' });
      return { kind: 'reserved' };
    });
  }

  commitStorage({ ownerId, reservationId }) {
    return this.#exclusive(() => {
      const item = this.#owner(ownerId).storage.get(reservationId);
      if (!item) {
        throw new UsageGuardError('storage_reservation_missing', 409);
      }
      if (item.state === 'committed') {
        return { kind: 'existing' };
      }
      if (item.state === 'released') {
        throw new UsageGuardError('storage_reservation_released', 409);
      }
      if (item.state === 'expired') {
        throw new UsageGuardError('storage_reservation_expired', 409);
      }
      item.state = 'committed';
      this.#owner(ownerId).storageBytes += item.bytes;
      return { kind: 'committed' };
    });
  }

  releaseStorage({ ownerId, reservationId }) {
    return this.#exclusive(() => {
      const item = this.#owner(ownerId).storage.get(reservationId);
      if (!item || item.state === 'released' || item.state === 'expired') {
        return { kind: 'existing' };
      }
      if (item.state === 'committed') {
        return { kind: 'already_committed' };
      }
      item.state = 'released';
      return { kind: 'released' };
    });
  }

  expireStorage({ ownerId, reservationId }) {
    return this.#exclusive(() => {
      const ledger = this.#owner(ownerId);
      const item = ledger.storage.get(reservationId);
      if (!item || item.state === 'expired') {
        return { kind: 'existing' };
      }
      if (item.state === 'committed') {
        ledger.storageBytes = Math.max(0, ledger.storageBytes - item.bytes);
      }
      item.state = 'expired';
      return { kind: 'expired' };
    });
  }

  #owner(ownerId) {
    let ledger = this.owners.get(ownerId);
    if (!ledger) {
      ledger = {
        spentCredits: 0,
        storageBytes: 0,
        rateEvents: [],
        generations: new Map(),
        storage: new Map(),
      };
      this.owners.set(ownerId, ledger);
    }
    return ledger;
  }

  #reservation(ownerId, reservationId) {
    const reservation = this.#owner(ownerId).generations.get(reservationId);
    if (!reservation) {
      throw new UsageGuardError('usage_reservation_missing', 409);
    }
    return reservation;
  }

  #exclusive(operation) {
    const result = this.tail.then(operation);
    this.tail = result.catch(() => undefined);
    return result;
  }
}
