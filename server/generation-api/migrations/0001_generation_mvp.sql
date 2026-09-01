CREATE TABLE IF NOT EXISTS generation_tasks (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  creation_key TEXT NOT NULL UNIQUE,
  fingerprint TEXT NOT NULL,
  version INTEGER NOT NULL CHECK (version > 0),
  task_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS generation_tasks_owner_id
  ON generation_tasks(owner_id, id);

CREATE TABLE IF NOT EXISTS usage_accounts (
  owner_id TEXT PRIMARY KEY,
  credit_limit INTEGER NOT NULL CHECK (credit_limit > 0),
  status TEXT NOT NULL CHECK (status IN ('active', 'revoked')),
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS generation_usage_reservations (
  owner_id TEXT NOT NULL,
  reservation_id TEXT NOT NULL,
  fingerprint TEXT NOT NULL,
  credit_cost INTEGER NOT NULL CHECK (credit_cost > 0),
  state TEXT NOT NULL CHECK (state IN ('reserved', 'settled', 'released')),
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY (owner_id, reservation_id)
);

CREATE INDEX IF NOT EXISTS generation_usage_owner_state
  ON generation_usage_reservations(owner_id, state);

CREATE INDEX IF NOT EXISTS generation_usage_owner_created
  ON generation_usage_reservations(owner_id, created_at_ms);

CREATE TABLE IF NOT EXISTS storage_usage_reservations (
  owner_id TEXT NOT NULL,
  reservation_id TEXT NOT NULL,
  bytes INTEGER NOT NULL CHECK (bytes > 0),
  state TEXT NOT NULL CHECK (state IN ('reserved', 'committed', 'released', 'expired')),
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY (owner_id, reservation_id)
);

CREATE INDEX IF NOT EXISTS storage_usage_owner_state
  ON storage_usage_reservations(owner_id, state);

CREATE TABLE IF NOT EXISTS enrollment_codes (
  code_hash TEXT PRIMARY KEY,
  expires_at_ms INTEGER NOT NULL,
  credit_limit INTEGER NOT NULL CHECK (credit_limit > 0),
  bound_key_id TEXT,
  bound_installation_id TEXT,
  consumed_at_ms INTEGER,
  CHECK (
    (bound_key_id IS NULL AND bound_installation_id IS NULL) OR
    (bound_key_id IS NOT NULL AND bound_installation_id IS NOT NULL)
  )
);

CREATE TABLE IF NOT EXISTS installations (
  id TEXT PRIMARY KEY,
  key_id TEXT NOT NULL UNIQUE,
  public_key_x963 BLOB NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'revoked')),
  credit_limit INTEGER NOT NULL CHECK (credit_limit > 0),
  created_at_ms INTEGER NOT NULL,
  last_seen_at_ms INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS session_challenges (
  id TEXT PRIMARY KEY,
  purpose TEXT NOT NULL CHECK (purpose IN ('installation', 'generation_session')),
  key_id TEXT NOT NULL,
  installation_id TEXT,
  nonce_hash TEXT NOT NULL,
  expires_at_ms INTEGER NOT NULL,
  consumed_at_ms INTEGER
);

CREATE INDEX IF NOT EXISTS session_challenges_expiry
  ON session_challenges(expires_at_ms);

CREATE INDEX IF NOT EXISTS session_challenges_key_purpose
  ON session_challenges(key_id, purpose, consumed_at_ms);
