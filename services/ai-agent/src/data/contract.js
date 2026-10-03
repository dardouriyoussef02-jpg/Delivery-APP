/**
 * The driver partnership agreement, owned by the backend so every client
 * (mobile app, dispatch tooling, tests) reads exactly the same text and a
 * signed copy can be snapshotted next to the signature.
 *
 * Bump `version` whenever the wording changes: existing signatures keep the
 * version they agreed to, so a re-sign is only ever required by policy, never
 * silently by a deploy.
 */
export const CONTRACT = {
  version: '1.0',
  title: 'Driver Partnership Agreement',
  company: 'ShiftFlow Logistics',
  sections: [
    {
      heading: '1. Engagement',
      body:
        'This agreement is entered into between ShiftFlow Logistics ("the company") and the ' +
        'driver named below. The company dispatches parcel deliveries to the driver through ' +
        'the ShiftFlow driver application. The driver accepts work by signing this agreement; ' +
        'no deliveries are assigned before it is signed.',
    },
    {
      heading: '2. Assigning of work',
      body:
        'Deliveries become visible to the driver only once the company has assigned them to ' +
        'that driver. The driver sees only their own route. Assignment does not guarantee a ' +
        'minimum volume of work, and either party may stop dispatching at any time.',
    },
    {
      heading: '3. Driver duties',
      body:
        'The driver will collect parcels from the hub within the agreed window, verify ' +
        'recipient details before hand-over, record the real status of every stop, and report ' +
        'failed attempts the same day. Cash-on-delivery amounts must be reconciled at the end ' +
        'of each shift.',
    },
    {
      heading: '4. Safety and conduct',
      body:
        'The driver will operate within local traffic law, use approved equipment, and never ' +
        'drive while impaired or fatigued. Damaged, refused or missing parcels must be ' +
        'returned to the hub rather than left with a third party.',
    },
    {
      heading: '5. Customer data',
      body:
        'Addresses, telephone numbers and notes are shared for the sole purpose of completing ' +
        'the delivery. The driver will not copy, publish or retain them after the shift, and ' +
        'will use the approved messaging channel for all customer contact.',
    },
    {
      heading: '6. Term and termination',
      body:
        'This agreement starts on the date of signature and continues until either party ' +
        'ends it. Ending it does not affect deliveries already in transit, which must be ' +
        'completed or handed back to dispatch.',
    },
    {
      heading: '7. Electronic signature',
      body:
        'By typing their full name and confirming this agreement, the driver agrees that the ' +
        'electronic signature and timestamp recorded by the company have the same effect as a ' +
        'handwritten signature.',
    },
  ],
};

/** Flat text of the agreement - what gets stored alongside the signature. */
export function renderContract(contract = CONTRACT) {
  return [contract.title, ...contract.sections.map((s) => `${s.heading}\n${s.body}`)].join('\n\n');
}

export default { CONTRACT, renderContract };
