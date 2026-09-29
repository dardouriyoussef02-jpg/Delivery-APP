import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { backfillDemoItems, openDatabase, seedDemoDeliveries } from '../src/data/database.js';
import { createSqliteAuthStore, createSqliteStore } from '../src/data/sqlite_store.js';
import { seedUsers } from '../src/auth/seed.js';
import { hashToken } from '../src/auth/middleware.js';
import { startTestApp, TEST_DRIVER } from './helpers.js';

const tempDirs = [];

function tempDbPath() {
  const dir = mkdtempSync(join(tmpdir(), 'delivery-db-'));
  tempDirs.push(dir);
  return join(dir, 'delivery.db');
}

after(() => {
  for (const dir of tempDirs) {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {
      // best effort
    }
  }
});

test('a fresh database is created, migrated and seeded with the demo route', async () => {
  const db = openDatabase({ path: tempDbPath() });
  const seeded = seedDemoDeliveries(db);
  assert.equal(seeded, true);

  const store = createSqliteStore(db);
  const deliveries = await store.list();
  assert.equal(deliveries.length, 4);
  assert.equal(deliveries[0].id, 'DLV-1042');

  // Shape the mobile app depends on must be identical to the demo store.
  const one = await store.get('DLV-1042');
  assert.equal(one.customer.firstName, 'Sanne');
  assert.equal(one.customer.id, 'CUS-8821');
  assert.equal(one.address.line1, '18 Kanalstraat');
  assert.ok(Array.isArray(one.notes) && one.notes.length >= 2);
  assert.ok(Array.isArray(one.events) && one.events.length >= 1);
  assert.ok(Array.isArray(one.history));
  assert.equal(one.driverId, 'DRV-77');

  // Seeding twice must not duplicate the demo data.
  assert.equal(seedDemoDeliveries(db), false);
  assert.equal((await store.list()).length, 4);
  db.close();
});

