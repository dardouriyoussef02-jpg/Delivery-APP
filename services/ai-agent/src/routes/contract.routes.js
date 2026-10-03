import { Router } from 'express';
import { CONTRACT, renderContract } from '../data/contract.js';
import { seedDemoNotifications } from '../data/database.js';

const MAX_SIGNATURE = 120;

/**
 * The partnership agreement endpoints.
 *
 *   GET  /api/v1/contract       -> the agreement text + whether it is signed
 *   POST /api/v1/contract/sign  -> record the signature AND dispatch open work
 *
 * These mount *after* `requireAuth` but *before* `requireContract`, because an
 * unsigned driver has to be able to reach them - that is the whole point of
 * the gate.
 *
 * Signing is idempotent: one driver, one agreement, and a repeated POST answers
 * with the original signature instead of overwriting it.
 */
export function createContractRoutes({ contracts, db }) {
  const router = Router();

  router.get('/contract', async (req, res, next) => {
    try {
      const contract = await contracts.find(req.auth.user.id);
      res.json({
        version: CONTRACT.version,
        title: CONTRACT.title,
        company: CONTRACT.company,
        sections: CONTRACT.sections,
        signed: Boolean(contract),
        contract,
      });
    } catch (error) {
      next(error);
    }
  });

  router.post('/contract/sign', async (req, res, next) => {
    try {
      const driverId = req.auth.user.id;
      const { signatureName, acknowledged } = req.body ?? {};

      const name = typeof signatureName === 'string' ? signatureName.trim() : '';
      if (name.length < 2 || name.length > MAX_SIGNATURE) {
        return res
          .status(422)
          .json({ error: `type your full name to sign (2-${MAX_SIGNATURE} characters)` });
      }
      if (acknowledged !== true) {
        return res
          .status(422)
          .json({ error: 'confirm that you have read and accept the agreement' });
      }

      const alreadySigned = Boolean(await contracts.find(driverId));
      const { contract, assigned, deliveryIds } = await contracts.sign({
        driverId,
        version: CONTRACT.version,
        signatureName: name,
        bodySnapshot: renderContract(),
      });

      // Work only becomes visible once it belongs to someone, so the demo
      // dispatch feed is materialised here rather than at boot - otherwise a
      // fresh database would announce stops that are not assigned to anyone.
      if (assigned > 0) seedDemoNotifications(db);

      return res.status(alreadySigned ? 200 : 201).json({
        contract,
        dispatch: { assigned, deliveryIds },
        alreadySigned,
      });
    } catch (error) {
      return next(error);
    }
  });

  return router;
}

export default createContractRoutes;
