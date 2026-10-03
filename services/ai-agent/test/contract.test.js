import test from 'node:test';
import assert from 'node:assert/strict';

import { startTestApp, TEST_ADMIN } from './helpers.js';

/** Boots the service with the seeded driver still awaiting the agreement. */
async function unsignedDriverApp() {
  return startTestApp({ signDriver: false });
}

async function get(app, path, token, headers = {}) {
  const response = await fetch(`${app.base}${path}`, { headers: app.auth(token, headers) });
  return { status: response.status, body: await response.json().catch(() => ({})) };
}

async function post(app, path, token, payload, headers = {}) {
  const response = await fetch(`${app.base}${path}`, {
    method: 'POST',
    headers: app.auth(token, { 'content-type': 'application/json', ...headers }),
    body: JSON.stringify(payload),
  });
  return { status: response.status, body: await response.json().catch(() => ({})) };
}

test('the agreement is readable by an unsigned driver and 401 without a session', async () => {
  const app = await unsignedDriverApp();
  try {
    const anonymous = await fetch(`${app.base}/api/v1/contract`);
    assert.equal(anonymous.status, 401);

    const login = await app.login();
    assert.equal(login.status, 200);
    assert.equal(login.body.driver.contractSigned, false, 'a fresh session is unsigned');

    const { status, body } = await get(app, '/api/v1/contract', login.body.token);
    assert.equal(status, 200);
    assert.equal(body.signed, false);
    assert.equal(body.version, '1.0');
    assert.ok(Array.isArray(body.sections) && body.sections.length >= 5);
    assert.ok(
      body.sections.some((section) => /dispatch/i.test(section.body)),
      'the agreement says how work is assigned',
    );
  } finally {
    await app.close();
  }
});

test('an unsigned driver is locked out of dispatched work but never dead-ended', async () => {
  const app = await unsignedDriverApp();
  try {
    const login = await app.login();
    const token = login.body.token;

    // Locked out: no route, no stop, no mutation, no feed.
    for (const path of ['/api/v1/deliveries', '/api/v1/deliveries/DLV-1042', '/api/v1/notifications']) {
      const { status, body } = await get(app, path, token);
      assert.equal(status, 403, `${path} is gated`);
      assert.equal(body.error, 'driver contract not signed');
    }

    const patched = await fetch(`${app.base}/api/v1/deliveries/DLV-1042/status`, {
      method: 'PATCH',
      headers: app.auth(token, { 'content-type': 'application/json' }),
      body: JSON.stringify({ status: 'delivered' }),
    });
    assert.equal(patched.status, 403);

    // ...but the way out is always reachable.
    assert.equal((await get(app, '/api/v1/contract', token)).status, 200);
    assert.equal((await get(app, '/api/v1/auth/me', token)).status, 200);
  } finally {
    await app.close();
  }
});

test('signing requires a name and an explicit acknowledgement', async () => {
  const app = await unsignedDriverApp();
  try {
    const login = await app.login();
    const token = login.body.token;

    const noAck = await post(app, '/api/v1/contract/sign', token, {
      signatureName: 'Demo Driver',
    });
    assert.equal(noAck.status, 422);
    assert.match(noAck.body.error, /confirm/i);

    const noName = await post(app, '/api/v1/contract/sign', token, {
      signatureName: ' ',
      acknowledged: true,
    });
    assert.equal(noName.status, 422);
    assert.match(noName.body.error, /full name/i);

    const tooLong = await post(app, '/api/v1/contract/sign', token, {
      signatureName: 'x'.repeat(200),
      acknowledged: true,
    });
    assert.equal(tooLong.status, 422);

    // Nothing was recorded by the rejected attempts.
    const { body } = await get(app, '/api/v1/contract', token);
    assert.equal(body.signed, false);
  } finally {
    await app.close();
  }
});

