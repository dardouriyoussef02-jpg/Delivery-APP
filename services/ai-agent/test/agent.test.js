import test from 'node:test';
import assert from 'node:assert/strict';

import { classifyNote, composeMessage, confidenceFor } from '../src/agent/heuristics.js';
import { searchGuidelines } from '../src/data/guidelines.js';
import { parseJsonLoose, validateSuggestion } from '../src/agent/validate.js';
import { createToolExecutor } from '../src/agent/tools.js';
import { createAgent } from '../src/agent/orchestrator.js';
import { createDeliveryGateway } from '../src/data/gateway.js';
import { deliveryStore } from '../src/data/deliveries.js';

const gateway = createDeliveryGateway();
const agent = createAgent({ deliveryStore: gateway, provider: 'mock' });

test('classifyNote recognises the common delivery-note situations', () => {
  assert.equal(classifyNote('Gate code 4482, leave with neighbour').type, 'access_instructions');
  assert.equal(classifyNote('Nobody will be home, please leave it in the porch').type, 'recipient_unavailable');
  assert.equal(classifyNote('The box is crushed and the seal is open').type, 'damaged_parcel');
  assert.equal(classifyNote('Can we move this to tomorrow morning?').type, 'reschedule_request');
  assert.equal(classifyNote('Please let me know when you are 10 minutes away').type, 'delivery_update_requested');
  assert.equal(classifyNote('Ring twice, I am hard of hearing').type, 'special_handling');
  assert.equal(classifyNote('Deliver like any other stop').type, 'general_note');
});

test('composeMessage stays inside the length guardrails', async () => {
  const delivery = await deliveryStore.get('DLV-1042');
  const samples = {
    access_instructions: 'Gate code 4482, leave with neighbour if nobody opens.',
    recipient_unavailable: 'Not home today, please leave it in the porch.',
    damaged_parcel: 'The box is damaged and the seal is open.',
    reschedule_request: 'Can we move this to tomorrow morning?',
    delivery_update_requested: 'Let me know when you are 10 minutes away.',
    special_handling: 'Ring twice, I am hard of hearing.',
    general_note: 'Deliver like any other stop.',
  };

  for (const [type, note] of Object.entries(samples)) {
    const body = composeMessage({
      delivery,
      situation: classifyNote(note),
      channel: 'sms',
    });
    const length = [...body].length;
    assert.ok(length >= 40, `${type} too short: ${length}`);
    assert.ok(length <= 320, `${type} too long: ${length}`);
    assert.ok(body.includes('Sanne'), `${type} should address the customer`);
  }
});

test('confidenceFor stays between 0 and 1', () => {
  const general = classifyNote('no keywords at all');
  assert.ok(confidenceFor(general) >= 0 && confidenceFor(general) < 0.6);
  const strong = classifyNote('gate code 1234');
  assert.ok(confidenceFor(strong, { hasHistory: true, noteLength: 80 }) <= 0.97);
});

test('searchGuidelines returns only relevant SOPs', () => {
  const access = searchGuidelines('gate code is broken buzzer');
  assert.ok(access.length > 0);
  assert.equal(access[0].id, 'SOP-ACCESS');

  const damage = searchGuidelines('parcel crushed seal open refuse');
  assert.ok(damage.some((entry) => entry.id === 'SOP-DAMAGE'));

  assert.deepEqual(searchGuidelines('xyzzy no matching topic'), []);
});

test('validateSuggestion accepts a good suggestion and rejects bad ones', () => {
  const good = {
    situation: { type: 'access_instructions', label: 'Access instructions given' },
    confidence: 0.88,
    reasoning: 'The note contains a gate code and a neighbour instruction.',
    recommendedAction: {
      type: 'follow_access_instructions',
      label: 'Follow the access instructions in the note',
      reason: 'Using the code avoids a failed attempt at a gated building.',
    },
    message: {
      channel: 'sms',
      recipient: 'Sanne',
      body: 'Hi Sanne, your driver is on the way and will use the access instructions from your note. Reply here if anything changes - ref DLV-1042.',
    },
  };

  assert.equal(validateSuggestion(good).valid, true);

  const tooLong = { ...good, message: { ...good.message, body: 'x'.repeat(400) } };
  const longResult = validateSuggestion(tooLong);
  assert.equal(longResult.valid, false);
  assert.ok(longResult.errors.some((e) => e.includes('too long')));

  const marketing = { ...good, message: { ...good.message, body: `${good.message.body} Get 10% discount today!` } };
  assert.equal(validateSuggestion(marketing).valid, false);

  const badAction = { ...good, recommendedAction: { ...good.recommendedAction, type: 'do_backflip' } };
  assert.equal(validateSuggestion(badAction).valid, false);

  assert.equal(validateSuggestion({}).valid, false);
});

