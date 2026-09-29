import { Router } from 'express';
import { randomBytes } from 'node:crypto';
import config from '../config.js';
import { hashPassword, verifyPassword } from '../auth/passwords.js';
import { hashToken } from '../auth/middleware.js';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Session endpoints.
 *
 *   POST /api/v1/auth/register -> creates a driver account (ALLOW_SIGNUP) and signs it in
 *   POST /api/v1/auth/login    -> issues a bearer token for a real credential check
 *   POST /api/v1/auth/logout   -> revokes the presented token
 *   GET  /api/v1/auth/me       -> the signed-in driver
 *
 * The mobile app stores the token in secure storage and sends it as
 * `Authorization: Bearer <token>` on every other call.
 */
export function createAuthRoutes({ auth, requireAuth }) {
  const router = Router();

  /**
   * Creates a driver account and immediately signs it in (same response shape
   * as login, HTTP 201).
   *
   * Guardrails, all enforced here because the client can never be trusted:
   *  - ALLOW_SIGNUP=false            -> 403
   *  - name/e-mail/password invalid  -> 422
   *  - e-mail already registered     -> 409 (also catches the UNIQUE race)
   *  - role is always `driver`       -> registration can never mint an admin
   */
  router.post('/auth/register', async (req, res, next) => {
    try {
      // Never race the first-run seeding of the user table.
      if (auth.ready) await auth.ready;

      if (!config.auth.allowSignup) {
        return res.status(403).json({ error: 'registration is disabled on this server' });
      }

      const { name, email, password } = req.body ?? {};
      const trimmedName = typeof name === 'string' ? name.trim() : '';
      const trimmedEmail = typeof email === 'string' ? email.trim().toLowerCase() : '';
      const plainPassword = typeof password === 'string' ? password : '';

      if (trimmedName.length < 2) {
        return res.status(422).json({ error: 'name must be at least 2 characters' });
      }
      if (!EMAIL_RE.test(trimmedEmail)) {
        return res.status(422).json({ error: 'enter a valid e-mail address' });
      }
      if (plainPassword.length < 8) {
        return res.status(422).json({ error: 'password must be at least 8 characters' });
      }

      if (await auth.findUserByEmail(trimmedEmail)) {
        return res.status(409).json({ error: 'an account with this e-mail already exists' });
      }

      const user = await auth.createUser({
        // Random id: unique without needing a counter, DRV- prefix matches
        // the seeded demo driver's shape.
        id: `DRV-${randomBytes(5).toString('hex').toUpperCase()}`,
        email: trimmedEmail,
        name: trimmedName,
        role: 'driver',
        passwordHash: hashPassword(plainPassword),
      });

      const token = randomBytes(32).toString('base64url');
      const expiresAt = new Date(Date.now() + config.auth.sessionTtlMs).toISOString();
      await auth.createSession({ tokenHash: hashToken(token), userId: user.id, expiresAt });

      return res.status(201).json({
        token,
        tokenType: 'Bearer',
        expiresAt,
        driver: publicUser(user),
      });
    } catch (error) {
      // Two identical sign-ups racing: the drivers table has UNIQUE(e-mail).
      if (/UNIQUE/i.test(error?.message ?? '')) {
        return res.status(409).json({ error: 'an account with this e-mail already exists' });
      }
      return next(error);
    }
  });

  router.post('/auth/login', async (req, res, next) => {
    try {
      // Never race the first-run seeding of the user table.
      if (auth.ready) await auth.ready;

      const { email, password } = req.body ?? {};
      if (typeof email !== 'string' || typeof password !== 'string' || !email.trim() || !password) {
        return res.status(400).json({ error: 'e-mail and password are required' });
      }

      const user = await auth.findUserByEmail(email);
      const ok = Boolean(user) && user.active !== 0 && verifyPassword(password, user.passwordHash);

      // Same response for unknown e-mail and wrong password: no user enumeration.
      if (!ok) return res.status(401).json({ error: 'invalid e-mail or password' });

      const token = randomBytes(32).toString('base64url');
      const expiresAt = new Date(Date.now() + config.auth.sessionTtlMs).toISOString();
      await auth.createSession({ tokenHash: hashToken(token), userId: user.id, expiresAt });

      return res.json({
        token,
        tokenType: 'Bearer',
        expiresAt,
        driver: publicUser(user),
      });
    } catch (error) {
      return next(error);
    }
  });

  router.post('/auth/logout', requireAuth, async (req, res, next) => {
    try {
      if (req.auth) await auth.deleteSession(req.auth.tokenHash);
      res.json({ status: 'logged_out' });
    } catch (error) {
      next(error);
    }
  });

  router.get('/auth/me', requireAuth, (req, res) => {
    res.json({ driver: publicUser(req.auth.user) });
  });

  return router;
}

function publicUser(user) {
  return { id: user.id, name: user.name, email: user.email, role: user.role };
}

export default createAuthRoutes;
