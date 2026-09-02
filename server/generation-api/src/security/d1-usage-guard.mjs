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

function requiredString(value, name) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new TypeError(`${name} is required.`);
  }
  return value;
}

function changes(result) {
  return Number(result?.meta?.changes ?? 0);
}

/**
 * Persistent fail-closed usage and storage ledger for Cloudflare D1.
 * Reservations are accepted by one conditional INSERT, so limits remain
 * atomic even when different Worker isolates receive concurrent requests.
 */
export class D1UsageGuard {
  constructor({
    database,
    maxCreditsPerOwner,
    maxConcurrentGenerationsPerOwner,
    maxGenerationReservationsPerWindow,
    maxGlobalGenerationReservationsPerWindow,
    rateWindowMilliseconds,
    activeReservationWindowMilliseconds,
    maxStorageBytesPerOwner,
    now = () => new Date(),
  }) {
    if (!database || typeof database.prepare !== 'function') {
      throw new TypeError('database is required.');
    }
    this.database = database;
    this.maxCreditsPerOwner = positiveInteger(
      maxCreditsPerOwner,
      'maxCreditsPerOwner',
    );
    this.maxConcurrent = positiveInteger(
      maxConcurrentGenerationsPerOwner,
      'maxConcurrentGenerationsPerOwner',
    );
    this.maxReservationsPerWindow = positiveInteger(
      maxGenerationReservationsPerWindow,
      'maxGenerationReservationsPerWindow',
    );
    this.maxGlobalReservationsPerWindow = positiveInteger(
      maxGlobalGenerationReservationsPerWindow,
      'maxGlobalGenerationReservationsPerWindow',
    );
    this.rateWindowMilliseconds = positiveInteger(
      rateWindowMilliseconds,
      'rateWindowMilliseconds',
    );
    this.activeReservationWindowMilliseconds = positiveInteger(
      activeReservationWindowMilliseconds ?? this.rateWindowMilliseconds,
      'activeReservationWindowMilliseconds',
    );
    this.maxStorageBytesPerOwner = positiveInteger(
      maxStorageBytesPerOwner,
      'maxStorageBytesPerOwner',
    );
    this.now = now;
  }

  async reserveGeneration({ ownerId, reservationId, fingerprint, creditCost }) {
    requiredString(ownerId, 'ownerId');
    requiredString(reservationId, 'reservationId');
    requiredString(fingerprint, 'fingerprint');
    positiveInteger(creditCost, 'creditCost');
    const existing = await this.#generationReservation(ownerId, reservationId);
    if (existing) return this.#existingGeneration(existing, fingerprint, creditCost);

    const timestamp = this.now().getTime();
    const inserted = await this.database
      .prepare(
        `INSERT INTO generation_usage_reservations
          (owner_id, reservation_id, fingerprint, credit_cost, state, created_at_ms, updated_at_ms)
         SELECT ?, ?, ?, ?, 'reserved', ?, ?
          WHERE
            (SELECT COUNT(*) FROM generation_usage_reservations
              WHERE created_at_ms >= ?) < ?
            AND
            (SELECT COUNT(*) FROM generation_usage_reservations
              WHERE owner_id = ? AND state = 'reserved'
                AND updated_at_ms >= ?) < ?
            AND
            (SELECT COUNT(*) FROM generation_usage_reservations
              WHERE owner_id = ? AND created_at_ms >= ?) < ?
            AND
            COALESCE((SELECT SUM(credit_cost) FROM generation_usage_reservations
              WHERE owner_id = ? AND state IN ('reserved', 'settled')), 0) + ? <=
              MIN(?, COALESCE((SELECT credit_limit FROM usage_accounts
                WHERE owner_id = ? AND status = 'active'), 0))
         ON CONFLICT(owner_id, reservation_id) DO NOTHING`,
      )
      .bind(
        ownerId,
        reservationId,
        fingerprint,
        creditCost,
        timestamp,
        timestamp,
        timestamp - this.rateWindowMilliseconds,
        this.maxGlobalReservationsPerWindow,
        ownerId,
        timestamp - this.activeReservationWindowMilliseconds,
        this.maxConcurrent,
        ownerId,
        timestamp - this.rateWindowMilliseconds,
        this.maxReservationsPerWindow,
        ownerId,
        creditCost,
        this.maxCreditsPerOwner,
        ownerId,
      )
      .run();
    if (changes(inserted) === 1) {
      return { kind: 'reserved', reservationId };
    }
    const raced = await this.#generationReservation(ownerId, reservationId);
    if (raced) return this.#existingGeneration(raced, fingerprint, creditCost);
    const account = await this.database
      .prepare(
        `SELECT credit_limit, status FROM usage_accounts WHERE owner_id = ?`,
      )
      .bind(ownerId)
      .first();
    if (!account || account.status !== 'active') {
      throw new UsageGuardError('generation_entitlement_required', 403);
    }
    const limits = await this.database
      .prepare(
        `SELECT
           (SELECT COUNT(*) FROM generation_usage_reservations
             WHERE created_at_ms >= ?) AS global_rate_count,
           SUM(CASE WHEN state = 'reserved' AND updated_at_ms >= ?
             THEN 1 ELSE 0 END) AS reserved_count,
           SUM(CASE WHEN created_at_ms >= ? THEN 1 ELSE 0 END) AS rate_count,
           COALESCE(SUM(CASE WHEN state IN ('reserved', 'settled') THEN credit_cost ELSE 0 END), 0) AS used_credits
         FROM generation_usage_reservations
         WHERE owner_id = ?`,
      )
      .bind(
        timestamp - this.rateWindowMilliseconds,
        timestamp - this.activeReservationWindowMilliseconds,
        timestamp - this.rateWindowMilliseconds,
        ownerId,
      )
      .first();
    if (
      Number(limits?.global_rate_count ?? 0) >=
      this.maxGlobalReservationsPerWindow
    ) {
      throw new UsageGuardError('generation_global_rate_exceeded', 429);
    }
    if (Number(limits?.rate_count ?? 0) >= this.maxReservationsPerWindow) {
      throw new UsageGuardError('generation_rate_exceeded', 429);
    }
    if (Number(limits?.reserved_count ?? 0) >= this.maxConcurrent) {
      throw new UsageGuardError('generation_concurrency_exceeded', 429);
    }
    const effectiveCreditLimit = Math.min(
      this.maxCreditsPerOwner,
      Number(account.credit_limit ?? 0),
    );
    if (Number(limits?.used_credits ?? 0) + creditCost > effectiveCreditLimit) {
      throw new UsageGuardError('generation_credit_exhausted', 402);
    }
    throw new UsageGuardError('generation_reservation_rejected', 409);
  }

