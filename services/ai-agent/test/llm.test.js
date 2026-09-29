import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';

import config from '../src/config.js';
import { createAnthropicModel } from '../src/agent/llm/anthropic.js';
import { createModel } from '../src/agent/llm/index.js';
import { createAgent } from '../src/agent/orchestrator.js';
import { createDeliveryGateway } from '../src/data/gateway.js';
import { deliveryStore } from '../src/data/deliveries.js';

/**
 * The real Anthropic API needs a paid key, so these tests speak the *contract*
 * of the Messages API through a local stub: same request/response shape, same
 * tool-use round trip. That verifies the adapter, the wiring and the full
 * agent workflow without ever needing ANTHROPIC_API_KEY (and without any
 * network access).
 */

const API_KEY = 'sk-test-not-a-real-key';

const FINAL_JSON = JSON.stringify({
  situation: { type: 'access_instructions', label: 'Access instructions provided' },
  confidence: 0.93,
  reasoning: 'The customer supplied a gate code and a neighbour fallback for the delivery attempt.',
  recommendedAction: {
    type: 'follow_access_instructions',
    label: 'Follow the access instructions',
    reason: 'Using the gate code avoids a failed first attempt at the building.',
  },
  message: {
    channel: 'sms',
    recipient: 'Sanne',
    body: 'Hi Sanne, your driver will use the access instructions from your note and follow the gate code on arrival - ref DLV-1042.',
  },
});

let stub;
let stubUrl;
let mode = 'happy'; // happy | slow | http500
let lastApiKey = null;
let requests = 0;

/** Saved config so every test restores the environment it found. */
const saved = {};

function stubConfig({ key = API_KEY, url = stubUrl, fallback } = {}) {
  saved.key ??= config.llm.anthropicKey;
  saved.url ??= config.llm.anthropicUrl;
  saved.fallback ??= config.llm.fallback;
  config.llm.anthropicKey = key;
  config.llm.anthropicUrl = url;
  if (fallback !== undefined) config.llm.fallback = fallback;
}

function restoreConfig() {
  if (saved.key !== undefined) config.llm.anthropicKey = saved.key;
  if (saved.url !== undefined) config.llm.anthropicUrl = saved.url;
  if (saved.fallback !== undefined) config.llm.fallback = saved.fallback;
  saved.key = saved.url = saved.fallback = undefined;
}

before(async () => {
  stub = createServer((req, res) => {
    let raw = '';
    req.on('data', (chunk) => {
      raw += chunk;
    });
    req.on('end', () => {
      requests += 1;
      lastApiKey = req.headers['x-api-key'] ?? null;

      if (mode === 'http500') {
        res.writeHead(500, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ error: { type: 'overloaded_error' } }));
        return;
      }

      const reply = () => {
        let wantsText = false;
        try {
          const body = JSON.parse(raw);
          wantsText = (body.messages ?? []).some(
            (message) =>
              Array.isArray(message.content) &&
              message.content.some((block) => block.type === 'tool_result'),
          );
        } catch {
          wantsText = false;
        }

        const payload = wantsText
          ? { content: [{ type: 'text', text: FINAL_JSON }], stop_reason: 'end_turn' }
          : {
              content: [
                { type: 'tool_use', id: 'tu_1', name: 'get_delivery', input: { deliveryId: 'DLV-1042' } },
                { type: 'tool_use', id: 'tu_2', name: 'list_delivery_events', input: { deliveryId: 'DLV-1042' } },
                { type: 'tool_use', id: 'tu_3', name: 'search_guidelines', input: { query: 'gate code' } },
                {
                  type: 'tool_use',
                  id: 'tu_4',
                  name: 'draft_message',
                  input: {
                    channel: 'sms',
                    recipient: 'Sanne',
                    body: 'Hi Sanne, your driver will use the access instructions from your note - ref DLV-1042.',
                  },
                },
              ],
              stop_reason: 'tool_use',
            };

        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify(payload));
      };

      if (mode === 'slow') setTimeout(reply, 500);
      else reply();
    });
  });

  await new Promise((resolve) => stub.listen(0, '127.0.0.1', resolve));
  stubUrl = `http://127.0.0.1:${stub.address().port}/v1/messages`;
});

