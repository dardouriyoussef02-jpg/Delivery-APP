import { Router } from 'express';

/**
 * Read/write endpoints the mobile app uses for its delivery list and status
 * updates. Backed by the demo store or proxied to the client's existing API.
 */
export function createDeliveryRoutes({ gateway, notifications }) {
  const router = Router();

  router.get('/deliveries', async (req, res, next) => {
    try {
      const rows = await gateway.list({ driverId: req.query.driverId });
      res.json({ mode: gateway.mode, count: rows.length, deliveries: rows });
    } catch (error) {
      next(error);
    }
  });

  router.get('/deliveries/:id', async (req, res, next) => {
    try {
      const delivery = await gateway.get(req.params.id);
      if (!delivery) return res.status(404).json({ error: `delivery ${req.params.id} not found` });
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
