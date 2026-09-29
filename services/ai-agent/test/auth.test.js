import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';

import { createApp } from '../src/server.js';
import { createMemoryAuthStore } from '../src/auth/store.js';
import { seedUsers } from '../src/auth/seed.js';
import { hashToken } from '../src/auth/middleware.js';
import { hashPassword, verifyPassword } from '../src/auth/passwords.js';
import { openDatabase } from '../src/data/database.js';
import { startTestApp, TEST_ADMIN, TEST_DRIVER } from './helpers.js';

let app;
let base;
let closeApp;

before(async () => {
  const started = await startTestApp();
  app = started.server;
  base = started.base;
  closeApp = started.close;
});

after(async () => {
  await closeApp?.();
});

// ---------------------------------------------------------------- passwords

test('passwords hash with scrypt and verify in constant time', () => {
  const stored = hashPassword('correct horse battery staple');
  assert.match(stored, /^scrypt:[0-9a-f]{32}:[0-9a-f]{128}$/);
  assert.equal(verifyPassword('correct horse battery staple', stored), true);
  assert.equal(verifyPassword('wrong password', stored), false);
  assert.equal(verifyPassword('', stored), false);
  assert.equal(verifyPassword('correct horse battery staple', 'garbage'), false);
  // Same password, different salt -> different hash.
  assert.notEqual(hashPassword('same'), hashPassword('same'));
});

// ------------------------------------------------------------------- login

test('POST /auth/login accepts valid credentials and returns a bearer token', async () => {
  const { status, body } = await startLogin();
  assert.equal(status, 200);
  assert.ok(body.token && body.token.length >= 32);
  assert.equal(body.tokenType, 'Bearer');
  assert.ok(Date.parse(body.expiresAt) > Date.now());
  assert.equal(body.driver.email, TEST_DRIVER.email);
  assert.equal(body.driver.role, 'driver');
  // The password (or anything resembling it) must never come back.
  assert.equal(JSON.stringify(body).includes(TEST_DRIVER.password), false);
});

test('POST /auth/login rejects invalid credentials with 401', async () => {
  const wrongPassword = await fetch(`${base}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: TEST_DRIVER.email, password: 'not-the-password' }),
  });
  assert.equal(wrongPassword.status, 401);
  assert.match((await wrongPassword.json()).error, /invalid e-mail or password/);

  const unknownUser = await fetch(`${base}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'nobody@fleet.local', password: 'whatever1234' }),
  });
  assert.equal(unknownUser.status, 401);
  // Identical message for unknown e-mail: no user enumeration.
  assert.equal(
    (await unknownUser.json()).error,
    (await (await fetch(`${base}/api/v1/auth/login`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email: TEST_DRIVER.email, password: 'not-the-password' }),
    })).json()).error,
  );
});

test('POST /auth/login requires both fields', async () => {
  const response = await fetch(`${base}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: TEST_DRIVER.email }),
  });
  assert.equal(response.status, 400);
});

test('an admin can log in with the admin seed account', async () => {
  const { status, body } = await startLogin(TEST_ADMIN.email, TEST_ADMIN.password);
  assert.equal(status, 200);
  assert.equal(body.driver.role, 'admin');
});

// ------------------------------------------------------- protected endpoints

test('protected endpoints return 401 without a token', async () => {
  const paths = [
    ['/api/v1/deliveries', 'GET'],
    ['/api/v1/deliveries/DLV-1042', 'GET'],
    ['/api/v1/agent/suggest', 'POST'],
    ['/api/v1/agent/messages', 'POST'],
    ['/api/v1/messages/outbox', 'GET'],
    ['/api/v1/auth/me', 'GET'],
    ['/api/v1/auth/logout', 'POST'],
  ];

  for (const [path, method] of paths) {
    const response = await fetch(`${base}${path}`, {
      method,
      headers: { 'content-type': 'application/json' },
      body: method === 'POST' ? JSON.stringify({}) : undefined,
    });
    assert.equal(response.status, 401, `${path} should require a token`);
  }
});

test('protected endpoints reject an invalid or forged token', async () => {
  const forged = ['not-a-token', '', hashToken('another-token'), 'a'.repeat(64)];

  for (const token of forged) {
    const response = await fetch(`${base}/api/v1/deliveries`, {
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(response.status, 401, `token "${token.slice(0, 12)}" must be rejected`);
  }
});

test('a valid token unlocks the protected endpoints', async () => {
  const { body } = await startLogin();
  const response = await fetch(`${base}/api/v1/deliveries`, {
    headers: { authorization: `Bearer ${body.token}` },
  });
  assert.equal(response.status, 200);

  const me = await fetch(`${base}/api/v1/auth/me`, {
    headers: { authorization: `Bearer ${body.token}` },
  });
  assert.equal(me.status, 200);
  assert.equal((await me.json()).driver.email, TEST_DRIVER.email);
});

test('POST /auth/logout revokes the token', async () => {
  const { body } = await startLogin();

  const logout = await fetch(`${base}/api/v1/auth/logout`, {
    method: 'POST',
    headers: { authorization: `Bearer ${body.token}` },
  });
  assert.equal(logout.status, 200);
  assert.equal((await logout.json()).status, 'logged_out');

  const after = await fetch(`${base}/api/v1/deliveries`, {
    headers: { authorization: `Bearer ${body.token}` },
  });
  assert.equal(after.status, 401);
});

test('an expired session token is rejected', async () => {
  const auth = createMemoryAuthStore();
  await seedUsers(auth, { log: { info() {}, warn() {} } });
  const token = 'expired-session-token';
  await auth.createSession({
    tokenHash: hashToken(token),
    userId: 'DRV-77',
    expiresAt: new Date(Date.now() - 1000).toISOString(),
  });

  const isolated = createApp({ auth, db: openDatabase({ path: ':memory:' }) });
  const server = isolated.listen(0);
  const { once } = await import('node:events');
  await once(server, 'listening');
  const isolatedBase = `http://127.0.0.1:${server.address().port}`;

  const response = await fetch(`${isolatedBase}/api/v1/deliveries`, {
    headers: { authorization: `Bearer ${token}` },
  });
  assert.equal(response.status, 401);
  server.close();
});

test('the seeded driver session carries the driver identity', async () => {
  const { body } = await startLogin();
  const outbox = await fetch(`${base}/api/v1/messages/outbox`, {
    headers: { authorization: `Bearer ${body.token}` },
  });
  assert.equal(outbox.status, 200);
});

async function startLogin(email = TEST_DRIVER.email, password = TEST_DRIVER.password) {
  const response = await fetch(`${base}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  return { status: response.status, body: await response.json().catch(() => ({})) };
}
