/**
 * Versioned SQLite schema.
 *
 * Each migration runs exactly once and is recorded in `schema_meta`, so the
 * database can be upgraded in place when the shape changes later.
 */

export const SCHEMA_VERSION = 2;

const migrations = [
  {
    version: 1,
    sql: `
      CREATE TABLE IF NOT EXISTS schema_meta (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );

      -- People who can sign in (drivers and admins).
      CREATE TABLE IF NOT EXISTS drivers (
        id            TEXT PRIMARY KEY,
        email         TEXT NOT NULL UNIQUE,
        name          TEXT NOT NULL,
        role          TEXT NOT NULL DEFAULT 'driver',
        password_hash TEXT NOT NULL,
        active        INTEGER NOT NULL DEFAULT 1,
        created_at    TEXT NOT NULL
      );

      -- Bearer sessions; only the SHA-256 of the token is stored.
      CREATE TABLE IF NOT EXISTS sessions (
        token_hash TEXT PRIMARY KEY,
        driver_id  TEXT NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_sessions_expiry ON sessions(expires_at);

      CREATE TABLE IF NOT EXISTS customers (
        id                TEXT PRIMARY KEY,
        first_name        TEXT NOT NULL,
        last_name         TEXT NOT NULL DEFAULT '',
        phone             TEXT NOT NULL DEFAULT '',
        preferred_channel TEXT NOT NULL DEFAULT 'sms',
        language          TEXT NOT NULL DEFAULT 'en',
        rating            REAL,
        created_at        TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS deliveries (
        id            TEXT PRIMARY KEY,
        status        TEXT NOT NULL DEFAULT 'pending',
        zone          TEXT,
        sequence      INTEGER NOT NULL DEFAULT 0,
        driver_id     TEXT REFERENCES drivers(id),
        customer_id   TEXT REFERENCES customers(id),
        window_start  TEXT,
        window_end    TEXT,
        eta           TEXT,
        distance_km   REAL,
        parcels       INTEGER,
        cod_amount    REAL,
        currency      TEXT DEFAULT 'EUR',
        address_json  TEXT NOT NULL DEFAULT '{}',
        notes_json    TEXT NOT NULL DEFAULT '[]',
        events_json   TEXT NOT NULL DEFAULT '[]',
        history_json  TEXT NOT NULL DEFAULT '[]',
        created_at    TEXT NOT NULL,
        updated_at    TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_deliveries_driver ON deliveries(driver_id);
      CREATE INDEX IF NOT EXISTS idx_deliveries_status ON deliveries(status);

      -- Append-only audit trail of every status transition.
      CREATE TABLE IF NOT EXISTS delivery_status_history (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        delivery_id TEXT NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
        from_status TEXT,
        to_status   TEXT NOT NULL,
        label       TEXT,
        changed_by  TEXT,
        changed_at  TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_status_history_delivery
        ON delivery_status_history(delivery_id, changed_at);

      -- Outbox: every message the driver actually approved and sent.
      CREATE TABLE IF NOT EXISTS messages (
        seq        INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id TEXT NOT NULL UNIQUE,
        delivery_id TEXT NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
        channel    TEXT NOT NULL,
        recipient  TEXT NOT NULL,
        body       TEXT NOT NULL,
        action     TEXT,
        sent_by    TEXT,
        sent_at    TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_messages_delivery ON messages(delivery_id);

      -- Feed the mobile app polls for local notifications.
      CREATE TABLE IF NOT EXISTS notifications (
        seq            INTEGER PRIMARY KEY AUTOINCREMENT,
        notification_id TEXT NOT NULL UNIQUE,
        driver_id      TEXT NOT NULL,
        type           TEXT NOT NULL,
        title          TEXT NOT NULL,
        body           TEXT NOT NULL DEFAULT '',
        delivery_id    TEXT,
        source         TEXT NOT NULL DEFAULT 'service',
        is_read        INTEGER NOT NULL DEFAULT 0,
        created_at     TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_notifications_driver ON notifications(driver_id, is_read);
    `,
  },
  {
    // v2: what is inside the parcel (name, category, product photo) so the app
    // can show the driver what they are delivering, not only who receives it.
    version: 2,
    sql: `
      ALTER TABLE deliveries ADD COLUMN item_json TEXT;
    `,
  },
];

/** Applies every pending migration. Returns the versions that ran. */
export function runMigrations(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS schema_meta (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
  `);

  const current = Number(
    db.prepare(`SELECT value FROM schema_meta WHERE key = 'schema_version'`).get()?.value ?? 0,
  );

  const applied = [];
  for (const migration of migrations) {
    if (migration.version <= current) continue;
    db.exec(migration.sql);
    db.prepare(
      `INSERT INTO schema_meta (key, value) VALUES ('schema_version', ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value`,
    ).run(String(migration.version));
    applied.push(migration.version);
  }

  return applied;
}

export default { runMigrations, SCHEMA_VERSION };
