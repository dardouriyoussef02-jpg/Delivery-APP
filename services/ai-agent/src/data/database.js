import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

import { deliveries as demoDeliveries } from './deliveries.js';
import { runMigrations } from './schema.js';
import { createNotificationStore } from './sqlite_store.js';

/**
 * Opens (and creates, if needed) the service's SQLite database.
 *
 * Uses Node's built-in `node:sqlite`, so the service keeps a zero-native-
 * dependency install while still persisting across restarts. Pass
 * `path: ':memory:'` for an isolated, throw-away database (tests).
 */
export function openDatabase({ path = ':memory:' } = {}) {
  if (path !== ':memory:') {
    mkdirSync(dirname(resolve(path)), { recursive: true });
  }

  const db = new DatabaseSync(path);
  db.exec('PRAGMA journal_mode = WAL');
  db.exec('PRAGMA foreign_keys = ON');
  runMigrations(db);
  return db;
}

/**
 * Seeds the demo dataset on an empty database so a fresh install still shows
 * the reference route. A database that already has rows is left untouched -
 * demo seeding is development data, production data comes from
 * EXISTING_API_BASE_URL.
 */
export function seedDemoDeliveries(db) {
  const existing = db.prepare('SELECT COUNT(*) AS n FROM deliveries').get();
  if (Number(existing?.n ?? 0) > 0) return false;

  const now = new Date().toISOString();

  // The demo route is an open pool: every stop starts unassigned, exactly like
  // work sitting on the dispatch board. Stops only gain an owner when a driver
  // signs the partnership agreement and the company sends them the open work
  // (`contract.sign` -> `assignOpenWork`).
  //
  // The seeded driver (DRV-77) still exists - it is created by the async auth
  // seeding - it just does not own anything yet.
  db.exec('PRAGMA foreign_keys = OFF');
  try {
    const upsertCustomer = db.prepare(`
      INSERT INTO customers
        (id, first_name, last_name, phone, preferred_channel, language, rating, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        first_name = excluded.first_name,
        last_name = excluded.last_name,
        phone = excluded.phone,
        preferred_channel = excluded.preferred_channel,
        language = excluded.language,
        rating = excluded.rating
    `);

    const insertDelivery = db.prepare(`
      INSERT INTO deliveries
        (id, status, zone, sequence, driver_id, customer_id, window_start, window_end, eta,
         distance_km, parcels, cod_amount, currency, address_json, notes_json, events_json,
         history_json, item_json, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    for (const demo of demoDeliveries) {
      const customer = demo.customer;
      upsertCustomer.run(
        customer.id,
        customer.firstName,
        customer.lastName ?? '',
        customer.phone ?? '',
        customer.preferredChannel ?? 'sms',
        customer.language ?? 'en',
        customer.rating ?? null,
        now,
      );

      insertDelivery.run(
        demo.id,
        demo.status,
        demo.zone ?? null,
        demo.sequence ?? 0,
        demo.driverId ?? null,
        customer?.id ?? null,
        demo.windowStart ?? null,
        demo.windowEnd ?? null,
        demo.eta ?? null,
        demo.distanceKm ?? null,
        demo.parcels ?? null,
        demo.codAmount ?? null,
        demo.currency ?? 'EUR',
        JSON.stringify(demo.address ?? {}),
        JSON.stringify(demo.notes ?? []),
        JSON.stringify(demo.events ?? []),
        JSON.stringify(demo.history ?? []),
        demo.item ? JSON.stringify(demo.item) : null,
        now,
        now,
      );
    }
  } finally {
    db.exec('PRAGMA foreign_keys = ON');
  }

  return true;
}

/**
 * Adds the `item` block to demo rows that were seeded before it existed.
 *
 * A database created by an older build has no `item_json` value, so the app
 * would show a nameless stop. Only demo rows are touched and only when the
 * column is still empty - real route data is never rewritten.
 */
export function backfillDemoItems(db) {
  const update = db.prepare(
    'UPDATE deliveries SET item_json = ? WHERE id = ? AND (item_json IS NULL OR item_json = \'\')',
  );

  let updated = 0;
  for (const demo of demoDeliveries) {
    if (!demo.item) continue;
    updated += Number(update.run(JSON.stringify(demo.item), demo.id).changes ?? 0);
  }
  return updated;
}

/**
 * Seeds the demo notification feed once (an empty notifications table only).
 *
 * These rows stand in for the systems a real deployment would integrate with -
 * dispatch assigning stops, a dispatcher reordering the route, a customer
 * adding a note. Every row is marked `source: 'demo'` so it stays clearly
 * separable from runtime events (`source: 'service'`, e.g. status changes).
 * Runtime "customer reply" notifications are created when a message is sent
 * in demo mode.
 */
export function seedDemoNotifications(db, { driverId } = {}) {
  const store = createNotificationStore(db);

  // Scoped to one driver: when a *second* driver signs later they must have
  // their own batch announced too, so a global "anything seeded yet?" guard
  // would leave them with an empty feed. Per driver it is still exactly-once -
  // a restart or a repeated sign never duplicates the rows.
  if (driverId) {
    const mine = db
      .prepare("SELECT COUNT(*) AS n FROM notifications WHERE source = 'demo' AND driver_id = ?")
      .get(driverId);
    if (Number(mine?.n ?? 0) > 0) return false;
  } else if (store.count() > 0) {
    return false;
  }

  const rows = db
    .prepare(
      `SELECT d.id, d.driver_id, d.sequence, d.notes_json, c.first_name, c.last_name
       FROM deliveries d
       LEFT JOIN customers c ON c.id = d.customer_id
       WHERE d.driver_id IS NOT NULL ${driverId ? 'AND d.driver_id = ?' : ''}
       ORDER BY d.sequence`,
    )
    .all(...(driverId ? [driverId] : []));
  if (rows.length === 0) return false;

  const minutesAgo = (minutes) => new Date(Date.now() - minutes * 60_000).toISOString();

  rows.forEach((row, index) => {
    const customerName = [row.first_name, row.last_name].filter(Boolean).join(' ');
    store.create({
      driverId: row.driver_id,
      type: 'delivery_assigned',
      title: 'Stop assigned to you',
      body: customerName
        ? `${row.id} · ${customerName} · stop ${row.sequence}`
        : `${row.id} · stop ${row.sequence}`,
      deliveryId: row.id,
      source: 'demo',
      // The two oldest assignments start as read so a demo badge is not
      // maxed out the moment it appears.
      isRead: index < 2,
      createdAt: minutesAgo(90 - index * 6),
    });
  });

  const reorder = rows.find((row) => row.id === 'DLV-1044');
  if (reorder) {
    store.create({
      driverId: reorder.driver_id,
      type: 'assignment_changed',
      title: 'Dispatch changed your route',
      body: `${reorder.id} was moved later in the route - check your stop order.`,
      deliveryId: reorder.id,
      source: 'demo',
      createdAt: minutesAgo(20),
    });
  }

  const noted = rows.find((row) => row.id === 'DLV-1043');
  if (noted) {
    const notes = JSON.parse(noted.notes_json ?? '[]');
    const customerNote = notes.find(
      (note) => note?.author === 'customer' && note?.text?.trim(),
    );
    if (customerNote) {
      const text = String(customerNote.text).trim();
      store.create({
        driverId: noted.driver_id,
        type: 'customer_update',
        title: 'Customer added a note',
        body: `${noted.id} · ${text.length > 140 ? `${text.slice(0, 140)}…` : text}`,
        deliveryId: noted.id,
        source: 'demo',
        createdAt: minutesAgo(8),
      });
    }
  }

  return true;
}

export default { openDatabase, seedDemoDeliveries, seedDemoNotifications, backfillDemoItems };
