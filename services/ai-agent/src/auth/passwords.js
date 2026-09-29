import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';

/**
 * Password hashing with scrypt from Node's crypto module - no external
 * dependency, memory-hard, and the parameters are stored inside the hash so
 * they can be upgraded later without a migration.
 *
 * Stored format: `scrypt:<salt-hex>:<hash-hex>`
 */
const SCRYPT_KEYLEN = 64;

export function hashPassword(password, salt = randomBytes(16).toString('hex')) {
  if (typeof password !== 'string' || password.length === 0) {
    throw new Error('password must be a non-empty string');
  }
  const hash = scryptSync(password, salt, SCRYPT_KEYLEN).toString('hex');
  return `scrypt:${salt}:${hash}`;
}

/** Constant-time verification. Never throws on malformed input. */
export function verifyPassword(password, stored) {
  if (typeof password !== 'string' || typeof stored !== 'string') return false;

  const [scheme, salt, expectedHex] = stored.split(':');
  if (scheme !== 'scrypt' || !salt || !expectedHex) return false;

  const expected = Buffer.from(expectedHex, 'hex');
  if (expected.length !== SCRYPT_KEYLEN) return false;

  let candidate;
  try {
    candidate = scryptSync(password, salt, SCRYPT_KEYLEN);
  } catch {
    return false;
  }
  return timingSafeEqual(candidate, expected);
}

export default { hashPassword, verifyPassword };
