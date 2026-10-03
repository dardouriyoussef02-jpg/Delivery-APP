import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { openDatabase } from '../src/data/database.js';
import { startTestApp, TEST_ADMIN, TEST_DRIVER } from './helpers.js';

/** GET helper: the driver's feed (optionally filtered). */
async function feed(app, token, query = '') {
  const response = await fetch(`${app.base}/api/v1/notifications${query}`, {
    headers: app.auth(token),
  });
  return { status: response.status, body: await response.json().catch(() => ({})) };
}

test('the notification feed requires a session', async () => {
  const app = await startTestApp();
  try {
    const response = await fetch(`${app.base}/api/v1/notifications`);
    assert.equal(response.status, 401);

    const forged = await fetch(`${app.base}/api/v1/notifications`, {
      headers: { authorization: 'Bearer not-a-real-token' },
    });
    assert.equal(forged.status, 401);
  } finally {
    await app.close();
  }
});

test('the driver gets the seeded demo feed with NTF ids and an unread count', async () => {
  const app = await startTestApp();
  try {
    const login = await app.login();
    assert.equal(login.status, 200);

    const { status, body } = await feed(app, login.body.token);
    assert.equal(status, 200);

    // 10 assignments + 1 route change + 1 customer note (all demo-sourced).
    assert.equal(body.notifications.length, 12);
    const types = new Set(body.notifications.map((item) => item.type));
    assert.deepEqual(
      [...types].sort(),
      ['assignment_changed', 'customer_update', 'delivery_assigned'],
    );
    assert.equal(body.unreadCount, 10, 'the two oldest assignments start read');

    for (const item of body.notifications) {
      assert.match(item.id, /^NTF-\d{4}$/);
      assert.ok(item.title && typeof item.body === 'string');
      assert.ok(item.deliveryId, 'demo notifications point at a delivery');
      assert.equal(item.source, 'demo');
      assert.ok(!Number.isNaN(Date.parse(item.createdAt)));
    }

    // Newest first: the customer note is the most recent event.
    assert.equal(body.notifications[0].type, 'customer_update');
    assert.equal(body.notifications[0].deliveryId, 'DLV-1043');
  } finally {
    await app.close();
  }
});

test('unread=1 returns only the unread rows', async () => {
  const app = await startTestApp();
  try {
    const login = await app.login();
    const { body } = await feed(app, login.body.token, '?unread=1');

    assert.equal(body.notifications.length, 10);
    assert.equal(body.notifications.every((item) => item.isRead === false), true);
    assert.equal(body.unreadCount, 10);
  } finally {
    await app.close();
  }
});

test('marking a notification read updates the count and is idempotent', async () => {
  const app = await startTestApp();
  try {
    const login = await app.login();
    const target = (await feed(app, login.body.token)).body.notifications[0];

    const first = await fetch(`${app.base}/api/v1/notifications/${target.id}/read`, {
      method: 'POST',
      headers: app.auth(login.body.token),
    });
    assert.equal(first.status, 200);
    const firstBody = await first.json();
    assert.equal(firstBody.notification.isRead, true);
    assert.equal(firstBody.unreadCount, 9);

    // Reading it again must not fail or double-count.
    const second = await fetch(`${app.base}/api/v1/notifications/${target.id}/read`, {
      method: 'POST',
      headers: app.auth(login.body.token),
    });
    assert.equal(second.status, 200);
    assert.equal((await second.json()).unreadCount, 9);

    // Unknown ids are 404.
    const missing = await fetch(`${app.base}/api/v1/notifications/NTF-9999/read`, {
      method: 'POST',
      headers: app.auth(login.body.token),
    });
    assert.equal(missing.status, 404);
  } finally {
    await app.close();
  }
});

test("another signed-in user cannot read or flip this driver's feed", async () => {
  const app = await startTestApp();
  try {
    const driver = await app.login();
    const admin = await app.login(TEST_ADMIN.email, TEST_ADMIN.password);
    assert.equal(admin.status, 200);

    const driverTarget = (await feed(app, driver.body.token)).body.notifications[0];

    // The admin has their own (empty) feed - scoping by session user id.
    const adminFeed = await feed(app, admin.body.token);
    assert.equal(adminFeed.status, 200);
    assert.equal(adminFeed.body.notifications.length, 0);
    assert.equal(adminFeed.body.unreadCount, 0);

    // ...and cannot mark the driver's notification as read.
    const steal = await fetch(`${app.base}/api/v1/notifications/${driverTarget.id}/read`, {
      method: 'POST',
      headers: app.auth(admin.body.token),
    });
    assert.equal(steal.status, 404);

    // The driver's feed is untouched.
    const stillUnread = (await feed(app, driver.body.token)).body;
    assert.equal(stillUnread.unreadCount, 10);
  } finally {
    await app.close();
  }
});

