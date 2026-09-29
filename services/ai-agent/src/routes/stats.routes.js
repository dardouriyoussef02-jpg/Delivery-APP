import { Router } from 'express';

/**
 * Admin statistics - every number is aggregated from the SQLite database at
 * request time (demo dataset or the rows this service recorded). Nothing here
 * is canned: delete the database and the dashboard honestly shows zeroes.
 *
 *   GET /api/v1/stats   (admin role, or the legacy service secret)
 *
 * `requireRole` is injected so the route file never touches auth internals.
 */
export function createStatsRoutes({ db, requireRole }) {
  const router = Router();

  const count = (sql) => Number(db.prepare(sql).get()?.n ?? 0);

  router.get('/stats', requireRole('admin'), (_req, res, next) => {
    try {
      const generatedAt = new Date().toISOString();

      // --- totals ---------------------------------------------------------
      const totals = {
        deliveries: count('SELECT COUNT(*) AS n FROM deliveries'),
        customers: count('SELECT COUNT(*) AS n FROM customers'),
        drivers: count('SELECT COUNT(*) AS n FROM drivers WHERE active = 1'),
        messagesSent: count('SELECT COUNT(*) AS n FROM messages'),
        notifications: count('SELECT COUNT(*) AS n FROM notifications'),
        unreadNotifications: count(
          'SELECT COUNT(*) AS n FROM notifications WHERE is_read = 0',
        ),
      };

      // --- deliveries by status ------------------------------------------
      const byStatus = { pending: 0, in_transit: 0, failed: 0, delivered: 0 };
      for (const row of db
        .prepare('SELECT status, COUNT(*) AS n FROM deliveries GROUP BY status')
        .all()) {
        byStatus[row.status] = Number(row.n);
      }

      const finished = byStatus.delivered + byStatus.failed;
      const completionRate =
        totals.deliveries === 0
          ? 0
          : Number((byStatus.delivered / totals.deliveries).toFixed(4));

      // --- delivery time: creation -> transition to "delivered" -----------
      const deliveryRows = db
        .prepare(
          `SELECT id, driver_id, created_at, delivered_at FROM (
             SELECT d.id, d.driver_id, d.created_at,
                    (SELECT MIN(h.changed_at) FROM delivery_status_history h
                      WHERE h.delivery_id = d.id AND h.to_status = 'delivered') AS delivered_at
             FROM deliveries d
           ) WHERE delivered_at IS NOT NULL`,
        )
        .all();

      const minutes = deliveryRows
        .map((row) => {
          const delta = (Date.parse(row.delivered_at) - Date.parse(row.created_at)) / 60000;
          return Number.isFinite(delta) && delta >= 0 ? delta : null;
        })
        .filter((value) => value !== null);

      const round1 = (value) => Number(value.toFixed(1));
      const deliveryTime = {
        sampleSize: minutes.length,
        averageMinutes: minutes.length
          ? round1(minutes.reduce((sum, value) => sum + value, 0) / minutes.length)
          : null,
        fastestMinutes: minutes.length ? round1(Math.min(...minutes)) : null,
        slowestMinutes: minutes.length ? round1(Math.max(...minutes)) : null,
      };

      // --- per-driver breakdown ------------------------------------------
      const driverRows = db
        .prepare(
          `SELECT d.id, d.name,
                  (SELECT COUNT(*) FROM deliveries x WHERE x.driver_id = d.id) AS assigned,
                  (SELECT COUNT(*) FROM deliveries x
                    WHERE x.driver_id = d.id AND x.status = 'delivered') AS delivered,
                  (SELECT COUNT(*) FROM deliveries x
                    WHERE x.driver_id = d.id AND x.status = 'failed') AS failed
             FROM drivers d WHERE d.active = 1 ORDER BY d.id`,
        )
        .all();

      const perDriver = driverRows.map((row) => {
        const own = minutes.length
          ? deliveryRows
              .filter((entry) => entry.driver_id === row.id)
              .map((entry) => (Date.parse(entry.delivered_at) - Date.parse(entry.created_at)) / 60000)
              .filter((value) => Number.isFinite(value) && value >= 0)
          : [];
        return {
          driverId: row.id,
          name: row.name,
          assigned: Number(row.assigned),
          delivered: Number(row.delivered),
          failed: Number(row.failed),
          averageMinutes: own.length ? round1(own.reduce((a, b) => a + b, 0) / own.length) : null,
        };
      });

      // --- latest status transitions --------------------------------------
      const recentActivity = db
        .prepare(
          `SELECT delivery_id, from_status, to_status, label, changed_by, changed_at
             FROM delivery_status_history
            ORDER BY changed_at DESC, id DESC LIMIT 5`,
        )
        .all()
        .map((row) => ({
          deliveryId: row.delivery_id,
          fromStatus: row.from_status,
          toStatus: row.to_status,
          label: row.label,
          changedBy: row.changed_by,
          changedAt: row.changed_at,
        }));

      res.json({
        generatedAt,
        source: 'database',
        totals,
        byStatus,
        completion: { finished, completionRate },
        deliveryTime,
        perDriver,
        recentActivity,
      });
    } catch (error) {
      next(error);
    }
  });

  return router;
}

export default createStatsRoutes;
