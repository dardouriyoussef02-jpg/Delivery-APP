import test from 'node:test';
import assert from 'node:assert/strict';

import { startTestApp, TEST_DRIVER } from './helpers.js';

async function stats(app, token) {
  const response = await fetch(`${app.base}/api/v1/stats`, {
    headers: app.auth(token),
  });
  return { status: response.status, body: await response.json().catch(() => ({})) };
}

test('the stats endpoint requires a session', async () => {
  const app = await startTestApp();
  try {
    const response = await fetch(`${app.base}/api/v1/stats`);
    assert.equal(response.status, 401);
  } finally {
    await app.close();
  }
});

test("a signed-in driver gets 403 - stats are admin-only", async () => {
  const app = await startTestApp();
  try {
    const login = await app.login(); // seeded driver (role: driver)
    assert.equal(login.status, 200);

    const { status, body } = await stats(app, login.body.token);
    assert.equal(status, 403);
    assert.equal(body.error, 'admin role required');
  } finally {
    await app.close();
  }
});

test('the admin sees totals aggregated from the database', async () => {
  const app = await startTestApp();
  try {
    const admin = await app.login(
      (process.env.SEED_ADMIN_EMAIL ?? 'admin@fleet.local').toLowerCase(),
      process.env.SEED_ADMIN_PASSWORD ?? 'admin-test-pass',
    );
    assert.equal(admin.status, 200);

    const { status, body } = await stats(app, admin.body.token);
    assert.equal(status, 200);
    assert.equal(body.source, 'database');
    assert.ok(!Number.isNaN(Date.parse(body.generatedAt)));

    // Seeded dispatch pool: 30 stops / 30 customers / 2 active users (driver+admin).
    // Three batches of ten sit on the board, but only the first signer's batch
    // is assigned, so `perDriver` below stays at 10.
    assert.equal(body.totals.deliveries, 30);
    assert.equal(body.totals.customers, 30);
    assert.equal(body.totals.drivers, 2);
    assert.equal(body.totals.messagesSent, 0);
    assert.equal(body.totals.notifications, 12);

    const statusSum = Object.values(body.byStatus).reduce((sum, n) => sum + n, 0);
    assert.equal(statusSum, body.totals.deliveries, 'byStatus adds up');
    assert.deepEqual(Object.keys(body.byStatus).sort(), [
      'delivered',
      'failed',
      'in_transit',
      'pending',
    ]);

    // Nothing delivered yet: honest zeroes, not made-up numbers.
    assert.equal(body.completion.completionRate, 0);
    assert.deepEqual(body.deliveryTime, {
      sampleSize: 0,
      averageMinutes: null,
      fastestMinutes: null,
      slowestMinutes: null,
    });
    assert.equal(Array.isArray(body.recentActivity), true);

    const demoDriver = body.perDriver.find((row) => row.driverId === 'DRV-77');
    assert.ok(demoDriver, 'the demo driver is listed');
    assert.equal(demoDriver.assigned, 10);
    assert.equal(demoDriver.delivered, 0);
    assert.equal(demoDriver.averageMinutes, null);
  } finally {
    await app.close();
  }
});

test('stats move when the database changes (status + sent message)', async () => {
  const app = await startTestApp();
  try {
    const admin = await app.login(
      (process.env.SEED_ADMIN_EMAIL ?? 'admin@fleet.local').toLowerCase(),
      process.env.SEED_ADMIN_PASSWORD ?? 'admin-test-pass',
    );
    const driver = await app.login(TEST_DRIVER.email, TEST_DRIVER.password);

    // A real completion and a real sent message...
    const patch = await fetch(`${app.base}/api/v1/deliveries/DLV-1045/status`, {
      method: 'PATCH',
      headers: app.auth(driver.body.token, { 'content-type': 'application/json' }),
      body: JSON.stringify({ status: 'delivered', label: 'Handed over in person' }),
    });
    assert.equal(patch.status, 200);

    const sent = await fetch(`${app.base}/api/v1/agent/messages`, {
      method: 'POST',
      headers: app.auth(driver.body.token, { 'content-type': 'application/json' }),
      body: JSON.stringify({
        deliveryId: 'DLV-1045',
        channel: 'sms',
        recipient: 'Amina',
        body: 'Hi Amina, your parcel was delivered in person - thank you for your patience - ref DLV-1045.',
      }),
    });
    assert.equal(sent.status, 201);

    // ...show up in the next aggregation.
    const { body } = await stats(app, admin.body.token);

    assert.equal(body.byStatus.delivered, 1);
    assert.equal(
      body.completion.finished,
      body.byStatus.delivered + body.byStatus.failed,
      'finished = delivered + failed',
    );
    assert.ok(body.completion.finished >= 1);
    // delivered / total, rounded to four decimals: 1 of 30 stops.
    assert.equal(body.completion.completionRate, 0.0333);
    assert.equal(body.totals.messagesSent, 1);

    assert.equal(body.deliveryTime.sampleSize, 1);
    assert.ok(body.deliveryTime.averageMinutes >= 0);
    assert.ok(body.deliveryTime.fastestMinutes <= body.deliveryTime.slowestMinutes);

    const demoDriver = body.perDriver.find((row) => row.driverId === 'DRV-77');
    assert.equal(demoDriver.delivered, 1);
    assert.ok(demoDriver.averageMinutes >= 0);

    assert.equal(body.recentActivity[0].deliveryId, 'DLV-1045');
    assert.equal(body.recentActivity[0].toStatus, 'delivered');
    assert.equal(body.recentActivity[0].changedBy, 'DRV-77');
  } finally {
    await app.close();
  }
});