after(() => {
  stub?.closeAllConnections?.();
  stub?.close();
});

function gateway() {
  return createDeliveryGateway({ store: deliveryStore });
}

// ------------------------------------------------------------- adapter shape

test('the Anthropic adapter speaks the Messages API contract', async () => {
  stubConfig();
  const model = createAnthropicModel();

  const response = await model.complete({
    system: 'system prompt',
    messages: [{ role: 'user', content: 'hello' }],
    tools: [{ name: 'get_delivery' }],
  });

  assert.equal(response.stopReason, 'tool_use');
  assert.equal(response.toolCalls.length, 4);
  assert.equal(response.toolCalls[0].name, 'get_delivery');
  assert.equal(response.toolCalls[3].name, 'draft_message');
  assert.equal(lastApiKey, API_KEY, 'the key must be sent as x-api-key, never in the body');
});

test('the adapter parses a final text answer', async () => {
  stubConfig();
  const model = createAnthropicModel();

  const response = await model.complete({
    system: 'system prompt',
    messages: [
      { role: 'user', content: 'go' },
      { role: 'assistant', content: [{ type: 'tool_use', id: 'tu_1', name: 'get_delivery', input: {} }] },
      { role: 'user', content: [{ type: 'tool_result', tool_use_id: 'tu_1', content: '{}' }] },
    ],
  });

  assert.equal(response.toolCalls.length, 0);
  assert.ok(response.text.includes('"situation"'));
});

// ------------------------------------------------------------- failure modes

test('a missing API key is reported as a configuration error, not a crash', () => {
  assert.throws(
    () => createAnthropicModel({ key: '' }),
    (error) => error.code === 'LLM_CONFIG' && /ANTHROPIC_API_KEY/.test(error.message),
  );

  stubConfig({ key: '' });
  try {
    assert.throws(
      () => createModel({ provider: 'anthropic', hooks: {} }),
      (error) => error.code === 'LLM_CONFIG',
    );
  } finally {
    restoreConfig();
  }
});

test('an unknown provider is a configuration error', () => {
  assert.throws(
    () => createModel({ provider: 'definitely-not-a-model', hooks: {} }),
    (error) => error.code === 'LLM_CONFIG',
  );
});

test('a slow API call times out as a transport error', async () => {
  stubConfig();
  mode = 'slow';
  const model = createAnthropicModel({ timeoutMs: 50 });
  try {
    await assert.rejects(
      () => model.complete({ system: 's', messages: [{ role: 'user', content: 'x' }] }),
      (error) => error.code === 'LLM_TRANSPORT' && /timed out after 50ms/.test(error.message),
    );
  } finally {
    mode = 'happy';
  }
});

test('an HTTP error from the API is a transport error', async () => {
  stubConfig();
  mode = 'http500';
  const model = createAnthropicModel();
  try {
    await assert.rejects(
      () => model.complete({ system: 's', messages: [{ role: 'user', content: 'x' }] }),
      (error) => error.code === 'LLM_TRANSPORT' && /Anthropic API 500/.test(error.message),
    );
  } finally {
    mode = 'happy';
  }
});

test('an unreachable API endpoint is a transport error', async () => {
  const model = createAnthropicModel({ key: API_KEY, url: 'http://127.0.0.1:9/v1/messages' });
  await assert.rejects(
    () => model.complete({ system: 's', messages: [{ role: 'user', content: 'x' }] }),
    (error) => error.code === 'LLM_TRANSPORT',
  );
});

// ------------------------------------------------------- full workflow (stub)

