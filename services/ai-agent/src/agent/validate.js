import config from '../config.js';
import { ACTION_TYPES, CHANNELS, SITUATION_TYPES } from './prompts.js';

const { minMessageChars, maxMessageChars, bannedWords } = config.guardrails;

/**
 * Words that must never reach a customer: marketing terms (a driver message is
 * service comms) plus abusive language. Used identically by the drafting tool,
 * the suggestion validator and the final send endpoint, so the rules cannot
 * drift apart.
 *
 * @param {string} body
 * @returns {string[]} the matched terms
 */
export function bannedWordHits(body) {
  const lower = String(body ?? '').toLowerCase();
  const words = [...bannedWords, ...(config.guardrails.abusiveWords ?? [])];
  return words.filter((word) => lower.includes(word));
}

/** Long digit runs (phone/bank data) unless the message reads like a reference. */
export function hasLongDigitRun(body) {
  const text = String(body ?? '');
  return /\b\d{7,}\b/.test(text.replace(/\D/g, '')) && !/ref\s/i.test(text);
}

/**
 * Hard gate on whatever the model produced. Anything that fails here is sent
 * back for one repair round; if it still fails we refuse to return a
 * suggestion rather than show the driver something sloppy.
 *
 * @returns {{valid: boolean, errors: string[]}}
 */
export function validateSuggestion(raw) {
  const errors = [];
  const value = raw && typeof raw === 'object' ? raw : {};

  if (!value.situation || typeof value.situation !== 'object') {
    errors.push('missing "situation"');
  } else {
    if (!SITUATION_TYPES.includes(value.situation.type)) {
      errors.push(`situation.type must be one of ${SITUATION_TYPES.join(', ')}`);
    }
    if (!isShortString(value.situation.label)) errors.push('situation.label missing or too long');
  }

  const confidence = Number(value.confidence);
  if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) {
    errors.push('confidence must be a number between 0 and 1');
  }

  if (!isShortString(value.reasoning, 200)) errors.push('reasoning missing or too long');

  if (!value.recommendedAction || typeof value.recommendedAction !== 'object') {
    errors.push('missing "recommendedAction"');
  } else {
    if (!ACTION_TYPES.includes(value.recommendedAction.type)) {
      errors.push(`recommendedAction.type must be one of ${ACTION_TYPES.join(', ')}`);
    }
    if (!isShortString(value.recommendedAction.label, 80)) {
      errors.push('recommendedAction.label missing or too long');
    }
    if (!isShortString(value.recommendedAction.reason, 220)) {
      errors.push('recommendedAction.reason missing or too long');
    }
  }

  const message = value.message;
  if (!message || typeof message !== 'object') {
    errors.push('missing "message"');
  } else {
    if (!CHANNELS.includes(message.channel)) errors.push(`message.channel must be one of ${CHANNELS.join(', ')}`);
    if (!message.recipient || typeof message.recipient !== 'string') errors.push('message.recipient missing');

    const body = String(message.body ?? '').trim();
    const length = [...body].length;
    if (length < minMessageChars) errors.push(`message.body too short (${length}/${minMessageChars})`);
    if (length > maxMessageChars) errors.push(`message.body too long (${length}/${maxMessageChars})`);
    for (const hit of bannedWordHits(body)) {
      errors.push(`message.body contains banned word "${hit}"`);
    }
    if (hasLongDigitRun(body)) errors.push('message.body contains a long number sequence (personal data)');
  }

  return { valid: errors.length === 0, errors };
}

function isShortString(value, max = 80) {
  return typeof value === 'string' && value.trim().length > 0 && value.trim().length <= max;
}

/**
 * Final gate for `POST /api/v1/agent/messages`.
 *
 * The same safety rules the agent uses while drafting are re-applied at the
 * send endpoint, because the server must never trust the client: a modified
 * app (or a curl one-liner) has to be rejected exactly like a bad model draft.
 *
 * @returns {{valid: boolean, errors: string[]}}
 */
export function validateOutgoingMessage(raw) {
  const errors = [];
  const value = raw && typeof raw === 'object' ? raw : {};

  for (const field of ['deliveryId', 'channel', 'recipient', 'body']) {
    const present = typeof value[field] === 'string' && value[field].trim().length > 0;
    if (!present) errors.push(`${field} is required`);
  }

  if (value.channel && !CHANNELS.includes(value.channel)) {
    errors.push(`channel must be one of ${CHANNELS.join(', ')}`);
  }

  if (value.action && !ACTION_TYPES.includes(value.action)) {
    errors.push(`action must be one of ${ACTION_TYPES.join(', ')}`);
  }

  if (typeof value.recipient === 'string' && value.recipient.length > 120) {
    errors.push('recipient is too long (max 120 characters)');
  }

  const body = typeof value.body === 'string' ? value.body.trim() : '';
  if (body) {
    const length = [...body].length;
    if (length < minMessageChars) errors.push(`message.body too short (${length}/${minMessageChars})`);
    if (length > maxMessageChars) errors.push(`message.body too long (${length}/${maxMessageChars})`);

    for (const hit of bannedWordHits(body)) {
      errors.push(`message.body contains banned word "${hit}"`);
    }
    if (hasLongDigitRun(body)) errors.push('message.body contains a long number sequence (personal data)');
  }

  return { valid: errors.length === 0, errors };
}

/**
 * The model is told to answer with bare JSON, but models occasionally wrap it
 * in prose or code fences. Pull the first balanced object out.
 * @param {string} text
 */
export function parseJsonLoose(text) {
  const fenced = /```(?:json)?\s*([\s\S]*?)```/i.exec(text);
  const candidate = fenced ? fenced[1] : text;

  const start = candidate.indexOf('{');
  if (start === -1) throw new Error('no JSON object found in model output');

  let depth = 0;
  let inString = false;
  let escaped = false;

  for (let i = start; i < candidate.length; i += 1) {
    const char = candidate[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (char === '\\') escaped = true;
      else if (char === '"') inString = false;
      continue;
    }
    if (char === '"') inString = true;
    else if (char === '{') depth += 1;
    else if (char === '}') {
      depth -= 1;
      if (depth === 0) {
        return JSON.parse(candidate.slice(start, i + 1));
      }
    }
  }

  throw new Error('unbalanced JSON object in model output');
}

export default { validateSuggestion, validateOutgoingMessage, parseJsonLoose };