test('every demo delivery describes the goods with a name and a photo', async () => {
  const db = openDatabase({ path: tempDbPath() });
  seedDemoDeliveries(db);

  const deliveries = await createSqliteStore(db).list();
  assert.equal(deliveries.length, 4);
  for (const delivery of deliveries) {
    assert.ok(delivery.item, `${delivery.id} must say what is being delivered`);
    assert.ok(delivery.item.name.trim().length > 0, `${delivery.id} has a name`);
    assert.ok(delivery.item.category, `${delivery.id} has a category`);
    assert.match(delivery.item.imageUrl, /^https:\/\//, `${delivery.id} links a remote photo`);
  }

  assert.equal(deliveries[0].item.name, 'Espresso machine');
  db.close();
});

test('a database from before the item column is backfilled on boot', async () => {
  const file = tempDbPath();

  const firstRun = openDatabase({ path: file });
  seedDemoDeliveries(firstRun);
  // Simulate rows written by the previous release: goods never described.
  firstRun.prepare('UPDATE deliveries SET item_json = NULL').run();
  assert.equal(
    Number(firstRun.prepare('SELECT COUNT(*) AS n FROM deliveries WHERE item_json IS NULL').get().n),
    4,
  );
  firstRun.close();

  const reopened = openDatabase({ path: file });
  assert.equal(backfillDemoItems(reopened), 4);
  assert.equal(backfillDemoItems(reopened), 0, 'the backfill is idempotent');

  const one = await createSqliteStore(reopened).get('DLV-1043');
  assert.equal(one.item.name, '46-inch LED TV');
  assert.equal(one.item.sku, 'SKU-TV-4608');
  reopened.close();
});

test('delivery status changes persist across a restart', async () => {
  const file = tempDbPath();

  // --- first boot -----------------------------------------------------
  let db = openDatabase({ path: file });
  seedDemoDeliveries(db);
  let store = createSqliteStore(db);
  await store.updateStatus('DLV-1044', 'delivered', {
    label: 'Handed over in person',
    changedBy: 'DRV-77',
  });
  db.close();

  // --- restart --------------------------------------------------------
  db = openDatabase({ path: file });
  store = createSqliteStore(db);
  const reopened = await store.get('DLV-1044');
  assert.equal(reopened.status, 'delivered');
  assert.ok(reopened.events.some((event) => event.type === 'delivered'));

  // The audit trail lives in its own table.
  const history = db
    .prepare('SELECT * FROM delivery_status_history WHERE delivery_id = ?')
    .all('DLV-1044');
  assert.equal(history.length, 1);
  assert.equal(history[0].to_status, 'delivered');
  assert.equal(history[0].from_status, 'pending');
  assert.equal(history[0].changed_by, 'DRV-77');

  db.close();
});

test('sent messages persist across a restart and keep the MSG- id format', async () => {
  const file = tempDbPath();

  let db = openDatabase({ path: file });
  seedDemoDeliveries(db);
  let store = createSqliteStore(db);

  const first = await store.sendMessage({
    deliveryId: 'DLV-1042',
    channel: 'sms',
    recipient: 'Sanne',
    body: 'Hi Sanne, your driver will use the access instructions from your note. See you shortly - ref DLV-1042.',
    action: 'follow_access_instructions',
    sentBy: 'DRV-77',
  });
  assert.match(first.messageId, /^MSG-\d{4}$/);
  assert.equal(first.messageId, 'MSG-0001');
  db.close();

  db = openDatabase({ path: file });
  store = createSqliteStore(db);
  const outbox = await store.outbox();
  assert.equal(outbox.length, 1);
  assert.equal(outbox[0].messageId, 'MSG-0001');
  assert.equal(outbox[0].deliveryId, 'DLV-1042');
  assert.equal(outbox[0].sentBy, 'DRV-77');
  assert.ok(outbox[0].sentAt);

  // New messages continue the sequence after the restart.
  const second = await store.sendMessage({
    deliveryId: 'DLV-1043',
    channel: 'whatsapp',
    recipient: 'Marco',
    body: 'Hi Marco, your parcel was inspected and we will bring a replacement box on the next run - ref DLV-1043.',
    sentBy: 'DRV-77',
  });
  assert.equal(second.messageId, 'MSG-0002');
  db.close();
});

test('users and sessions persist across a restart', async () => {
  const file = tempDbPath();

  let db = openDatabase({ path: file });
  let auth = createSqliteAuthStore(db);
  await seedUsers(auth, { log: { info() {}, warn() {} } });

  const token = 'restart-token';
  await auth.createSession({
    tokenHash: hashToken(token),
    userId: 'DRV-77',
    expiresAt: new Date(Date.now() + 60_000).toISOString(),
  });

  const emailCase = 'DRIVER@FLEET.LOCAL';
  const user = await auth.findUserByEmail(emailCase);
  assert.ok(user, 'e-mail lookup must be case-insensitive');
  assert.equal(user.role, 'driver');
  assert.ok(user.passwordHash.startsWith('scrypt:'));
  db.close();

  // --- restart --------------------------------------------------------
  db = openDatabase({ path: file });
  auth = createSqliteAuthStore(db);
  assert.equal(await auth.countUsers(), 2);

  const session = await auth.findSession(hashToken(token));
  assert.ok(session, 'session must survive a restart');
  assert.equal(session.userId, 'DRV-77');

  await auth.deleteSession(hashToken(token));
  assert.equal(await auth.findSession(hashToken(token)), null);
  db.close();
});

test('an expired session is dropped from the database on read', async () => {
  const db = openDatabase({ path: ':memory:' });
  const auth = createSqliteAuthStore(db);
  await seedUsers(auth, { log: { info() {}, warn() {} } });

  await auth.createSession({
    tokenHash: hashToken('old-token'),
    userId: 'DRV-77',
    expiresAt: new Date(Date.now() - 1000).toISOString(),
  });

  assert.equal(await auth.findSession(hashToken('old-token')), null);
  assert.equal(
    Number(db.prepare('SELECT COUNT(*) AS n FROM sessions').get().n),
    0,
    'expired row removed',
  );
  db.close();
});

test('the HTTP API keeps status changes and messages after a full restart', async () => {
  const file = tempDbPath();

  // --- boot 1: sign in, change a status, send a message ---------------
  const boot1 = await startTestApp({ db: openDatabase({ path: file }) });
  let boot2;
  try {
    const login1 = await boot1.login();
    assert.equal(login1.status, 200);
    const token = login1.body.token;

    const patch = await fetch(`${boot1.base}/api/v1/deliveries/DLV-1043/status`, {
      method: 'PATCH',
      headers: boot1.auth(token, { 'content-type': 'application/json' }),
      body: JSON.stringify({ status: 'failed', label: 'Recipient unreachable' }),
    });
    assert.equal(patch.status, 200);

    const send = await fetch(`${boot1.base}/api/v1/agent/messages`, {
      method: 'POST',
      headers: boot1.auth(token, { 'content-type': 'application/json' }),
      body: JSON.stringify({
        deliveryId: 'DLV-1043',
        channel: 'sms',
        recipient: 'Marco',
        body: 'Hi Marco, we could not reach you today - the parcel is safe at the depot, reply RESCHEDULE to pick a new time - ref DLV-1043.',
      }),
    });
    assert.equal(send.status, 201);
    const messageId = (await send.json()).messageId;

    await boot1.close(); // "restart": process gone, file remains

    // --- boot 2: same file, fresh process state ------------------------
    boot2 = await startTestApp({ db: openDatabase({ path: file }) });

    // The bearer token issued before the restart still works: sessions persist.
    const deliveries = await (
      await fetch(`${boot2.base}/api/v1/deliveries`, { headers: boot2.auth(token) })
    ).json();
    assert.equal(deliveries.error, undefined, 'list response has no error field');
    const failed = deliveries.deliveries.find((d) => d.id === 'DLV-1043');
    assert.equal(failed.status, 'failed');

    const outbox = await (
      await fetch(`${boot2.base}/api/v1/messages/outbox`, { headers: boot2.auth(token) })
    ).json();
    assert.ok(outbox.messages.some((m) => m.messageId === messageId));

    // And the session is revocable after the restart, too.
    const logout = await fetch(`${boot2.base}/api/v1/auth/logout`, {
      method: 'POST',
      headers: boot2.auth(token),
    });
    assert.equal(logout.status, 200);
    const afterLogout = await fetch(`${boot2.base}/api/v1/deliveries`, {
      headers: boot2.auth(token),
    });
    assert.equal(afterLogout.status, 401);
  } finally {
    await boot1.close();
    await boot2?.close();
  }
  assert.equal(TEST_DRIVER.email.includes('@'), true);
});