  async touchGeneration({ ownerId, reservationId }) {
    const reservation = await this.#requiredGeneration(ownerId, reservationId);
    if (reservation.state !== 'reserved') return { kind: 'existing' };
    const result = await this.database
      .prepare(
        `UPDATE generation_usage_reservations
            SET updated_at_ms = ?
          WHERE owner_id = ? AND reservation_id = ? AND state = 'reserved'`,
      )
      .bind(this.now().getTime(), ownerId, reservationId)
      .run();
    return { kind: changes(result) === 1 ? 'touched' : 'existing' };
  }

  async settleGeneration({ ownerId, reservationId }) {
    const reservation = await this.#requiredGeneration(ownerId, reservationId);
    if (reservation.state === 'settled') return { kind: 'existing' };
    if (reservation.state === 'released') {
      throw new UsageGuardError('usage_reservation_released', 409);
    }
    const result = await this.database
      .prepare(
        `UPDATE generation_usage_reservations
            SET state = 'settled', updated_at_ms = ?
          WHERE owner_id = ? AND reservation_id = ? AND state = 'reserved'`,
      )
      .bind(this.now().getTime(), ownerId, reservationId)
      .run();
    if (changes(result) === 1) return { kind: 'settled' };
    return this.settleGeneration({ ownerId, reservationId });
  }

  async releaseGeneration({ ownerId, reservationId }) {
    const reservation = await this.#requiredGeneration(ownerId, reservationId);
    if (reservation.state === 'released') return { kind: 'existing' };
    if (reservation.state === 'settled') return { kind: 'already_settled' };
    const result = await this.database
      .prepare(
        `UPDATE generation_usage_reservations
            SET state = 'released', updated_at_ms = ?
          WHERE owner_id = ? AND reservation_id = ? AND state = 'reserved'`,
      )
      .bind(this.now().getTime(), ownerId, reservationId)
      .run();
    if (changes(result) === 1) return { kind: 'released' };
    return this.releaseGeneration({ ownerId, reservationId });
  }

