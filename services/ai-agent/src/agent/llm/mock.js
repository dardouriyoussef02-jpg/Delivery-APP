import { classifyNote, composeMessage, confidenceFor } from '../heuristics.js';

/**
 * Offline stand-in for Claude.
 *
 * It speaks the exact same contract as the real model - it can emit tool calls,
 * read tool results and finally answer with a JSON object - so the whole agent
 * loop, trace and validation path run identically with or without an API key.
 * Decisions come from the deterministic note classifier.
 */

const MAX_DRAFT_ATTEMPTS = 2;

/**
 * @param {{getDeliveryContext: () => object, getNote: () => string}} hooks
 */
export function createMockModel(hooks) {
  return {
    name: 'mock',

    async complete({ messages }) {
      const results = collectToolResults(messages);
      const delivery = hooks.getDeliveryContext();
      const note = hooks.getNote();

      // Turn 1: gather every piece of context before deciding anything.
      if (!results.get('get_delivery')) {
        return {
          stopReason: 'tool_use',
          text: '',
          toolCalls: [
            { id: 'call-1', name: 'get_delivery', input: { deliveryId: delivery.id } },
            { id: 'call-2', name: 'list_delivery_events', input: { deliveryId: delivery.id } },
            { id: 'call-3', name: 'search_guidelines', input: { query: keywordsFrom(note) } },
          ],
        };
      }

      const situation = classifyNote(note);
      const draftResult = results.get('draft_message');

      // Turn 2 (plus one repair turn): propose the message and run guardrails.
      if (!draftResult || (!draftResult.ok && draftResult.attempt < MAX_DRAFT_ATTEMPTS)) {
        const attempt = (draftResult?.attempt ?? 0) + 1;
        const body = composeMessage({
          delivery,
          situation,
          channel: delivery.customer.preferredChannel,
        });
        return {
          stopReason: 'tool_use',
          text: '',
          toolCalls: [
            {
              id: `call-draft-${attempt}`,
              name: 'draft_message',
              input: {
                channel: delivery.customer.preferredChannel,
                recipient: delivery.customer.firstName,
                body: attempt === 1 ? body : shorten(body),
              },
            },
          ],
        };
      }

      // Draft could not be fixed inside the retry budget: never return a bad message.
      if (!draftResult.ok) {
        return {
          stopReason: 'end_turn',
          text: JSON.stringify({
            situation: { type: situation.type, label: situation.label },
            confidence: 0.2,
            reasoning: 'The drafted message failed the guardrail checks twice, so nothing is proposed.',
            recommendedAction: {
              type: 'proceed_as_planned',
              label: 'Handle this stop manually',
              reason: 'Automatic drafting failed validation, so a human decision is safer.',
            },
            message: {
              channel: delivery.customer.preferredChannel,
              recipient: delivery.customer.firstName,
              body: `Note for dispatch: ${draftResult.errors.join(' ')}`.slice(0, 300),
            },
          }),
        };
      }

      // Turn 3: context gathered + message validated -> final answer.
      const hasHistory = (results.get('list_delivery_events')?.previousAttempts?.length ?? 0) > 0;
      const draft = draftResult.draft;

      return {
        stopReason: 'end_turn',
        text: JSON.stringify({
          situation: { type: situation.type, label: situation.label },
          confidence: confidenceFor(situation, { hasHistory, noteLength: note.length }),
          reasoning: `The note "${truncate(note, 70)}" points to ${situation.label.toLowerCase()}.`,
          recommendedAction: {
            type: situation.action,
            label: situation.actionLabel,
            reason: actionReason(situation, delivery),
          },
          message: {
            channel: draft.channel,
            recipient: draft.recipient,
            body: draft.body,
          },
        }),
      };
    },
  };
}

/**
 * Replay the conversation the same way the API would present it: resolve each
 * tool_result to its tool name through the assistant's tool_use blocks.
 */
function collectToolResults(messages) {
  const idToName = new Map();
  const attempts = new Map();

  for (const message of messages) {
    const blocks = Array.isArray(message.content) ? message.content : [];

    if (message.role === 'assistant') {
      for (const block of blocks) {
        if (block.type === 'tool_use') idToName.set(block.id, block.name);
      }
      continue;
    }

    for (const block of blocks) {
      if (block.type !== 'tool_result') continue;
      const name = idToName.get(block.tool_use_id);
      if (!name) continue;

      const count = (attempts.get(name)?.attempt ?? 0) + 1;
      const payload = parseContent(block.content);
      attempts.set(name, { attempt: count, ...payload });
    }
  }

  return attempts;
}

function parseContent(content) {
  if (typeof content === 'string') {
    try {
      return JSON.parse(content);
    } catch {
      return { raw: content };
    }
  }
  if (Array.isArray(content)) {
    const text = content
      .filter((block) => block.type === 'text')
      .map((block) => block.text)
      .join('');
    return parseContent(text);
  }
  return content && typeof content === 'object' ? content : {};
}

function keywordsFrom(note) {
  const stop = new Set([
    'the', 'and', 'with', 'for', 'you', 'your', 'please', 'that', 'this',
    'have', 'from', 'not', 'can', 'are', 'was', 'all', 'but', 'will', 'when',
  ]);
  return String(note)
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((word) => word.length > 3 && !stop.has(word))
    .slice(0, 6)
    .join(' ');
}

function actionReason(situation, delivery) {
  switch (situation.type) {
    case 'access_instructions':
      return 'Following the note avoids a failed attempt at a gated building.';
    case 'recipient_unavailable':
      return 'One call plus the agreed safe place keeps attempt one successful.';
    case 'damaged_parcel':
      return 'Raising damage before hand-over protects the customer and the claim.';
    case 'reschedule_request':
      return 'Confirming in writing lets planning re-book without a support ticket.';
    case 'delivery_update_requested':
      return 'A proactive update removes uncertainty while the driver is en route.';
    case 'special_handling':
      return 'Doing exactly what the note asks prevents a complaint on arrival.';
    default:
      return `The stop is on schedule for ${delivery.address.city}, so normal handling applies.`;
  }
}

function shorten(body) {
  return body.length <= 320 ? body : `${body.slice(0, 300).trimEnd()}...`;
}

function truncate(value, max) {
  return value.length <= max ? value : `${value.slice(0, max - 1)}...`;
}

export default createMockModel;
