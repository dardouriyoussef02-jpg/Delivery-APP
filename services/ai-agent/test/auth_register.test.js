import test from 'node:test';
import assert from 'node:assert/strict';

import { startTestApp, TEST_DRIVER } from './helpers.js';

async function register(app, payload) {
  const response = await fetch(`${app.base}/api/v1/auth/register`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });
  return { status: response.status, body: await response.json().catch(() => ({})) };
}

test('a new driver registers with e-mail + password and is signed in', async () => {
  const app = await startTestApp();
  try {
    const created = await register(app, {
      name: 'Nina Courier',
      email: '  Nina@Courier.co ',
      password: 'strong-pass-1',
    });

    assert.equal(created.status, 201);
    assert.ok(created.body.token, 'a session token comes back immediately');
    assert.equal(created.body.tokenType, 'Bearer');
    assert.equal(created.body.driver.email, 'nina@courier.co', 'e-mail normalised');
    assert.equal(created.body.driver.role, 'driver');
    assert.equal(created.body.driver.name, 'Nina Courier');
    assert.match(created.body.driver.id, /^DRV-/);

    // The token really authenticates...
    const me = await fetch(`${app.base}/api/v1/auth/me`, {
      headers: app.auth(created.body.token),
    });
    assert.equal(me.status, 200);

    // ...and the credentials can be used to sign in again from scratch.
    const again = await app.login('nina@courier.co', 'strong-pass-1');
    assert.equal(again.status, 200);
    assert.equal(again.body.driver.id, created.body.driver.id);
  } finally {
    await app.close();
  }
});

test('a stray space cannot cost a driver their sign-up', async () => {
  const app = await startTestApp();
  try {
    // Keyboards and paste routinely leave whitespace behind. It is never legal
    // in an e-mail, so it gets cleaned up - not turned into a 422 the driver
    // has no way to decode.
    const created = await register(app, {
      name: 'Youssef Dardouri',
      email: '  Youssef .Dardouri@Gmail.com ',
      password: 'strong-pass-1',
    });

    assert.equal(created.status, 201, 'a stray space must not block sign-up');
    assert.equal(created.body.driver.email, 'youssef.dardouri@gmail.com');

    // The stored account is one address: the same driver signs back in.
    const again = await app.login(' Youssef.Dardouri@Gmail.COM ', 'strong-pass-1');
    assert.equal(again.status, 200);
    assert.equal(again.body.driver.id, created.body.driver.id);

    // And it is exactly one row - normalisation never forks an account.
    const repeat = await register(app, {
      name: 'Youssef Again',
      email: 'youssef.dardouri@gmail.com',
      password: 'another-pass-1',
    });
    assert.equal(repeat.status, 409);
  } finally {
    await app.close();
  }
});

test('invalid sign-ups are rejected with 422', async () => {
  const app = await startTestApp();
  try {
    const noName = await register(app, {
      email: 'ok@fleet.local',
      password: 'strong-pass-1',
    });
    assert.equal(noName.status, 422);
    assert.match(noName.body.error, /name/);

    const badEmail = await register(app, {
      name: 'Ok Driver',
      email: 'not-an-email',
      password: 'strong-pass-1',
    });
    assert.equal(badEmail.status, 422);
    assert.match(badEmail.body.error, /e-mail/);

    const shortPassword = await register(app, {
      name: 'Ok Driver',
      email: 'ok@fleet.local',
      password: 'short',
    });
    assert.equal(shortPassword.status, 422);
    assert.match(shortPassword.body.error, /8 characters/);

    // Nothing above was created.
    const retry = await register(app, {
      name: 'Ok Driver',
      email: 'ok@fleet.local',
      password: 'strong-pass-1',
    });
    assert.equal(retry.status, 201, 'failed attempts must not burn the e-mail');
  } finally {
    await app.close();
  }
});

test('the same e-mail cannot register twice (409, no user enumeration)', async () => {
  const app = await startTestApp();
  try {
    const first = await register(app, {
      name: 'First Driver',
      email: 'dupe@fleet.local',
      password: 'strong-pass-1',
    });
    assert.equal(first.status, 201);

    const second = await register(app, {
      name: 'Second Driver',
      email: 'DUPE@fleet.local',
      password: 'different-pass-1',
    });
    assert.equal(second.status, 409);
    assert.equal(second.body.error, 'an account with this e-mail already exists');
    assert.ok(!second.body.token, 'no token for a rejected sign-up');
  } finally {
    await app.close();
  }
});

test('the seeded fleet accounts cannot be taken over through sign-up', async () => {
  const app = await startTestApp();
  try {
    const taken = await register(app, {
      name: 'Impostor',
      email: TEST_DRIVER.email,
      password: 'hijacker-pass-1',
    });
    assert.equal(taken.status, 409);

    // The real driver still signs in with the real password.
    const legit = await app.login();
    assert.equal(legit.status, 200);
  } finally {
    await app.close();
  }
});

test('registration can never mint an admin', async () => {
  const app = await startTestApp();
  try {
    const sneaky = await register(app, {
      name: 'Role Admin',
      email: 'wannabe@fleet.local',
      password: 'strong-pass-1',
      role: 'admin',
    });

    assert.equal(sneaky.status, 201);
    assert.equal(sneaky.body.driver.role, 'driver');

    // The account is a plain driver on the stats endpoint too.
    const stats = await fetch(`${app.base}/api/v1/stats`, {
      headers: app.auth(sneaky.body.token),
    });
    assert.equal(stats.status, 403);
  } finally {
    await app.close();
  }
});

test('ALLOW_SIGNUP=false disables registration', async () => {
  const app = await startTestApp();
  process.env.ALLOW_SIGNUP = 'false';
  try {
    const refused = await register(app, {
      name: 'Blocked Driver',
      email: 'blocked@fleet.local',
      password: 'strong-pass-1',
    });
    assert.equal(refused.status, 403);
    assert.equal(refused.body.error, 'registration is disabled on this server');

    // Login keeps working while sign-up is off.
    const login = await app.login();
    assert.equal(login.status, 200);
  } finally {
    delete process.env.ALLOW_SIGNUP;
    await app.close();
  }
});
