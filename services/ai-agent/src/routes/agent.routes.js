import { Router } from 'express';
import config from '../config.js';
import createAgent from '../agent/orchestrator.js';
import { validateSuggestion, validateOutgoingMessage } from '../agent/validate.js';

/**
 * Routes for the AI feature.
 *
 * Design rule: the agent only ever *proposes*. The driver presses Send, and
 * only then does a message leave the service.
 */
export function createAgentRoutes({ gateway, notifications }) {
  const router = Router();
  const agent = createAgent({ deliveryStore: gateway });

  /** Health of the whole AI pipeline, including which model backs it. */
  router.get('/agent/health', (_req, res) => {
    res.json({
      status: 'ok',
      provider: config.llm.provider,
      fallback: config.llm.fallback,
      anthropicConfigured: Boolean(config.llm.anthropicKey),
      dataMode: gateway.mode,
      features: ['suggest', 'message-drafting'],
      sendsMessagesAutomatically: false,
    });
  });

  /**
   * POST /api/v1/agent/suggest
   * body: { deliveryId, note?, driverId?, channel? }
   */
  router.post('/agent/suggest', async (req, res, next) => {
    try {
      const { deliveryId, note, driverId, channel } = req.body ?? {};
      if (!deliveryId) {
        return res.status(400).json({ error: 'deliveryId is required' });
      }

      const suggestion = await agent.suggest({ deliveryId, note, driverId, channel });
      res.json(suggestion);
    } catch (error) {
      next(error);
    }
  });

  /**
   * POST /api/v1/agent/suggest/validate
   * Dry-run helper used by tests and by the app after the driver edits text.
   */
  router.post('/agent/suggest/validate', (req, res) => {
    const result = validateSuggestion(req.body ?? {});
    res.status(result.valid ? 200 : 422).json(result);
  });

  /**
   * POST /api/v1/agent/messages
   * Called only after the driver reviewed and approved the text.
   * body: { deliveryId, channel, recipient, body, action? }
   */
  router.post('/agent/messages', async (req, res, next) => {
    try {
      const { deliveryId, channel, recipient, body, action } = req.body ?? {};
      const missing = ['deliveryId', 'channel', 'recipient', 'body'].filter(
        (field) => !req.body?.[field],
      );
      if (missing.length) {
        return res.status(400).json({ error: `missing fields: ${missing.join(', ')}` });
      }

      const delivery = await gateway.get(deliveryId);
      if (!delivery) return res.status(404).json({ error: `delivery ${deliveryId} not found` });

      // Server-side re-validation: the exact guardrails the agent drafts with
      // are applied again here, so a modified client can never bypass them.
      const guard = validateOutgoingMessage({ deliveryId, channel, recipient, body, action });
      if (!guard.valid) {
        return res.status(422).json({ error: 'message rejected by the guardrails', errors: guard.errors });
      }

      const record = await gateway.sendMessage({
        deliveryId,
        channel,
        recipient,
        body,
        action: action ?? null,
        // Identity comes from the validated session, never from a client header.
        sentBy: req.auth?.user?.id ?? req.header('x-driver-id') ?? 'unknown',
      });

      // Demo mode stands in for the customer's messaging system: a reply can
      // arrive for a delivery the driver messaged (at most once). Live mode
      // would get this event pushed from the existing API instead.
      const driverId = req.auth?.user?.id ?? null;
      if (notifications && driverId && gateway.mode === 'demo') {
        try {
          const feed = await notifications.list({ driverId });
          const alreadyReplied = feed.some(
            (item) => item.type === 'customer_reply' && item.deliveryId === deliveryId,
          );
          if (!alreadyReplied) {
            const name = recipient || delivery.customer?.firstName || 'the customer';
            await notifications.create({
              driverId,
              type: 'customer_reply',
              title: `${name} replied`,
              body: `${name}: "Thanks for the update - see you at the door!"`,
              deliveryId,
              source: 'demo',
            });
          }
        } catch (error) {
          // A notification problem must never turn a successful send into a 500.
          console.warn('[notifications] could not record the demo reply:', error.message);
        }
      }

      res.status(201).json({ status: 'sent', ...record });
    } catch (error) {
      next(error);
    }
  });

  return router;
}

export default createAgentRoutes;
