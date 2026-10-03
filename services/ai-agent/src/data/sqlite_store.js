import { DatabaseSync } from 'node:sqlite';

/**
 * SQLite-backed stores.
 *
 * Both interfaces match their in-memory counterparts exactly
 * (`deliveryStore` in `deliveries.js` and `createMemoryAuthStore`), so routes
 * and the agent cannot tell where the rows live - only that they survive a
 * restart.
 *
 * @typedef {object} DeliveryStoreApi
 * @property {(params?: {driverId?: string}) => Promise<object[]>} list
 * @property {(id: string) => Promise<object|null>} get
 * @property {(id: string, status: string, meta?: {label?: string, changedBy?: string}) => Promise<object|null>} updateStatus
 * @property {(message: object) => Promise<object>} sendMessage
 * @property {() => Promise<object[]>} outbox
 */

const dbValue = (value) => (value === undefined ? null : value);

function safeJson(text, fallback) {
  try {
    return JSON.parse(text ?? 'null') ?? fallback;
  } catch {
    return fallback;
  }
}

function mapDelivery(row) {
  if (!row) return null;
  return {
    id: row.id,
    status: row.status,
    zone: row.zone,
    sequence: row.sequence,
    driverId: row.driver_id,
    windowStart: row.window_start,
    windowEnd: row.window_end,
    eta: row.eta,
    distanceKm: row.distance_km,
    parcels: row.parcels,
    codAmount: row.cod_amount,
    currency: row.currency,
    address: safeJson(row.address_json, {}),
    customer: row.c_id
      ? {
          id: row.c_id,
          firstName: row.first_name,
          lastName: row.last_name,
          phone: row.phone,
          preferredChannel: row.preferred_channel,
          language: row.language,
          rating: row.rating,
        }
      : null,
    notes: safeJson(row.notes_json, []),
    events: safeJson(row.events_json, []),
    history: safeJson(row.history_json, []),
    item: row.item_json ? safeJson(row.item_json, null) : null,
  };
}

const DELIVERY_SELECT = `
  SELECT d.id, d.status, d.zone, d.sequence, d.driver_id, d.customer_id,
         d.window_start, d.window_end, d.eta, d.distance_km, d.parcels,
         d.cod_amount, d.currency, d.address_json, d.notes_json, d.events_json,
         d.history_json, d.item_json,
         c.id AS c_id, c.first_name, c.last_name, c.phone, c.preferred_channel,
         c.language, c.rating
  FROM deliveries d
  LEFT JOIN customers c ON c.id = d.customer_id
`;

