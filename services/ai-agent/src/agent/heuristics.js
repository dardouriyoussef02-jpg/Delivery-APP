/**
 * Deterministic understanding of a delivery note.
 *
 * Used by the offline `mock` model so demos and tests behave identically on
 * every machine, and reused by the real prompt as a "first opinion" the model
 * can confirm or overrule.
 */

const SITUATIONS = [
  {
    type: 'access_instructions',
    label: 'Access instructions given',
    keywords: ['gate code', 'code', 'buzzer', 'intercom', 'neighbour', 'neighbor', 'door code', 'entrance'],
    action: 'follow_access_instructions',
    actionLabel: 'Follow the access instructions in the note',
  },
  {
    type: 'recipient_unavailable',
    label: 'Recipient may not be there',
    keywords: ['not home', 'unavailable', 'away', 'leave at', 'leave it', 'porch', 'safe place', 'meeting', 'nobody'],
    action: 'leave_safe_place_or_call',
    actionLabel: 'Call once, then use the agreed safe place',
  },
  {
    type: 'damaged_parcel',
    label: 'Damaged parcel reported',
    keywords: ['damaged', 'broken', 'crushed', 'seal is open', 'wet', 'refuse', 'reject'],
    action: 'flag_to_dispatch',
    actionLabel: 'Raise it with dispatch before hand-over',
  },
  {
    type: 'reschedule_request',
    label: 'Reschedule requested',
    keywords: ['tomorrow', 'reschedule', 'another day', 'another time', 'move this', 'postpone', 'cancel'],
    action: 'request_reschedule',
    actionLabel: 'Confirm the new window in writing',
  },
  {
    type: 'delivery_update_requested',
    label: 'Customer wants an update',
    keywords: ['update', 'when', 'long', 'eta', 'arrive', 'waiting', 'minutes away', 'let me know'],
    action: 'send_eta_update',
    actionLabel: 'Send the ETA update now',
  },
  {
    type: 'special_handling',
    label: 'Special handling requested',
    keywords: ['hard of hearing', 'twice', 'ring the bell', 'fragile', 'handle with care', 'do not leave'],
    action: 'follow_handling_request',
    actionLabel: 'Handle exactly as the note asks',
  },
];

const FALLBACK = {
  type: 'general_note',
  label: 'General delivery note',
  keywords: [],
  action: 'proceed_as_planned',
  actionLabel: 'Proceed with the current stop',
};

/**
 * @param {string} note
 * @returns {{type: string, label: string, action: string, actionLabel: string, matchedKeyword?: string}}
 */
export function classifyNote(note = '') {
  const text = String(note).toLowerCase();
  let best = null;

  for (const situation of SITUATIONS) {
    const matched = situation.keywords
      .filter((keyword) => text.includes(keyword))
      .reduce((longest, keyword) => (keyword.length > longest.length ? keyword : longest), '');
    if (!matched) continue;
    if (!best || matched.length > best.matched.length) {
      best = { situation, matched };
    }
  }

  if (!best) return { ...FALLBACK };
  return { ...best.situation, matchedKeyword: best.matched };
}

/**
 * Compose a short, review-ready message for the driver. Deliberately terse:
 * the driver reads it once, edits if needed, and sends.
 */
export function composeMessage({ delivery, situation, channel }) {
  const name = delivery?.customer?.firstName ?? 'there';
  const code = delivery?.id ?? 'your order';
  const eta = delivery?.eta ? minutesUntil(delivery.eta) : null;

  switch (situation.type) {
    case 'access_instructions':
      return `Hi ${name}, your driver is on the way to ${delivery.address.line1} and will use the access instructions from your note. Any update, just reply here - ref ${code}.`;
    case 'recipient_unavailable':
      return `Hi ${name}, your driver is arriving at ${delivery.address.line1}${eta ? ` in about ${eta} min` : ''}. If nobody answers, we will use the safe place you confirmed in your note - ref ${code}.`;
    case 'damaged_parcel':
      return `Hi ${name}, we noticed possible damage on order ${code} before hand-over. Our driver is photographing it now and dispatch will contact you with the options - no action needed from you.`;
    case 'reschedule_request':
      return `Hi ${name}, thanks for letting us know about order ${code}. We will re-book it for the next available window and confirm the new day by message shortly.`;
    case 'delivery_update_requested':
      return `Hi ${name}, your driver is ${eta ? `about ${eta} min` : 'almost'} away from ${delivery.address.line1} with order ${code}. We will message again if the ETA changes.`;
    case 'special_handling':
      return `Hi ${name}, got it - your driver will follow your note for order ${code} exactly as written. See you shortly at ${delivery.address.line1}.`;
    default:
      return `Hi ${name}, your driver is on the way to ${delivery.address.line1} with order ${code}${eta ? `, ETA about ${eta} min` : ''}. Reply here if anything changes.`;
  }
}

function minutesUntil(iso) {
  const diff = Math.round((new Date(iso).getTime() - Date.now()) / 60_000);
  if (!Number.isFinite(diff)) return null;
  return Math.max(1, diff);
}

/**
 * Confidence heuristic for the offline model (0..1).
 * Strong keyword hit + supporting context = higher confidence.
 */
export function confidenceFor(situation, { hasHistory = false, noteLength = 0 } = {}) {
  if (situation.type === 'general_note') return 0.45;
  let score = 0.72;
  if (situation.matchedKeyword) score += 0.08;
  if (noteLength > 40) score += 0.06;
  if (hasHistory) score += 0.05;
  return Math.min(0.97, Number(score.toFixed(2)));
}

export default { classifyNote, composeMessage, confidenceFor };
