import express from 'express';
import cors from 'cors';
import { pathToFileURL } from 'node:url';
import config from './config.js';
import { createDeliveryGateway } from './data/gateway.js';
import { backfillDemoItems, openDatabase, seedDemoDeliveries, seedDemoNotifications } from './data/database.js';
import {
  createContractStore,
  createNotificationStore,
  createSqliteAuthStore,
  createSqliteStore,
} from './data/sqlite_store.js';
import { seedUsers } from './auth/seed.js';
import { createAuthMiddleware } from './auth/middleware.js';
import { createAuthRoutes } from './routes/auth.routes.js';
import { createAgentRoutes } from './routes/agent.routes.js';
import { createContractRoutes } from './routes/contract.routes.js';
import { createDeliveryRoutes } from './routes/deliveries.routes.js';
import { createNotificationRoutes } from './routes/notifications.routes.js';
import { createStatsRoutes } from './routes/stats.routes.js';

/**
 * First-run auth store over the shared SQLite database. Seeding happens
 * asynchronously; `login` awaits `auth.ready` so no request can race it.
 */
export function createDefaultAuth(database, { log = console } = {}) {
  const auth = createSqliteAuthStore(database);
  auth.ready = seedUsers(auth, { log });
  return auth;
}

/**
 * Builds the HTTP app.
 *
 * `db` can be injected (tests pass `:memory:` or a temp file); by default the
 * SQLite database from `DATABASE_PATH` is opened, seeded with the demo route
 * on first run and shared by the delivery gateway, auth and outbox - so status
 * changes and sent messages survive a restart.
 */
export function createApp({ db, gateway, auth } = {}) {
  const database = db ?? openDatabase({ path: config.db.path });
  seedDemoDeliveries(database);
  backfillDemoItems(database);

  const deliveryGateway = gateway ?? createDeliveryGateway({ store: createSqliteStore(database) });
  const authStore = auth ?? createDefaultAuth(database);
  const contractStore = createContractStore(database);
  const notificationStore = createNotificationStore(database);
  if (!config.existingApi.enabled) seedDemoNotifications(database);

  const app = express();

  app.use(cors());
  app.use(express.json({ limit: '64kb' }));

  const { optionalAuth, requireAuth, requireRole, requireContract } = createAuthMiddleware({
    auth: authStore,
    contracts: contractStore,
  });

  // Resolves `req.auth` for every request; protected routes call requireAuth.
  app.use(optionalAuth);

  app.get('/health', (_req, res) => {
    res.json({
      status: 'ok',
      service: 'delivery-ai-agent',
      version: '1.0.0',
      dataMode: deliveryGateway.mode,
      llmProvider: config.llm.provider,
      database: database.path === ':memory:' ? 'memory' : 'sqlite',
      uptimeSec: Math.round(process.uptime()),
    });
  });

  // Auth endpoints first: /auth/login is the only public write.
  app.use(
    '/api/v1',
    createAuthRoutes({ auth: authStore, contracts: contractStore, requireAuth }),
  );

  // Everything else under /api/v1 requires a valid session (or the legacy
  // service secret).
  app.use('/api/v1', requireAuth);

  // The agreement sits *before* the contract gate: an unsigned driver has to
  // be able to read it and sign it, otherwise the gate would be a dead end.
  app.use('/api/v1', createContractRoutes({ contracts: contractStore, db: database }));

  // Aggregated from the database; admin role (or legacy service secret) only.
  // Deliberately mounted before requireContract: somebody asking for
  // fleet-wide numbers needs to hear that they are not an admin, which is the
  // real reason they are being turned away - not their contract state.
  app.use('/api/v1', createStatsRoutes({ db: database, requireRole }));

  // Dispatched work from here on: no signed agreement, no route.
  app.use('/api/v1', requireContract);
  app.use('/api/v1', createAgentRoutes({ gateway: deliveryGateway, notifications: notificationStore }));
  app.use('/api/v1', createDeliveryRoutes({ gateway: deliveryGateway, notifications: notificationStore }));
  app.use('/api/v1', createNotificationRoutes({ notifications: notificationStore }));

  app.use((_req, res) => {
    res.status(404).json({ error: 'unknown endpoint' });
  });

  // Central error handler: always JSON, never a stack trace to the app.
  app.use((error, _req, res, _next) => {
    const status = error.status ?? 500;
    if (status >= 500) console.error('[agent]', error);
    res.status(status).json({ error: error.message ?? 'internal error' });
  });

  app.locals.db = database;
  return app;
}

export function start() {
  if (config.llm.provider === 'anthropic' && !config.llm.anthropicKey) {
    console.warn(
      '[llm] LLM_PROVIDER=anthropic but ANTHROPIC_API_KEY is empty - the service will keep ' +
        `working on the offline model (LLM_FALLBACK=${config.llm.fallback}). ` +
        'Add the key to services/ai-agent/.env to use the real Claude API.',
    );
  }

  const app = createApp();
  return app.listen(config.port, config.host, () => {
    console.log(`delivery-ai-agent listening on http://localhost:${config.port}`);
    console.log(`  llm provider : ${config.llm.provider}`);
    console.log(`  data mode    : ${config.existingApi.enabled ? 'existing API' : 'demo dataset'}`);
    console.log(`  database     : ${config.db.path}`);
    console.log(
      '  endpoints    : POST /api/v1/auth/login, GET /health, GET /api/v1/notifications, ' +
        'POST /api/v1/agent/suggest, POST /api/v1/agent/messages',
    );
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  start();
}