test('signing records the agreement and the company dispatches the open route', async () => {
  const app = await unsignedDriverApp();
  try {
    const login = await app.login();
    const token = login.body.token;

    // Before: the dispatch board is an open pool nobody owns.
    const before = await get(app, '/api/v1/deliveries', token);
    assert.equal(before.status, 403);

    const signed = await post(app, '/api/v1/contract/sign', token, {
      signatureName: 'Demo Driver',
      acknowledged: true,
    });
    assert.equal(signed.status, 201);
    assert.equal(signed.body.alreadySigned, false);
    assert.equal(signed.body.contract.signatureName, 'Demo Driver');
    assert.equal(signed.body.contract.version, '1.0');
    assert.ok(!Number.isNaN(Date.parse(signed.body.contract.signedAt)));
    assert.deepEqual(
      signed.body.dispatch.deliveryIds,
      ['DLV-1042', 'DLV-1043', 'DLV-1044', 'DLV-1045', 'DLV-1046', 'DLV-1047', 'DLV-1048', 'DLV-1049', 'DLV-1050', 'DLV-1051'],
      'every open stop is dispatched in route order',
    );
    assert.equal(signed.body.dispatch.assigned, 10);

    // After: the same session now sees the work, and reports itself as signed.
    const after = await get(app, '/api/v1/deliveries', token);
    assert.equal(after.status, 200);
    assert.equal(after.body.count, 10);
    assert.ok(
      after.body.deliveries.every((d) => d.driverId === login.body.driver.id),
      'every stop now belongs to the signer',
    );

    const me = await get(app, '/api/v1/auth/me', token);
    assert.equal(me.body.driver.contractSigned, true);

    const contract = await get(app, '/api/v1/contract', token);
    assert.equal(contract.body.signed, true);
    assert.equal(contract.body.contract.signatureName, 'Demo Driver');
  } finally {
    await app.close();
  }
});

test('signing is idempotent - one driver, one agreement', async () => {
  const app = await unsignedDriverApp();
  try {
    const login = await app.login();
    const token = login.body.token;

    const first = await post(app, '/api/v1/contract/sign', token, {
      signatureName: 'Demo Driver',
      acknowledged: true,
    });
    assert.equal(first.status, 201);
    assert.equal(first.body.dispatch.assigned, 10);

    const second = await post(app, '/api/v1/contract/sign', token, {
      signatureName: 'Somebody Else',
      acknowledged: true,
    });
    assert.equal(second.status, 200);
    assert.equal(second.body.alreadySigned, true);
    assert.equal(second.body.contract.signatureName, 'Demo Driver', 'the original holds');
    assert.equal(second.body.dispatch.assigned, 0, 'nothing new to dispatch');

    const { body } = await get(app, '/api/v1/deliveries', token);
    assert.equal(body.count, 10, 'work was not duplicated');
  } finally {
    await app.close();
  }
});

test('each driver claims their own batch of stops', async () => {
  const app = await unsignedDriverApp();
  try {
    // The established driver claims the first batch of the open pool.
    const first = await app.login();
    assert.equal((await app.signContract(first.body.token)).status, 201);

    const registered = await fetch(`${app.base}/api/v1/auth/register`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        name: 'Second Driver',
        email: 'second@example.com',
        password: 'second-driver-pass',
      }),
    });
    assert.equal(registered.status, 201);
    const secondBody = await registered.json();
    assert.equal(secondBody.driver.contractSigned, false, 'a new signup starts unsigned');

    const token2 = secondBody.token;
    assert.equal(
      (await get(app, '/api/v1/deliveries', token2)).status,
      403,
      'a new driver cannot read work before signing',
    );

    const signed = await post(app, '/api/v1/contract/sign', token2, {
      signatureName: 'Second Driver',
      acknowledged: true,
    });
    assert.equal(signed.status, 201);
    assert.equal(signed.body.dispatch.assigned, 10, 'they claim the next batch');
    assert.deepEqual(
      signed.body.dispatch.deliveryIds,
      ['DLV-1052', 'DLV-1053', 'DLV-1054', 'DLV-1055', 'DLV-1056', 'DLV-1057', 'DLV-1058', 'DLV-1059', 'DLV-1060', 'DLV-1061'],
      'batch two is the next ten stops in route order',
    );

    const mine = await get(app, '/api/v1/deliveries', token2);
    assert.equal(mine.body.count, 10, 'they only ever see their own route');
    assert.ok(
      mine.body.deliveries.every((stop) => stop.driverId === secondBody.driver.id),
      'every stop belongs to the second driver',
    );

    const theirs = await get(app, '/api/v1/deliveries', first.body.token);
    assert.equal(theirs.body.count, 10, "the first driver's route is untouched");

    const shared = mine.body.deliveries.filter((stop) =>
      theirs.body.deliveries.some((other) => other.id === stop.id),
    );
    assert.deepEqual(shared, [], 'no stop is ever dispatched to two drivers');

    // The board is deeper than two routes: a third driver claims batch three
    // instead of being told there is nothing left to deliver.
    const third = await fetch(`${app.base}/api/v1/auth/register`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        name: 'Third Driver',
        email: 'third@example.com',
        password: 'third-driver-pass',
      }),
    });
    assert.equal(third.status, 201);
    const token3 = (await third.json()).token;

    const thirdSigned = await post(app, '/api/v1/contract/sign', token3, {
      signatureName: 'Third Driver',
      acknowledged: true,
    });
    assert.equal(thirdSigned.status, 201);
    assert.equal(thirdSigned.body.dispatch.assigned, 10, 'batch three is still on the board');
    assert.deepEqual(
      thirdSigned.body.dispatch.deliveryIds,
      ['DLV-1062', 'DLV-1063', 'DLV-1064', 'DLV-1065', 'DLV-1066', 'DLV-1067', 'DLV-1068', 'DLV-1069', 'DLV-1070', 'DLV-1071'],
      'batch three is the next ten stops in route order',
    );

    const thirdStops = (await get(app, '/api/v1/deliveries', token3)).body.deliveries;
    const earlier = [...mine.body.deliveries, ...theirs.body.deliveries];
    assert.deepEqual(
      thirdStops.filter((stop) => earlier.some((other) => other.id === stop.id)),
      [],
      'the three routes are disjoint',
    );
  } finally {
    await app.close();
  }
});