test('a failed stop raises a status_changed notification; delivered does not', async () => {
  const app = await startTestApp();
  try {
    const login = await app.login();
    const headers = app.auth(login.body.token, { 'content-type': 'application/json' });

    const failed = await fetch(`${app.base}/api/v1/deliveries/DLV-1045/status`, {
      method: 'PATCH',
      headers,
      body: JSON.stringify({ status: 'failed', label: 'Recipient unreachable' }),
    });
    assert.equal(failed.status, 200);

    const { body } = await feed(app, login.body.token);
    const statusNotes = body.notifications.filter((item) => item.type === 'status_changed');
    assert.equal(statusNotes.length, 1);
    assert.equal(statusNotes[0].deliveryId, 'DLV-1045');
    assert.equal(statusNotes[0].source, 'service', 'runtime events are service-sourced');
    assert.match(statusNotes[0].body, /Recipient unreachable/);
    assert.equal(body.unreadCount, 11);

    // A normal completion is not an alert.
    await fetch(`${app.base}/api/v1/deliveries/DLV-1045/status`, {
      method: 'PATCH',
      headers,
      body: JSON.stringify({ status: 'delivered', label: 'Handed over in person' }),
    });
    const after = await feed(app, login.body.token);
    assert.equal(
      after.body.notifications.filter((item) => item.type === 'status_changed').length,
      1,
    );
  } finally {
    await app.close();
  }
});

test('sending a message raises exactly one customer reply per delivery', async () => {
  const app = await startTestApp();
  try {
    const login = await app.login();
    const headers = app.auth(login.body.token, { 'content-type': 'application/json' });

    const send = (body) =>
      fetch(`${app.base}/api/v1/agent/messages`, {
        method: 'POST',
        headers,
        body: JSON.stringify(body),
      });

    const first = await send({
      deliveryId: 'DLV-1042',
      channel: 'sms',
      recipient: 'Sanne',
      body: 'Hi Sanne, your driver will use the access instructions from your note. See you shortly - ref DLV-1042.',
    });
    assert.equal(first.status, 201);

    let { body: items } = await feed(app, login.body.token);
    let replies = items.notifications.filter((item) => item.type === 'customer_reply');
    assert.equal(replies.length, 1);
    assert.equal(replies[0].deliveryId, 'DLV-1042');
    assert.equal(replies[0].source, 'demo');
    assert.match(replies[0].title, /Sanne/);

    // A second message to the same delivery must not spam the feed.
    await send({
      deliveryId: 'DLV-1042',
      channel: 'sms',
      recipient: 'Sanne',
      body: 'Hi Sanne, we are 10 minutes away and will ring the bell twice - ref DLV-1042.',
    });
    ({ body: items } = await feed(app, login.body.token));
    assert.equal(
      items.notifications.filter((item) => item.type === 'customer_reply').length,
      1,
    );

    // Another delivery gets its own reply.
    await send({
      deliveryId: 'DLV-1043',
      channel: 'whatsapp',
      recipient: 'Marco',
      body: 'Hi Marco, your parcel was inspected and we will bring a replacement box on the next run - ref DLV-1043.',
    });
    ({ body: items } = await feed(app, login.body.token));
    assert.equal(
      items.notifications.filter((item) => item.type === 'customer_reply').length,
      2,
    );
  } finally {
    await app.close();
  }
});

test('the feed and read-state survive a restart', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'delivery-ntf-'));
  const file = join(dir, 'delivery.db');

  try {
    // --- boot 1: read the feed, mark the newest one as read -------------
    const boot1 = await startTestApp({ db: openDatabase({ path: file }) });
    let token;
    let before;
    try {
      const login = await boot1.login();
      token = login.body.token;
      const seen = (await feed(boot1, token)).body;
      before = {
        ids: seen.notifications.map((item) => item.id).sort(),
        unread: seen.unreadCount,
      };
      assert.equal(before.ids.length, 12);

      const newest = seen.notifications[0];
      const mark = await fetch(`${boot1.base}/api/v1/notifications/${newest.id}/read`, {
        method: 'POST',
        headers: boot1.auth(token),
      });
      assert.equal(mark.status, 200);
      assert.equal((await mark.json()).unreadCount, before.unread - 1);
    } finally {
      await boot1.close();
    }

    // --- boot 2: same file, fresh process state -------------------------
    const boot2 = await startTestApp({ db: openDatabase({ path: file }) });
    try {
      // The session itself persisted, so the same bearer token still works.
      const seen = (await feed(boot2, token)).body;
      assert.deepEqual(
        seen.notifications.map((item) => item.id).sort(),
        before.ids,
        'same NTF ids after the restart',
      );
      assert.equal(seen.unreadCount, before.unread - 1, 'read-state persisted');

      const readRow = seen.notifications.find((item) => item.isRead === true);
      assert.ok(readRow, 'at least one row stays marked read');
      assert.equal(TEST_DRIVER.email.includes('@'), true);
    } finally {
      await boot2.close();
    }
  } finally {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {
      // best effort
    }
  }
});
