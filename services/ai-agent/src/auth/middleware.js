import { createHash } from 'node:crypto';
import config from '../config.js';

/** SHA-256 of the bearer token - only the hash is ever persisted. */
export function hashToken(token) {
  return createHash('sha256').update(String(token)).digest('hex');
}

function bearerToken(req) {
  const header = req.header('authorization') ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  return match ? match[1].trim() : null;
}

/**
 * Authentication middleware factory.
 *
 *  - `optionalAuth`:   resolves `req.auth` when a valid session token is sent.
 *  - `requireAuth`:    401 unless a valid session (or the legacy service
 *                      `X-Driver-Token` secret) is present.
 *  - `requireRole`:    403 when the signed-in user lacks the role.
 *  - `requireContract`:403 when a driver has not signed the partnership
 *                      agreement yet. Admins and the service secret are the
 *                      company itself, so they are exempt.
 *
 * The server never trusts the client's idea of who it is: the driver id always
 * comes from the validated session.
 */
export function createAuthMiddleware({ auth, contracts }) {
  async function resolve(req) {
    const token = bearerToken(req);
    if (!token) return null;

    const tokenHash = hashToken(token);
    const session = await auth.findSession(tokenHash);
    if (!session) return null;

    const user = await auth.findUserById(session.userId);
    if (!user || user.active === 0) return null;

    return { token, tokenHash, session, user };
  }

  async function optionalAuth(req, _res, next) {
    try {
      req.auth = await resolve(req);
      // Legacy service-to-service secret (existing integration contract).
      req.legacyService =
        Boolean(config.auth.driverToken) && req.header('x-driver-token') === config.auth.driverToken;
      next();
    } catch (error) {
      next(error);
    }
  }

  async function requireAuth(req, res, next) {
    try {
      if (!req.auth) req.auth = await resolve(req);
      if (req.auth || req.legacyService) return next();
      const expired = bearerToken(req) ? 'session expired or invalid' : 'authentication required';
      return res.status(401).json({ error: expired });
    } catch (error) {
      return next(error);
    }
  }

  function requireRole(role) {
    return (req, res, next) => {
      if (!req.auth && !req.legacyService) {
        return res.status(401).json({ error: 'authentication required' });
      }
      if (req.legacyService) return next(); // service secret acts with full rights
      if (req.auth.user.role !== role) {
        return res.status(403).json({ error: `${role} role required` });
      }
      return next();
    };
  }

  /**
   * The contract gate: no signed agreement, no dispatched work.
   *
   * Mounted after `requireAuth` and after the /contract routes, so an unsigned
   * driver can still fetch and sign the agreement - they are only locked out of
   * the routes that hand out or mutate deliveries. A missing store is a wiring
   * bug, so it fails loudly instead of quietly letting everyone through.
   */
  async function requireContract(req, res, next) {
    try {
      if (req.legacyService) return next(); // the integration account is the company
      if (!req.auth) return res.status(401).json({ error: 'authentication required' });
      if (req.auth.user.role === 'admin') return next();
      if (!contracts) return next(new Error('contract store is not configured'));
      if (await contracts.find(req.auth.user.id)) return next();
      return res.status(403).json({ error: 'driver contract not signed' });
    } catch (error) {
      return next(error);
    }
  }

  return { optionalAuth, requireAuth, requireRole, requireContract };
}

export default createAuthMiddleware;
