import { randomBytes } from 'node:crypto';
import config from '../config.js';
import { hashPassword } from './passwords.js';

/**
 * Builds the first-run user list from environment configuration.
 *
 * No password is ever hard-coded: values come from the environment (`.env` in
 * development). When a password is not configured we generate a strong random
 * one and print it once, so a fresh install can still be signed into without
 * silently accepting any credentials.
 *
 * The driver id matches the demo dataset (`DRV-77`) so the seeded deliveries
 * belong to the seeded driver.
 */
export function loadSeedUsers({ log = console } = {}) {
  const seed = config.auth.seed;

  const driverPassword = seed.driverPassword || generatePassword('driver');
  const adminPassword = seed.adminPassword || generatePassword('admin');

  if (!seed.driverPassword) {
    log.warn(`[auth] SEED_DRIVER_PASSWORD is not set - generated driver password: ${driverPassword}`);
  }
  if (!seed.adminPassword) {
    log.warn(`[auth] SEED_ADMIN_PASSWORD is not set - generated admin password: ${adminPassword}`);
  }

  return {
    users: [
      {
        id: seed.driverId,
        email: seed.driverEmail,
        name: 'Demo Driver',
        role: 'driver',
        passwordHash: hashPassword(driverPassword),
      },
      {
        id: seed.adminId,
        email: seed.adminEmail,
        name: 'Fleet Admin',
        role: 'admin',
        passwordHash: hashPassword(adminPassword),
      },
    ],
    /** Plaintext passwords, only for logging at first boot - never stored. */
    generated: {
      driverEmail: seed.driverEmail,
      driverPassword,
      adminEmail: seed.adminEmail,
      adminPassword,
    },
  };
}

/** Seeds the store once (no-op when users already exist). */
export async function seedUsers(auth, { log = console } = {}) {
  if ((await auth.countUsers()) > 0) return false;
  const { users } = loadSeedUsers({ log });
  await auth.createUsers(users);
  log.info(`[auth] seeded ${users.length} users (${users.map((u) => u.role).join(', ')})`);
  return true;
}

function generatePassword(role) {
  return `dev-${role}-${randomBytes(6).toString('hex')}`;
}

export default { loadSeedUsers, seedUsers };
