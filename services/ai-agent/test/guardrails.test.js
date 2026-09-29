import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';

import { validateOutgoingMessage } from '../src/agent/validate.js';
import { startTestApp } from './helpers.js';

let base;
let token;
let auth;
let closeApp;

const GOOD_BODY =
  'Hi Sanne, your driver will use the access instructions from your note. See you shortly - ref DLV-1042.';

before(async () => {
  const started = await startTestApp();
  base = started.base;
  auth = started.auth;
  closeApp = started.close;
  const login = await started.login();
  assert.equal(login.status, 200);
  token = login.body.token;
});

after(async () => {
  await closeApp?.();
});

async function send(payload, { withToken = true } = {}) {
  const response = await fetch(`${base}/api/v1/agent/messages`, {
    method: 'POST',
    headers: auth(withToken ? token : null, { 'content-type': 'application/json' }),
    body: JSON.stringify(payload),
  });
  return { status: response.status, body: await response.json().catch(() => ({})) };
}

// ----------------------------------------------------------- unit validator

test('validateOutgoingMessage applies the same rules as the agent drafts', () => {
  const good = {
    deliveryId: 'DLV-1042',
    channel: 'sms',
    recipient: 'Sanne',
    body: GOOD_BODY,
    action: 'follow_access_instructions',
  };
  assert.deepEqual(validateOutgoingMessage(good), { valid: true, errors: [] });

  const short = validateOutgoingMessage({ ...good, body: 'Too short' });
  assert.equal(short.valid, false);
  assert.ok(short.errors.some((e) => e.includes('too short')));

  const long = validateOutgoingMessage({ ...good, body: 'x'.repeat(400) });
  assert.equal(long.valid, false);
  assert.ok(long.errors.some((e) => e.includes('too long')));

  const marketing = validateOutgoingMessage({ ...good, body: `${GOOD_BODY} Get 10% discount today!` });
  assert.equal(marketing.valid, false);
  assert.ok(marketing.errors.some((e) => e.includes('banned word')));

  const badChannel = validateOutgoingMessage({ ...good, channel: 'pigeon' });
  assert.equal(badChannel.valid, false);

  const badAction = validateOutgoingMessage({ ...good, action: 'do_a_backflip' });
  assert.equal(badAction.valid, false);

  const missing = validateOutgoingMessage({ deliveryId: 'DLV-1042' });
  assert.equal(missing.valid, false);
  assert.ok(missing.errors.some((e) => e.includes('recipient')));
  assert.ok(missing.errors.some((e) => e.includes('body')));
});

// --------------------------------------------------- HTTP send guardrails

test('a valid approved message is still accepted (201)', async () => {
  const { status, body } = await send({
    deliveryId: 'DLV-1042',
    channel: 'sms',
    recipient: 'Sanne',
    body: GOOD_BODY,
    action: 'follow_access_instructions',
  });

  assert.equal(status, 201);
  assert.equal(body.status, 'sent');
  assert.ok(body.messageId.startsWith('MSG-'));
  assert.equal(body.sentBy, 'DRV-77'); // identity from the session, not the client
});

test('a banned-word message is rejected with 422 (the MSG-0002 bug)', async () => {
  const { status, body } = await send({
    deliveryId: 'DLV-1043',
    channel: 'sms',
    recipient: 'Marco',
    body: ' idiot customer, stupid request, your parcel is late again and nobody cares',
  });

  assert.equal(status, 422);
  assert.match(body.error, /guardrail/);
  assert.ok(Array.isArray(body.errors) && body.errors.length > 0);

  // Nothing was stored.
  const outbox = await (await fetch(`${base}/api/v1/messages/outbox`, { headers: auth(token) })).json();
  assert.equal(
    outbox.messages.some((m) => String(m.body).includes('idiot')),
    false,
  );
});

test('a too-short message is rejected with 422', async () => {
  const { status, body } = await send({
    deliveryId: 'DLV-1042',
    channel: 'sms',
    recipient: 'Sanne',
    body: 'Too short',
  });
  assert.equal(status, 422);
  assert.ok(body.errors.some((e) => e.includes('too short')));
});

test('a too-long message is rejected with 422', async () => {
  const { status } = await send({
    deliveryId: 'DLV-1042',
    channel: 'sms',
    recipient: 'Sanne',
    body: 'x'.repeat(500),
  });
  assert.equal(status, 422);
});

test('marketing content is rejected with 422', async () => {
  const { status, body } = await send({
    deliveryId: 'DLV-1042',
    channel: 'whatsapp',
    recipient: 'Sanne',
    body: `${GOOD_BODY} Use promo FREESHIP on your next order with a free upgrade!`,
  });
  assert.equal(status, 422);
  assert.ok(body.errors.some((e) => e.includes('banned word')));
});

test('missing fields are rejected with 400', async () => {
  const { status, body } = await send({ deliveryId: 'DLV-1042', channel: 'sms' });
  assert.equal(status, 400);
  assert.match(body.error, /missing fields/);
});

test('an unknown delivery is rejected with 404 before anything is stored', async () => {
  const { status } = await send({
    deliveryId: 'DLV-9999',
    channel: 'sms',
    recipient: 'Nobody',
    body: GOOD_BODY,
  });
  assert.equal(status, 404);
});

test('the send endpoint rejects unauthenticated callers with 401', async () => {
  const { status } = await send(
    {
      deliveryId: 'DLV-1042',
      channel: 'sms',
      recipient: 'Sanne',
      body: GOOD_BODY,
    },
    { withToken: false },
  );
  assert.equal(status, 401);
});

test('an invalid action is rejected with 422', async () => {
  const { status, body } = await send({
    deliveryId: 'DLV-1042',
    channel: 'sms',
    recipient: 'Sanne',
    body: GOOD_BODY,
    action: 'send_nudes',
  });
  assert.equal(status, 422);
  assert.ok(body.errors.some((e) => e.includes('action')));
});