test('a driver cannot read or change another driver - even with a forged query', async () => {
  const app = await startTestApp(); // seeded driver already signed
  try {
    const seeded = await app.login();
    const token = seeded.body.token;

    const second = await fetch(`${app.base}/api/v1/auth/register`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        name: 'Second Driver',
        email: 'other@example.com',
        password: 'second-driver-pass',
      }),
    });
    const otherToken = (await second.json()).token;

    // Signed, and therefore past the gate - but that grants no ownership of
    // somebody else's stops, which is what the checks below actually prove.
    assert.equal((await app.signContract(otherToken)).status, 201);

    // Same 404 as a typo'd id, so a stop cannot be probed for.
    const theirs = await get(app, '/api/v1/deliveries/DLV-1042', otherToken);
    assert.equal(theirs.status, 404);

    const patch = await fetch(`${app.base}/api/v1/deliveries/DLV-1042/status`, {
      method: 'PATCH',
      headers: app.auth(otherToken, { 'content-type': 'application/json' }),
      body: JSON.stringify({ status: 'delivered' }),
    });
    assert.equal(patch.status, 404, 'a stop can only be changed by its driver');

    // Forging ?driverId does not widen a driver's view either: the answer is
    // exactly what their session already returns, never the other route.
    const own = await get(app, '/api/v1/deliveries', otherToken);
    const forged = await get(app, '/api/v1/deliveries?driverId=DRV-77', otherToken);
    assert.deepEqual(
      forged.body.deliveries.map((stop) => stop.id),
      own.body.deliveries.map((stop) => stop.id),
      'the query parameter is ignored for drivers',
    );
    assert.ok(
      forged.body.deliveries.every((stop) => stop.driverId !== 'DRV-77'),
      "the seeded driver's stops are never exposed",
    );
    assert.ok(
      forged.body.deliveries.every((stop) => stop.id !== 'DLV-1042'),
      "the seeded driver's route does not leak in",
    );
  } finally {
    await app.close();
  }
});

test('the company keeps the overview: an admin sees every stop', async () => {
  const app = await startTestApp();
  try {
    const admin = await app.login(TEST_ADMIN.email, TEST_ADMIN.password);
    assert.equal(admin.status, 200);

    const { status, body } = await get(app, '/api/v1/deliveries', admin.body.token);
    assert.equal(status, 200);
    assert.equal(body.count, 30, 'admins are not scoped to one route');

    // The admin is exempt from the agreement gate - they are the company.
    const stats = await get(app, '/api/v1/stats', admin.body.token);
    assert.equal(stats.status, 200);
    assert.equal(stats.body.totals.notifications, 12, 'dispatch feed follows the assignments');
  } finally {
    await app.close();
  }
});

test('the demo dispatch feed only appears once work is actually assigned', async () => {
  const app = await unsignedDriverApp();
  try {
    const login = await app.login();
    const token = login.body.token;

    const before = await get(app, '/api/v1/notifications', token);
    assert.equal(before.status, 403, 'nothing to announce before signing');

    await app.signContract(token);

    const after = await get(app, '/api/v1/notifications', token);
    assert.equal(after.status, 200);
    assert.ok(after.body.notifications.length > 0, 'the company announces the assigned stops');
    assert.ok(
      after.body.notifications.some((n) => n.type === 'delivery_assigned'),
      'assignment notifications are created at dispatch time',
    );
  } finally {
    await app.close();
  }
});
