import { Router } from 'express';

/**
 * Read/write endpoints the mobile app uses for its delivery list and status
 * updates. Backed by the demo store or proxied to the client's existing API.
 *
 * Visibility is derived from the validated session, never from the query
 * string: a driver only ever sees their own route, so a forged `?driverId=`
 * is ignored rather than honoured. Admins and the legacy service secret are
 * the company and may look at any route (or all of them at once).
 */
export function createDeliveryRoutes({ gateway, notifications }) {
  const router = Router();

  /** true when the caller may see or touch this delivery at all. */
  function mayAccess(req, delivery) {
    if (req.legacyService || req.auth?.user?.role === 'admin') return true;
    return Boolean(delivery.driverId) && delivery.driverId === req.auth?.user?.id;
  }

  /** The driver id to list for: any (admin/service) or always the session's. */
  function listScope(req) {
    if (req.legacyService || req.auth?.user?.role === 'admin') {
      return req.query.driverId ?? undefined;
    }
    return req.auth?.user?.id ?? null;
  }

  router.get('/deliveries', async (req, res, next) => {
    try {
      const rows = await gateway.list({ driverId: listScope(req) });
      res.json({ mode: gateway.mode, count: rows.length, deliveries: rows });
    } catch (error) {
      next(error);
    }
  });

  router.get('/deliveries/:id', async (req, res, next) => {
    try {
      const delivery = await gateway.get(req.params.id);
      if (!delivery) return res.status(404).json({ error: `delivery ${req.params.id} not found` });
      // Same 404 for "does not exist" and "not yours": no id probing.
      if (!mayAccess(req, delivery)) {
        return res.status(404).json({ error: `delivery ${req.params.id} not found` });
      }
      res.json(delivery);
    } catch (error) {
      next(error);
    }
  });

  router.patch('/deliveries/:id/status', async (req, res, next) => {
    try {
      const { status, label } = req.body ?? {};
      const allowed = ['pending', 'in_transit', 'failed', 'delivered'];
      if (!allowed.includes(status)) {
        return res.status(400).json({ error: `status must be one of ${allowed.join(', ')}` });
      }

      const existing = await gateway.get(req.params.id);
      if (!existing || !mayAccess(req, existing)) {
        return res.status(404).json({ error: `delivery ${req.params.id} not found` });
      }

      const updated = await gateway.updateStatus(req.params.id, status, {
        label,
        changedBy: req.auth?.user?.id ?? null,
      });
      if (!updated) return res.status(404).json({ error: `delivery ${req.params.id} not found` });

      // Important status change: a failed stop needs a retry decision, so the
      // driver (or dispatch watching the same feed) gets a durable notification
      // instead of a snackbar that disappears.
      if (notifications && status === 'failed' && (updated.driverId || req.auth?.user?.id)) {
        try {
          await notifications.create({
            driverId: updated.driverId ?? req.auth.user.id,
            type: 'status_changed',
            title: 'Stop needs attention',
            body: `${updated.id} was marked failed${label ? ` - ${label}` : ''}. Open the stop to retry it.`,
            deliveryId: updated.id,
            source: 'service',
          });
        } catch (error) {
          console.warn('[notifications] could not record the status change:', error.message);
        }
      }

      res.json(updated);
    } catch (error) {
      next(error);
    }
  });

  router.get('/messages/outbox', async (_req, res, next) => {
    try {
      res.json({ messages: await gateway.outbox() });
    } catch (error) {
      next(error);
    }
  });

  return router;
}

export default createDeliveryRoutes;