/** Delivery CRUD + outbox, persisted in SQLite. */
export function createSqliteStore(db) {
  return {
    db,

    async list({ driverId } = {}) {
      const rows = driverId
        ? db
            .prepare(`${DELIVERY_SELECT} WHERE d.driver_id = ? ORDER BY d.sequence`)
            .all(driverId)
        : db.prepare(`${DELIVERY_SELECT} ORDER BY d.sequence`).all();
      return rows.map(mapDelivery);
    },

    async get(id) {
      const row = db.prepare(`${DELIVERY_SELECT} WHERE d.id = ?`).get(id);
      return mapDelivery(row);
    },

    async updateStatus(id, status, { label, changedBy } = {}) {
      const current = await this.get(id);
      if (!current) return null;

      const now = new Date().toISOString();
      const events = [
        ...current.events,
        { at: now, type: status, label: label ?? `Status changed to ${status}` },
      ];

      db.prepare('UPDATE deliveries SET status = ?, events_json = ?, updated_at = ? WHERE id = ?').run(
        status,
        JSON.stringify(events),
        now,
        id,
      );
      db.prepare(
        `INSERT INTO delivery_status_history
           (delivery_id, from_status, to_status, label, changed_by, changed_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      ).run(id, current.status, status, dbValue(label), dbValue(changedBy), now);

      return this.get(id);
    },

    /** Stores a driver-approved message; only called after server guardrails. */
    async sendMessage(message) {
      const sentAt = new Date().toISOString();
      // AUTOINCREMENT never reuses a seq, so the id can be computed up-front
      // and written in a single statement (message_id is NOT NULL UNIQUE).
      const nextSeq =
        Number(db.prepare('SELECT COALESCE(MAX(seq), 0) AS n FROM messages').get()?.n ?? 0) + 1;
      const messageId = `MSG-${String(nextSeq).padStart(4, '0')}`;

      db.prepare(
        `INSERT INTO messages (message_id, delivery_id, channel, recipient, body, action, sent_by, sent_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run(
        messageId,
        message.deliveryId,
        message.channel,
        message.recipient,
        message.body,
        dbValue(message.action),
        dbValue(message.sentBy),
        sentAt,
      );

      return { messageId, sentAt, ...message };
    },

    async outbox() {
      return db
        .prepare('SELECT * FROM messages ORDER BY seq')
        .all()
        .map((row) => ({
          messageId: row.message_id,
          sentAt: row.sent_at,
          deliveryId: row.delivery_id,
          channel: row.channel,
          recipient: row.recipient,
          body: row.body,
          action: row.action,
          sentBy: row.sent_by,
        }));
    },
  };
}

function mapUser(row) {
  if (!row) return null;
  return {
    id: row.id,
    email: row.email,
    name: row.name,
    role: row.role,
    passwordHash: row.password_hash,
    active: row.active,
    createdAt: row.created_at,
  };
}

/** Users + sessions, persisted in SQLite (same surface as the memory store). */
export function createSqliteAuthStore(db) {
  return {
    async findUserByEmail(email) {
      const needle = String(email ?? '').trim().toLowerCase();
      return mapUser(db.prepare('SELECT * FROM drivers WHERE email = ?').get(needle));
    },

    async findUserById(id) {
      return mapUser(db.prepare('SELECT * FROM drivers WHERE id = ?').get(id));
    },

    async countUsers() {
      return Number(db.prepare('SELECT COUNT(*) AS n FROM drivers').get()?.n ?? 0);
    },

    async createUser(user) {
      db.prepare(
        `INSERT INTO drivers (id, email, name, role, password_hash, active, created_at)
         VALUES (?, ?, ?, ?, ?, 1, ?)`,
      ).run(
        user.id,
        String(user.email).trim().toLowerCase(),
        user.name,
        user.role ?? 'driver',
        user.passwordHash,
        new Date().toISOString(),
      );
      return this.findUserById(user.id);
    },

    async createUsers(rows) {
      for (const row of rows) await this.createUser(row);
    },

    async createSession({ tokenHash, userId, expiresAt }) {
      db.prepare(
        `INSERT INTO sessions (token_hash, driver_id, created_at, expires_at)
         VALUES (?, ?, ?, ?)`,
      ).run(tokenHash, userId, new Date().toISOString(), expiresAt);
    },

    async findSession(tokenHash) {
      const row = db.prepare('SELECT * FROM sessions WHERE token_hash = ?').get(tokenHash);
      if (!row) return null;
      if (Date.parse(row.expires_at) <= Date.now()) {
        db.prepare('DELETE FROM sessions WHERE token_hash = ?').run(tokenHash);
        return null;
      }
      return {
        tokenHash: row.token_hash,
        userId: row.driver_id,
        createdAt: row.created_at,
        expiresAt: row.expires_at,
      };
    },

    async deleteSession(tokenHash) {
      db.prepare('DELETE FROM sessions WHERE token_hash = ?').run(tokenHash);
    },

    async deleteSessionsForUser(userId) {
      db.prepare('DELETE FROM sessions WHERE driver_id = ?').run(userId);
    },

    async purgeExpiredSessions() {
      const info = db.prepare('DELETE FROM sessions WHERE expires_at <= ?').run(
        new Date().toISOString(),
      );
      return Number(info.changes ?? 0);
    },
  };
}

function mapNotification(row) {
  if (!row) return null;
  return {
    id: row.notification_id,
    type: row.type,
    title: row.title,
    body: row.body,
    deliveryId: row.delivery_id,
    source: row.source,
    isRead: Number(row.is_read) === 1,
    createdAt: row.created_at,
  };
}

/**
 * Notification feed per driver (NTF- id format), persisted in SQLite.
 *
 * `source` records where the event came from: `service` for real runtime
 * triggers (status changes, sent messages), `demo` for the seeded demo
 * dataset that stands in for the customer/dispatch systems.
 */
export function createNotificationStore(db) {
  return {
    async list({ driverId, unreadOnly = false } = {}) {
      const rows = unreadOnly
        ? db
            .prepare(
              'SELECT * FROM notifications WHERE driver_id = ? AND is_read = 0 ' +
                'ORDER BY created_at DESC, seq DESC',
            )
            .all(driverId)
        : db
            .prepare(
              'SELECT * FROM notifications WHERE driver_id = ? ORDER BY created_at DESC, seq DESC',
            )
            .all(driverId);
      return rows.map(mapNotification);
    },

    async unreadCount(driverId) {
      const row = db
        .prepare('SELECT COUNT(*) AS n FROM notifications WHERE driver_id = ? AND is_read = 0')
        .get(driverId);
      return Number(row?.n ?? 0);
    },

    async create({
      driverId,
      type,
      title,
      body = '',
      deliveryId = null,
      source = 'service',
      isRead = false,
      createdAt,
    }) {
      const nextSeq =
        Number(db.prepare('SELECT COALESCE(MAX(seq), 0) AS n FROM notifications').get()?.n ?? 0) + 1;
      const notificationId = `NTF-${String(nextSeq).padStart(4, '0')}`;
      const createdAtIso = createdAt ?? new Date().toISOString();

      db.prepare(
        `INSERT INTO notifications
           (notification_id, driver_id, type, title, body, delivery_id, source, is_read, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run(
        notificationId,
        driverId,
        type,
        title,
        body,
        dbValue(deliveryId),
        source,
        isRead ? 1 : 0,
        createdAtIso,
      );

      return {
        id: notificationId,
        type,
        title,
        body,
        deliveryId,
        source,
        isRead,
        createdAt: createdAtIso,
      };
    },

    /** Marks one of *this driver's* notifications as read; null when unknown. */
    async markRead(driverId, id) {
      const info = db
        .prepare(
          'UPDATE notifications SET is_read = 1 WHERE notification_id = ? AND driver_id = ? AND is_read = 0',
        )
        .run(id, driverId);
      const row = db
        .prepare('SELECT * FROM notifications WHERE notification_id = ? AND driver_id = ?')
        .get(id, driverId);
      if (Number(info.changes ?? 0) === 0 && !row) return null; // unknown id / other driver
      return mapNotification(row); // already-read rows answer idempotently
    },

    /** Used by the demo seeder to stay idempotent. */
    count() {
      return Number(db.prepare('SELECT COUNT(*) AS n FROM notifications').get()?.n ?? 0);
    },
  };
}

export { DatabaseSync };
export default { createSqliteStore, createSqliteAuthStore, createNotificationStore };
