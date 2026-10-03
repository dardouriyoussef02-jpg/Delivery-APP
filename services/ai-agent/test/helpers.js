import { once } from 'node:events';
import { createApp } from '../src/server.js';
import { openDatabase } from '../src/data/database.js';

// Deterministic credentials no matter whether .env is present. The values are
// read by config.js lazily (seed getters), so setting them here is enough.
process.env.SEED_DRIVER_PASSWORD ||= 'driver-test-pass';
process.env.SEED_ADMIN_PASSWORD ||= 'admin-test-pass';

export const TEST_DRIVER = {
  email: (process.env.SEED_DRIVER_EMAIL ?? 'driver@fleet.local').toLowerCase(),
  password: process.env.SEED_DRIVER_PASSWORD,
};

export const TEST_ADMIN = {
  email: (process.env.SEED_ADMIN_EMAIL ?? 'admin@fleet.local').toLowerCase(),
  password: process.env.SEED_ADMIN_PASSWORD,
};

/**
 * Boots the service on an ephemeral port and returns small helpers so tests
 * stay focused on behaviour instead of boilerplate.
 *
 * The seeded driver starts out *already signed*, the way an established driver
 * would be, so existing tests keep exercising work rather than the onboarding
 * gate. Pass `signDriver: false` to get a fresh, unsigned driver.
 */
export async function startTestApp(options = {}) {
  const { signDriver = true, ...appOptions } = options;

  // Every test app gets its own throw-away database: no shared state between
  // parallel test files and no writes to the development database file.
  const db = appOptions.db ?? openDatabase({ path: ':memory:' });
  const server = createApp({ ...appOptions, db }).listen(0);
  await once(server, 'listening');
  const base = `http://127.0.0.1:${server.address().port}`;

  async function login(email = TEST_DRIVER.email, password = TEST_DRIVER.password) {
    const response = await fetch(`${base}/api/v1/auth/login`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });
    const body = await response.json().catch(() => ({}));
    return { status: response.status, body };
  }

  /** Merges the Authorization header into a fetch header bag. */
  const auth = (token, headers = {}) => ({
    ...(token ? { authorization: `Bearer ${token}` } : {}),
    ...headers,
  });

  /** Signs the partnership agreement; also dispatches the open demo route. */
  async function signContract(token, body = {}) {
    const response = await fetch(`${base}/api/v1/contract/sign`, {
      method: 'POST',
      headers: auth(token, { 'content-type': 'application/json' }),
      body: JSON.stringify({
        signatureName: 'Demo Driver',
        acknowledged: true,
        ...body,
      }),
    });
    const payload = await response.json().catch(() => ({}));
    return { status: response.status, body: payload };
  }

  if (signDriver) {
    const seeded = await login();
    if (seeded.status === 200) await signContract(seeded.body.token);
  }

  let closed = false;
  async function close() {
    if (closed) return;
    closed = true;
    server.closeIdleConnections?.();
    server.close();
    await once(server, 'close');
    try {
      db.close();
    } catch {
      // already closed
    }
  }

  return { server, base, login, auth, signContract, close };
}
