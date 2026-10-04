/**
 * The single e-mail rule for the service.
 *
 * Sign-up used to validate on one rule, each auth store normalised with its
 * own, and the mobile app used a third - looser - one. A driver could pass the
 * form and still be answered 422 with a bare `enter a valid e-mail address`.
 *
 * Everything now shares this module: the register route validates against it,
 * and both stores normalise with it, so what is validated, what is stored and
 * what is looked up can never drift apart again.
 */

/**
 * Shape an e-mail must have: something, an `@`, then something containing a
 * dot. No whitespace anywhere - a space is always a keyboard or paste typo.
 */
export const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Canonical form of an address: strip whitespace (never legal in an e-mail)
 * and lower case, so `  Jane.Doe@Gmail ` and `jane.doe@gmail` are the same
 * account rather than two.
 */
export function normalizeEmail(email) {
  return String(email ?? '').replace(/\s+/g, '').toLowerCase();
}

/** True when [email] survives normalisation into a valid address. */
export function isValidEmail(email) {
  return EMAIL_RE.test(normalizeEmail(email));
}

export default { EMAIL_RE, normalizeEmail, isValidEmail };
