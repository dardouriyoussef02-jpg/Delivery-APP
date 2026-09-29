import { Router } from 'express';

/**
 * The driver's notification feed (mounted behind `requireAuth`).
 *
 * Every response is scoped to the signed-in user (`req.auth.user.id`), so one
 * driver can never read or flip another driver's notifications - including the
 * legacy service credential, which carries no user id and therefore sees an
 * empty feed.
 *
 *   GET  /api/v1/notifications          -> { notifications, unreadCount }
 *   GET  /api/v1/notifications?unread=1 -> only the unread rows
 *   POST /api/v1/notifications/:id/read -> mark one as read (404 if unknown)
 */
export function createNotificationRoutes({ notifications }) {
  const router = Router();

  router.get('/notifications', async (req, res, next) => {
    try {
      const driverId = req.auth?.user?.id ?? '';
      const unreadOnly = req.query.unread === '1' || req.query.unread === 'true';

      const [items, unreadCount] = await Promise.all([
        notifications.list({ driverId, unreadOnly }),
        notifications.unreadCount(driverId),
      ]);

      res.json({ notifications: items, unreadCount });
    } catch (error) {
      next(error);
    }
  });

  router.post('/notifications/:id/read', async (req, res, next) => {
    try {
      const driverId = req.auth?.user?.id ?? '';
      const updated = await notifications.markRead(driverId, req.params.id);

      if (!updated) {
        return res.status(404).json({ error: `notification ${req.params.id} not found` });
      }

      res.json({ notification: updated, unreadCount: await notifications.unreadCount(driverId) });
    } catch (error) {
      next(error);
    }
  });

  return router;
}

export default createNotificationRoutes;
