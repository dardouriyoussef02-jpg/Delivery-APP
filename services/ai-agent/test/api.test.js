import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { startTestApp } from './helpers.js';

let server;
let base;
let token;
let auth;

before(async () => {
  const started = await startTestApp();
  server = started.server;
  base = started.base;
  auth = started.auth;

  // Every endpoint behind /api/v1 now needs a real session.
  const login = await started.login();
  assert.equal(login.status, 200, 'seeded driver must be able to log in');
  token = login.body.token;
});

after(async () => {
  server?.closeIdleConnections?.();
  server?.close();
  await new Promise((resolve) => server?.once('close', resolve));
});

test('GET /health reports the service is alive', async () => {
  const response = await fetch(`${base}/health`);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.status, 'ok');
  assert.equal(body.llmProvider, 'mock');
});

test('GET /api/v1/deliveries returns the driver route', async () => {
  const response = await fetch(`${base}/api/v1/deliveries`, { headers: auth(token) });
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.ok(body.count >= 4);
  assert.equal(body.deliveries[0].id, 'DLV-1042');
});

test('GET /api/v1/deliveries/:id returns one delivery', async () => {
  const response = await fetch(`${base}/api/v1/deliveries/DLV-1043`, { headers: auth(token) });
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.customer.firstName, 'Marco');

  const missing = await fetch(`${base}/api/v1/deliveries/DLV-0000`, { headers: auth(token) });
  assert.equal(missing.status, 404);
});

test('POST /api/v1/agent/suggest runs the full agent loop', async () => {
  const response = await fetch(`${base}/api/v1/agent/suggest`, {
    method: 'POST',
    headers: auth(token, { 'content-type': 'application/json' }),
    body: JSON.stringify({ deliveryId: 'DLV-1042' }),
  });

  assert.equal(response.status, 200);
  const suggestion = await response.json();
  assert.equal(suggestion.situation.type, 'access_instructions');
  assert.equal(suggestion.requiresApproval, true);
  assert.ok(suggestion.trace.length >= 3);
  assert.ok(suggestion.latencyMs >= 0);
});

test('POST /api/v1/agent/suggest requires deliveryId', async () => {
  const response = await fetch(`${base}/api/v1/agent/suggest`, {
    method: 'POST',
    headers: auth(token, { 'content-type': 'application/json' }),
    body: JSON.stringify({}),
  });
  assert.equal(response.status, 400);
});

test('POST /api/v1/agent/messages records a driver-approved message', async () => {
  const response = await fetch(`${base}/api/v1/agent/messages`, {
    method: 'POST',
    headers: auth(token, { 'content-type': 'application/json', 'x-driver-id': 'DRV-77' }),
    body: JSON.stringify({
      deliveryId: 'DLV-1042',
      channel: 'sms',
      recipient: 'Sanne',
      body: 'Hi Sanne, your driver will use the access instructions from your note. See you shortly - ref DLV-1042.',
      action: 'follow_access_instructions',
    }),
  });

  assert.equal(response.status, 201);
  const body = await response.json();
  assert.equal(body.status, 'sent');
  assert.ok(body.messageId.startsWith('MSG-'));

  const outbox = await (await fetch(`${base}/api/v1/messages/outbox`, { headers: auth(token) })).json();
  assert.ok(outbox.messages.some((m) => m.deliveryId === 'DLV-1042'));
});

test('PATCH /api/v1/deliveries/:id/status updates the stop', async () => {
  const response = await fetch(`${base}/api/v1/deliveries/DLV-1045/status`, {
    method: 'PATCH',
    headers: auth(token, { 'content-type': 'application/json' }),
    body: JSON.stringify({ status: 'delivered', label: 'Handed over in person' }),
  });
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.status, 'delivered');

  const invalid = await fetch(`${base}/api/v1/deliveries/DLV-1045/status`, {
    method: 'PATCH',
    headers: auth(token, { 'content-type': 'application/json' }),
    body: JSON.stringify({ status: 'skyrocket' }),
  });
  assert.equal(invalid.status, 400);
});