  async reserveStorage({ ownerId, reservationId, bytes }) {
    requiredString(ownerId, 'ownerId');
    requiredString(reservationId, 'reservationId');
    positiveInteger(bytes, 'bytes');
    const existing = await this.#storageReservation(ownerId, reservationId);
    if (existing) return this.#existingStorage(existing, bytes);
    const timestamp = this.now().getTime();
    const inserted = await this.database
      .prepare(
        `INSERT INTO storage_usage_reservations
          (owner_id, reservation_id, bytes, state, created_at_ms, updated_at_ms)
         SELECT ?, ?, ?, 'reserved', ?, ?
          WHERE COALESCE((SELECT SUM(bytes) FROM storage_usage_reservations
            WHERE owner_id = ? AND state IN ('reserved', 'committed')), 0) + ? <= ?
         ON CONFLICT(owner_id, reservation_id) DO NOTHING`,
      )
      .bind(
        ownerId,
        reservationId,
        bytes,
        timestamp,
        timestamp,
        ownerId,
        bytes,
        this.maxStorageBytesPerOwner,
      )
      .run();
    if (changes(inserted) === 1) return { kind: 'reserved' };
    const raced = await this.#storageReservation(ownerId, reservationId);
    if (raced) return this.#existingStorage(raced, bytes);
    throw new UsageGuardError('storage_quota_exceeded', 413);
  }

  async commitStorage({ ownerId, reservationId }) {
    const item = await this.#requiredStorage(ownerId, reservationId);
    if (item.state === 'committed') return { kind: 'existing' };
    if (item.state === 'released') {
      throw new UsageGuardError('storage_reservation_released', 409);
    }
    if (item.state === 'expired') {
      throw new UsageGuardError('storage_reservation_expired', 409);
    }
    const result = await this.database
      .prepare(
        `UPDATE storage_usage_reservations
            SET state = 'committed', updated_at_ms = ?
          WHERE owner_id = ? AND reservation_id = ? AND state = 'reserved'`,
      )
      .bind(this.now().getTime(), ownerId, reservationId)
      .run();
    if (changes(result) === 1) return { kind: 'committed' };
    return this.commitStorage({ ownerId, reservationId });
  }

  async releaseStorage({ ownerId, reservationId }) {
    const item = await this.#storageReservation(ownerId, reservationId);
    if (!item || item.state === 'released' || item.state === 'expired') {
      return { kind: 'existing' };
    }
    if (item.state === 'committed') return { kind: 'already_committed' };
    const result = await this.database
      .prepare(
        `UPDATE storage_usage_reservations
            SET state = 'released', updated_at_ms = ?
          WHERE owner_id = ? AND reservation_id = ? AND state = 'reserved'`,
      )
      .bind(this.now().getTime(), ownerId, reservationId)
      .run();
    if (changes(result) === 1) return { kind: 'released' };
    return this.releaseStorage({ ownerId, reservationId });
  }

  async expireStorage({ ownerId, reservationId }) {
    const item = await this.#storageReservation(ownerId, reservationId);
    if (!item || item.state === 'expired') return { kind: 'existing' };
    const result = await this.database
      .prepare(
        `UPDATE storage_usage_reservations
            SET state = 'expired', updated_at_ms = ?
          WHERE owner_id = ? AND reservation_id = ? AND state != 'expired'`,
      )
      .bind(this.now().getTime(), ownerId, reservationId)
      .run();
    if (changes(result) === 1) return { kind: 'expired' };
    return this.expireStorage({ ownerId, reservationId });
  }

  async #generationReservation(ownerId, reservationId) {
    return this.database
      .prepare(
        `SELECT fingerprint, credit_cost, state
           FROM generation_usage_reservations
          WHERE owner_id = ? AND reservation_id = ?`,
      )
      .bind(ownerId, reservationId)
      .first();
  }

  async #requiredGeneration(ownerId, reservationId) {
    const reservation = await this.#generationReservation(ownerId, reservationId);
    if (!reservation) {
      throw new UsageGuardError('usage_reservation_missing', 409);
    }
    return reservation;
  }

  #existingGeneration(existing, fingerprint, creditCost) {
    if (
      existing.fingerprint !== fingerprint ||
      Number(existing.credit_cost) !== creditCost
    ) {
      throw new UsageGuardError('usage_reservation_conflict', 409);
    }
    return { kind: 'existing' };
  }

  async #storageReservation(ownerId, reservationId) {
    return this.database
      .prepare(
        `SELECT bytes, state
           FROM storage_usage_reservations
          WHERE owner_id = ? AND reservation_id = ?`,
      )
      .bind(ownerId, reservationId)
      .first();
  }

  async #requiredStorage(ownerId, reservationId) {
    const item = await this.#storageReservation(ownerId, reservationId);
    if (!item) {
      throw new UsageGuardError('storage_reservation_missing', 409);
    }
    return item;
  }

  #existingStorage(existing, bytes) {
    if (Number(existing.bytes) !== bytes) {
      throw new UsageGuardError('storage_reservation_conflict', 409);
    }
    return { kind: 'existing' };
  }
}
