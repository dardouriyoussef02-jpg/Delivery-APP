import config from '../config.js';

export const SITUATION_TYPES = [
  'access_instructions',
  'recipient_unavailable',
  'damaged_parcel',
  'reschedule_request',
  'delivery_update_requested',
  'special_handling',
  'general_note',
];

export const ACTION_TYPES = [
  'follow_access_instructions',
  'leave_safe_place_or_call',
  'flag_to_dispatch',
  'request_reschedule',
  'send_eta_update',
  'follow_handling_request',
  'proceed_as_planned',
];

export const CHANNELS = ['sms', 'whatsapp', 'push'];

export const OUTPUT_SCHEMA = `{
  "situation": {
    "type": one of ${JSON.stringify(SITUATION_TYPES)},
    "label": "max 60 chars, human readable"
  },
  "confidence": 0.0-1.0,
  "reasoning": "one sentence, why this situation was chosen",
  "recommendedAction": {
    "type": one of ${JSON.stringify(ACTION_TYPES)},
    "label": "max 70 chars, the concrete next step for the driver",
    "reason": "one sentence explaining the benefit for this delivery"
  },
  "message": {
    "channel": one of ${JSON.stringify(CHANNELS)},
    "recipient": "customer first name",
    "body": "the ready-to-send customer message, ${config.guardrails.minMessageChars}-${config.guardrails.maxMessageChars} characters"
  }
}`;

export function buildSystemPrompt() {
  return `You are the delivery assistant inside a driver app. You work for a courier company.

You receive ONE delivery note (plus delivery and customer context retrieved with tools). Your job:
1. Understand what the note means for this stop.
2. Choose the single best next action for the driver.
3. Draft a short message the driver can review and send to the customer.

Rules you must follow:
- Be practical and specific to this delivery. Never give generic advice.
- The message is service communication: short, friendly, plain language, at most two sentences plus an order reference. No marketing, no discounts, no promises about exact minutes.
- Use the customer's first name. Never include another customer's data, or the full address of anyone else.
- Keep the language of the message aligned with the customer's preferred language code when provided.
- Channel must be the customer's preferred channel when one exists.
- Never claim the parcel was delivered, never claim you contacted dispatch - you only suggest.
- If the note is ambiguous, pick the safest action for the customer and lower your confidence.
- You may only recommend actions from the allowed list.

Workflow: call the tools you need (delivery context, event history, guidelines), then answer.
When you have everything, reply with ONLY a JSON object matching this schema and nothing else:
${OUTPUT_SCHEMA}`;
}

export function buildUserPrompt({ delivery, note, heuristicHint }) {
  const lines = [
    'Delivery note to handle:',
    `"""${note}"""`,
    '',
    `Delivery reference: ${delivery.id}`,
    `Customer: ${delivery.customer.firstName} ${delivery.customer.lastName} (prefers ${delivery.customer.preferredChannel}, language ${delivery.customer.language})`,
    `Address: ${delivery.address.line1}${delivery.address.line2 ? ', ' + delivery.address.line2 : ''}, ${delivery.address.postalCode} ${delivery.address.city}`,
    `Status: ${delivery.status} | parcels: ${delivery.parcels} | COD: ${delivery.codAmount} ${delivery.currency}`,
  ];

  if (delivery.address.accessHint) {
    lines.push(`Address access hint: ${delivery.address.accessHint}`);
  }

  if (heuristicHint) {
    lines.push('', `Rule-based first read (confirm or overrule it): ${heuristicHint}`);
  }

  lines.push('', 'Retrieve anything else you need with the tools, then answer with the JSON object.');
  return lines.join('\n');
}

export default { buildSystemPrompt, buildUserPrompt, OUTPUT_SCHEMA };