test('parseJsonLoose handles fenced and prose-wrapped output', () => {
  assert.deepEqual(parseJsonLoose('{"a":1}'), { a: 1 });
  assert.deepEqual(parseJsonLoose('```json\n{"a":1}\n```'), { a: 1 });
  assert.deepEqual(parseJsonLoose('Here you go:\n{"nested":{"b":2}}\nHope that helps'), { nested: { b: 2 } });
  assert.throws(() => parseJsonLoose('no json here'));
});

test('draft_message tool enforces guardrails', async () => {
  const tools = createToolExecutor({ deliveryStore });

  const tooShort = await tools.execute('draft_message', {
    channel: 'sms',
    recipient: 'Sanne',
    body: 'Too short',
  });
  assert.equal(tooShort.ok, false);

  const withMarketing = await tools.execute('draft_message', {
    channel: 'sms',
    recipient: 'Sanne',
    body: 'Hi Sanne, your driver is 10 minutes away with your order. Use promo FREESHIP for your next order!',
  });
  assert.equal(withMarketing.ok, false);
  assert.ok(withMarketing.errors.some((e) => e.includes('promo')));

  const good = await tools.execute('draft_message', {
    channel: 'whatsapp',
    recipient: 'Sanne',
    body: 'Hi Sanne, your driver is 10 minutes away from Kanalstraat with order DLV-1042. We will message again if the ETA changes.',
  });
  assert.equal(good.ok, true);
  assert.ok(good.draft.charCount > 40);
});

test('agent understands a gate-code note and proposes a grounded action', async () => {
  const result = await agent.suggest({ deliveryId: 'DLV-1042' });

  assert.equal(result.deliveryId, 'DLV-1042');
  assert.equal(result.provider, 'mock');
  assert.equal(result.requiresApproval, true);
  assert.equal(result.situation.type, 'access_instructions');
  assert.equal(result.recommendedAction.type, 'follow_access_instructions');
  assert.equal(result.message.channel, 'sms');
  assert.ok(result.confidence >= 0.5 && result.confidence <= 1);

  const toolsUsed = result.trace.map((step) => step.tool);
  assert.ok(toolsUsed.includes('get_delivery'));
  assert.ok(toolsUsed.includes('search_guidelines'));
  assert.ok(toolsUsed.includes('draft_message'));

  assert.ok(result.message.charCount <= 320);
  assert.ok(result.message.body.includes('DLV-1042'));
  assert.equal(validateSuggestion(result).valid, true);
});

test('agent escalates a damaged parcel to dispatch', async () => {
  const result = await agent.suggest({ deliveryId: 'DLV-1043' });

  assert.equal(result.situation.type, 'damaged_parcel');
  assert.equal(result.recommendedAction.type, 'flag_to_dispatch');
  assert.equal(result.message.channel, 'whatsapp');
  assert.ok(result.message.body.toLowerCase().includes('damage'));
});

test('agent handles a reschedule request', async () => {
  const result = await agent.suggest({ deliveryId: 'DLV-1044' });

  assert.equal(result.situation.type, 'reschedule_request');
  assert.equal(result.recommendedAction.type, 'request_reschedule');
  assert.ok(result.trace.length >= 3);
});

test('agent accepts an inline note different from the stored one', async () => {
  const result = await agent.suggest({
    deliveryId: 'DLV-1045',
    note: 'Customer called: not home, please leave the parcel with the neighbour at number 12.',
  });

  assert.equal(result.note.includes('neighbour at number 12'), true);
  assert.ok(['recipient_unavailable', 'access_instructions'].includes(result.situation.type));
});

test('agent fails with 404 for an unknown delivery', async () => {
  await assert.rejects(() => agent.suggest({ deliveryId: 'DLV-9999' }), /not found/i);
});

test('agent fails with 400 when there is no note at all', async () => {
  const bare = { ...(await deliveryStore.get('DLV-1045')), notes: [] };
  const emptyStore = {
    get: async () => bare,
    list: async () => [bare],
    updateStatus: async () => bare,
    sendMessage: async (m) => m,
  };
  const bareAgent = createAgent({ deliveryStore: emptyStore, provider: 'mock' });
  await assert.rejects(() => bareAgent.suggest({ deliveryId: 'DLV-1045' }), /no delivery note/i);
});
