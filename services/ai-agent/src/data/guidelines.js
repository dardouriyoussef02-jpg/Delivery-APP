/**
 * Internal knowledge the agent can search before it decides what to suggest.
 *
 * In production this is fetched from the client's SOP/help-centre endpoint
 * (`search_guidelines` is the seam where that plugs in); here it ships as data
 * so the agent has grounded, company-specific guidance instead of guessing.
 */

export const guidelines = [
  {
    id: 'SOP-ACCESS',
    topics: ['access', 'gate', 'code', 'buzzer', 'intercom', 'door', 'neighbour', 'neighbor'],
    title: 'Access instructions & gated buildings',
    body: 'Use the access code from the delivery note, never ask the customer to share a code that is not in the note. If the buzzer or intercom fails, call the customer once; if there is no answer, follow the safe-place rules. Never leave parcels in a shared porch or stairwell.',
  },
  {
    id: 'SOP-UNAVAILABLE',
    topics: ['not home', 'unavailable', 'away', 'leave', 'porch', 'safe', 'neighbour', 'neighbor', 'meeting'],
    title: 'Recipient unavailable',
    body: 'Call the customer once before attempting a safe place. If the note allows leaving with a neighbour, do that and record the neighbour house number in the event log. Otherwise mark the attempt as failed with reason "recipient unavailable" and let dispatch schedule attempt two.',
  },
  {
    id: 'SOP-DAMAGE',
    topics: ['damaged', 'broken', 'crushed', 'seal', 'wet', 'refuse', 'reject'],
    title: 'Damaged or open parcels',
    body: 'Do not ask the customer to accept a visibly damaged parcel. Take one photo of the packaging, mark the attempt as damaged goods, and notify dispatch immediately. The customer does not need to contact support themselves - the driver raises it.',
  },
  {
    id: 'SOP-RESCHEDULE',
    topics: ['tomorrow', 'reschedule', 'another day', 'another time', 'move', 'cancel', 'postpone', 'morning'],
    title: 'Rescheduling a delivery',
    body: 'Confirm the new day in writing with the customer, then mark the attempt as "requested reschedule" so planning can re-book it. Never promise a specific hour outside the published windows; offer the next available window instead.',
  },
  {
    id: 'SOP-ETA',
    topics: ['eta', 'update', 'when', 'long', 'waiting', 'arrive', 'minutes', 'track'],
    title: 'Proactive ETA updates',
    body: 'Send an ETA update when the customer asked for one or when arrival slips more than 10 minutes past the promised window. Keep it under 2 sentences, include the order reference, and never promise an exact minute you cannot hold.',
  },
  {
    id: 'SOP-COD',
    topics: ['cash', 'cod', 'payment', 'pay', 'amount', 'money'],
    title: 'Cash on delivery',
    body: 'Collect the exact amount listed on the label before handing over the parcel. Never accept a higher amount and never promise change above 20 EUR. The receipt is sent by email automatically after the hand-over.',
  },
  {
    id: 'SOP-CONTACT',
    topics: ['call', 'phone', 'ring', 'bell', 'hard of hearing', 'twice', 'contact'],
    title: 'Contacting the customer',
    body: 'Call through the app so the number stays private. If the customer is hard of hearing or asked for a specific ring pattern, follow the note exactly and wait at least 60 seconds before leaving.',
  },
  {
    id: 'SOP-PRIVACY',
    topics: ['photo', 'privacy', 'data', 'gdpr', 'signature'],
    title: 'Proof of delivery & privacy',
    body: 'Photos must show the parcel at the delivery location only - no open windows, people or screens. Signature capture is required for orders above 100 EUR. Never include another customer\'s details in a message.',
  },
];

/**
 * Simple relevance search: score each entry by topic/keyword overlap with the
 * query, keeping only entries that actually match something.
 * @param {string} query
 * @param {number} limit
 */
export function searchGuidelines(query, limit = 3) {
  const haystack = String(query ?? '').toLowerCase();
  const words = haystack.split(/[^a-z0-9]+/).filter((w) => w.length > 2);

  const scored = guidelines
    .map((entry) => {
      const topicHits = entry.topics.reduce(
        (total, topic) => total + (haystack.includes(topic) ? 2 : 0),
        0,
      );
      const wordHits = words.filter(
        (word) => entry.title.toLowerCase().includes(word) || entry.body.toLowerCase().includes(word),
      ).length;
      return { entry, score: topicHits + wordHits };
    })
    .filter(({ score }) => score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, limit);

  return scored.map(({ entry }) => ({ ...entry }));
}

export default guidelines;
