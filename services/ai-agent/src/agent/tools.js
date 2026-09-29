import config from '../config.js';
import { searchGuidelines } from '../data/guidelines.js';
import { bannedWordHits, hasLongDigitRun } from './validate.js';
import { CHANNELS } from './prompts.js';

/**
 * Tool contracts handed to the model (Anthropic tool-use format).
 * Each tool is a thin, side-effect-free read except `draft_message`, which only
 * validates. Nothing here ever sends a message: sending stays a driver action.
 */
export const toolSchemas = [
  {
    name: 'get_delivery',
    description:
      'Full context for one delivery: customer preferences, address, access hints, status and COD amount. Call this first.',
    input_schema: {
      type: 'object',
      properties: {
        deliveryId: { type: 'string', description: 'Delivery reference, e.g. DLV-1042' },
      },
      required: ['deliveryId'],
    },
  },
  {
    name: 'list_delivery_events',
    description: 'Chronological event history plus previous delivery attempts for this address.',
    input_schema: {
      type: 'object',
      properties: {
        deliveryId: { type: 'string' },
      },
      required: ['deliveryId'],
    },
  },
  {
    name: 'search_guidelines',
    description:
      'Search the company SOP knowledge base (access rules, damaged goods, reschedules, ETA updates, proof of delivery). Always ground your action choice in a guideline when one matches.',
    input_schema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Short keywords taken from the customer note' },
      },
      required: ['query'],
    },
  },
  {
    name: 'draft_message',
    description:
      'Validate the message you want to propose to the driver. Returns character/guardrail checks. It does NOT send anything - the driver reviews and sends it in the app.',
    input_schema: {
      type: 'object',
      properties: {
        channel: { type: 'string', enum: CHANNELS },
        recipient: { type: 'string', description: 'Customer first name' },
        body: { type: 'string', description: 'Full message text as the driver would send it' },
      },
      required: ['channel', 'recipient', 'body'],
    },
  },
];

/**
 * @param {{deliveryStore: {get: Function}, maxMessageChars: number, minMessageChars: number, bannedWords: string[]}} deps
 */
export function createToolExecutor({ deliveryStore, guidelinesSearch = searchGuidelines }) {
  const guardrails = config.guardrails;

  function checkMessage({ channel, recipient, body }) {
    const errors = [];
    const text = String(body ?? '').trim();
    const length = [...text].length;

    if (!CHANNELS.includes(channel)) errors.push(`channel must be one of ${CHANNELS.join(', ')}`);
    if (!recipient) errors.push('recipient is required');
    if (length < guardrails.minMessageChars) {
      errors.push(`message is too short (${length} < ${guardrails.minMessageChars} characters)`);
    }
    if (length > guardrails.maxMessageChars) {
      errors.push(`message is too long (${length} > ${guardrails.maxMessageChars} characters) - shorten it`);
    }
    for (const word of bannedWordHits(text)) {
      errors.push(
        guardrails.bannedWords.includes(word)
          ? `remove the word "${word}" - service messages must not market`
          : `remove the word "${word}" - messages must stay respectful`,
      );
    }
    if (hasLongDigitRun(text)) {
      errors.push('do not paste long number sequences (phone/bank data) into a customer message');
    }

    return {
      ok: errors.length === 0,
      errors,
      checks: { length, limit: guardrails.maxMessageChars, channel },
    };
  }

  async function execute(name, input = {}) {
    switch (name) {
      case 'get_delivery': {
        const delivery = await deliveryStore.get(input.deliveryId);
        if (!delivery) return { ok: false, error: `delivery ${input.deliveryId} not found` };
        return {
          ok: true,
          delivery: {
            id: delivery.id,
            status: delivery.status,
            eta: delivery.eta,
            window: [delivery.windowStart, delivery.windowEnd],
            parcels: delivery.parcels,
            codAmount: delivery.codAmount,
            currency: delivery.currency,
            item: delivery.item ?? null,
            distanceKm: delivery.distanceKm,
            address: delivery.address,
            customer: delivery.customer,
            notes: delivery.notes,
          },
        };
      }

      case 'list_delivery_events': {
        const delivery = await deliveryStore.get(input.deliveryId);
        if (!delivery) return { ok: false, error: `delivery ${input.deliveryId} not found` };
        return { ok: true, events: delivery.events, previousAttempts: delivery.history ?? [] };
      }

      case 'search_guidelines': {
        const results = guidelinesSearch(String(input.query ?? ''));
        return {
          ok: true,
          query: input.query,
          count: results.length,
          results: results.map((r) => ({ id: r.id, title: r.title, body: r.body })),
        };
      }

      case 'draft_message': {
        const result = checkMessage(input);
        if (!result.ok) return { ok: false, errors: result.errors, checks: result.checks };
        return {
          ok: true,
          draft: {
            channel: input.channel,
            recipient: input.recipient,
            body: String(input.body).trim(),
            charCount: result.checks.length,
          },
          note: 'Draft validated. The driver still has to review and send it in the app.',
        };
      }

      default:
        return { ok: false, error: `unknown tool: ${name}` };
    }
  }

  return { execute, checkMessage, schemas: toolSchemas };
}

export default createToolExecutor;