test('the complete agent workflow runs on the Anthropic provider', async () => {
  stubConfig();
  const before = requests;

  const agent = createAgent({ deliveryStore: gateway(), provider: 'anthropic' });
  const result = await agent.suggest({ deliveryId: 'DLV-1042' });

  // Response structure the mobile app depends on - unchanged.
  assert.equal(result.provider, 'anthropic');
  assert.equal(result.deliveryId, 'DLV-1042');
  assert.equal(result.situation.type, 'access_instructions');
  assert.ok(result.confidence > 0 && result.confidence <= 1);
  assert.ok(result.reasoning.length > 0);
  assert.equal(result.recommendedAction.type, 'follow_access_instructions');
  assert.ok(result.message.body.length >= 40);
  assert.equal(result.requiresApproval, true);
  assert.ok(result.trace.length >= 3, 'tool trace kept');
  assert.ok(result.latencyMs >= 0);

  // The real tool loop ran against real (demo) data.
  const toolsUsed = result.trace.map((step) => step.tool);
  assert.ok(toolsUsed.includes('get_delivery'));
  assert.ok(toolsUsed.includes('draft_message'));
  assert.equal(toolsUsed.includes('llm_fallback'), false, 'no fallback needed');

  assert.ok(requests - before >= 2, 'tool round trip + final answer');
  assert.equal(JSON.stringify(result).includes(API_KEY), false, 'the key never leaves the server');
});

// ------------------------------------------------------------- fallback paths

test('a transport failure falls back to the offline model and says so', async () => {
  stubConfig({ url: 'http://127.0.0.1:9/v1/messages' });
  try {
    const agent = createAgent({ deliveryStore: gateway(), provider: 'anthropic' });
    const result = await agent.suggest({ deliveryId: 'DLV-1042' });

    assert.equal(result.provider, 'anthropic->mock');
    const fallback = result.trace.find((step) => step.tool === 'llm_fallback');
    assert.ok(fallback, 'the fallback is visible in the trace');
    assert.match(fallback.detail, /LLM_TRANSPORT|failed/i);

    // The driver still gets a complete, valid suggestion.
    assert.equal(result.situation.type, 'access_instructions');
    assert.ok(result.message.body.length >= 40);
    assert.equal(result.requiresApproval, true);
  } finally {
    restoreConfig();
  }
});

test('a missing key falls back instead of failing the driver', async () => {
  stubConfig({ key: '' });
  try {
    const agent = createAgent({ deliveryStore: gateway(), provider: 'anthropic' });
    const result = await agent.suggest({ deliveryId: 'DLV-1043' });

    assert.equal(result.provider, 'anthropic->mock');
    const fallback = result.trace.find((step) => step.tool === 'llm_fallback');
    assert.ok(fallback);
    assert.match(fallback.detail, /ANTHROPIC_API_KEY/);
    assert.equal(result.situation.type, 'damaged_parcel');
  } finally {
    restoreConfig();
  }
});

test('with LLM_FALLBACK=off the failure surfaces as an HTTP-mapped error', async () => {
  stubConfig({ url: 'http://127.0.0.1:9/v1/messages', fallback: 'off' });
  try {
    const agent = createAgent({ deliveryStore: gateway(), provider: 'anthropic' });
    await assert.rejects(
      () => agent.suggest({ deliveryId: 'DLV-1042' }),
      (error) => error.status === 502 && error.code === 'LLM_TRANSPORT',
    );
  } finally {
    restoreConfig();
  }

  stubConfig({ key: '', fallback: 'off' });
  try {
    const agent = createAgent({ deliveryStore: gateway(), provider: 'anthropic' });
    await assert.rejects(
      () => agent.suggest({ deliveryId: 'DLV-1042' }),
      (error) => error.status === 503 && error.code === 'LLM_CONFIG',
    );
  } finally {
    restoreConfig();
  }
});

test('the default provider for tests stays the offline model', async () => {
  const agent = createAgent({ deliveryStore: gateway(), provider: 'mock' });
  const result = await agent.suggest({ deliveryId: 'DLV-1042' });
  assert.equal(result.provider, 'mock');
  assert.equal(result.trace.some((step) => step.tool === 'llm_fallback'), false);
});
