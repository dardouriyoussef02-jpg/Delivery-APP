import config from '../config.js';
import { classifyNote } from './heuristics.js';
import { buildSystemPrompt, buildUserPrompt, CHANNELS } from './prompts.js';
import { createToolExecutor, toolSchemas } from './tools.js';
import { createModel } from './llm/index.js';
import { parseJsonLoose, validateSuggestion } from './validate.js';

const TOOL_LABELS = {
  get_delivery: 'Reading delivery context',
  list_delivery_events: 'Checking previous attempts',
  search_guidelines: 'Looking up company guidelines',
  draft_message: 'Drafting the customer message',
};

const REPAIR_PROMPT =
  'Your JSON failed validation. Fix ONLY the listed problems and reply with the corrected JSON object, no commentary. Problems: ';

/**
 * The agent loop:
 *   understand note -> retrieve context -> ground in guidelines ->
 *   draft message -> guardrail check -> (one repair) -> validated suggestion.
 *
 * Bounded by MAX_AGENT_TURNS so a misbehaving model can never spin.
 *
 * Provider behaviour:
 *   - `mock` (default): fully offline, used by tests and demos.
 *   - `anthropic`: real Claude API, requires ANTHROPIC_API_KEY server-side.
 *   - When the real model cannot be built (missing key) or fails mid-flight
 *     (timeout, API error, unusable output) the loop is re-run on the offline
 *     model as long as LLM_FALLBACK != "off", and the response reports it
 *     (e.g. `provider: "anthropic->mock"`) instead of failing the driver.
 *
 * @param {{deliveryStore: object, provider?: string}} deps
 */
export function createAgent({ deliveryStore, provider } = {}) {
  const tools = createToolExecutor({ deliveryStore });

  async function suggest({ deliveryId, note, driverId, channel }) {
    const startedAt = Date.now();
    const trace = [];

    const delivery = await deliveryStore.get(deliveryId);
    if (!delivery) {
      const error = new Error(`Delivery ${deliveryId} not found`);
      error.status = 404;
      throw error;
    }

    const effectiveNote = note?.trim() || defaultNote(delivery);
    if (!effectiveNote) {
      const error = new Error('No delivery note provided and none stored on the delivery');
      error.status = 400;
      throw error;
    }

    const hint = classifyNote(effectiveNote);
    const hooks = {
      getDeliveryContext: () => delivery,
      getNote: () => effectiveNote,
    };

    const system = buildSystemPrompt();
    const baseMessages = [
      {
        role: 'user',
        content: buildUserPrompt({
          delivery,
          note: effectiveNote,
          heuristicHint: `${hint.label} -> ${hint.actionLabel}`,
        }),
      },
    ];

    /**
     * Runs the complete loop (tool use -> draft -> validation -> one repair)
     * against one model. `messages` is always a fresh copy so a failed
     * attempt cannot poison a retry.
     */
    const runAgentLoop = async (model) => {
      const messages = [...baseMessages];
      let finalText = '';
      let repairCount = 0;
      const maxTurns = config.guardrails.maxAgentTurns;

      for (let turn = 0; turn < maxTurns; turn += 1) {
        const response = await model.complete({ system, messages, tools: toolSchemas });

        if (response.toolCalls?.length) {
          messages.push({ role: 'assistant', content: assistantBlocks(response) });

          const results = [];
          for (const call of response.toolCalls) {
            const step = { tool: call.name, label: TOOL_LABELS[call.name] ?? call.name, input: safeInput(call.input) };
            const stepStart = Date.now();
            const result = await tools.execute(call.name, call.input);
            results.push({ call, result });
            trace.push({
              ...step,
              ok: result.ok !== false,
              ms: Date.now() - stepStart,
              detail: summarise(call.name, result),
            });
            if (config.telemetry) {
              console.log(`[agent] ${call.name} -> ${result.ok !== false ? 'ok' : 'error'} (${Date.now() - stepStart}ms)`);
            }
          }

          messages.push({
            role: 'user',
            content: results.map(({ call, result }) => ({
              type: 'tool_result',
              tool_use_id: call.id,
              content: JSON.stringify(result),
            })),
          });
          continue;
        }

        finalText = response.text ?? '';
        break;
      }

      if (!finalText) {
        const error = new Error('The assistant did not produce a suggestion within the turn limit');
        error.status = 502;
        throw error;
      }

      let suggestion = tryParse(finalText, 'model output was not valid JSON');
      let validation = validateSuggestion(suggestion);

      while (!validation.valid && repairCount < 1) {
        repairCount += 1;
        trace.push({
          tool: 'validate',
          label: 'Validating the suggestion',
          ok: false,
          ms: 0,
          detail: `Sent back for repair: ${validation.errors.join('; ')}`,
        });

        messages.push({ role: 'assistant', content: finalText });
        messages.push({ role: 'user', content: REPAIR_PROMPT + validation.errors.join('; ') });

        const repaired = await model.complete({ system, messages, tools: [] });
        finalText = repaired.text ?? '';
        suggestion = tryParse(finalText, 'repaired output was not valid JSON');
        validation = validateSuggestion(suggestion);
      }

      if (!validation.valid) {
        const error = new Error(`Suggestion failed validation: ${validation.errors.join('; ')}`);
        error.status = 502;
        throw error;
      }

      return { suggestion, repairCount };
    };

    // --- pick the model, with a documented fallback to the offline one ---
    const requestedProvider = String(provider ?? config.llm.provider).toLowerCase();
    const fallbackEnabled = config.llm.fallback !== 'off';

    let model;
    let providerUsed;
    try {
      model = createModel({ provider, hooks });
      providerUsed = model.name;
    } catch (error) {
      // Missing API key / unknown provider: fall back unless disabled.
      if (!fallbackEnabled || requestedProvider === 'mock') {
        if (error.code === 'LLM_CONFIG') error.status = 503;
        throw error;
      }
      providerUsed = `${requestedProvider}->mock`;
      pushFallback(trace, `primary model unavailable: ${error.message}`);
      model = await createModel({ provider: 'mock', hooks });
    }

    let outcome;
    try {
      outcome = await runAgentLoop(model);
    } catch (error) {
      const fallbackable =
        error.code === 'LLM_TRANSPORT' ||
        error.code === 'LLM_CONFIG' ||
        error.status === 502;

      if (!fallbackable || !fallbackEnabled || providerUsed === 'mock') {
        if (error.code === 'LLM_TRANSPORT') error.status = 502;
        if (error.code === 'LLM_CONFIG') error.status = 503;
        throw error;
      }

      providerUsed = `${providerUsed}->mock`;
      pushFallback(trace, `${error.code ?? 'error'}: ${error.message}`);
      model = await createModel({ provider: 'mock', hooks });
      outcome = await runAgentLoop(model);
    }

    const { suggestion, repairCount } = outcome;
    const requestedChannel = channel ?? delivery.customer.preferredChannel;

    return {
      requestId: `SUG-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`,
      deliveryId: delivery.id,
      provider: providerUsed,
      note: effectiveNote,
      situation: suggestion.situation,
      confidence: Number(suggestion.confidence),
      reasoning: suggestion.reasoning,
      recommendedAction: suggestion.recommendedAction,
      message: {
        ...suggestion.message,
        channel: CHANNELS.includes(suggestion.message.channel)
          ? suggestion.message.channel
          : requestedChannel,
        charCount: [...String(suggestion.message.body)].length,
      },
      requiresApproval: true,
      trace,
      repairCount,
      latencyMs: Date.now() - startedAt,
      createdAt: new Date().toISOString(),
    };
  }

  return { suggest };
}

/** Records why the offline model took over - visible to support in the trace. */
function pushFallback(trace, reason) {
  trace.push({
    tool: 'llm_fallback',
    label: 'Falling back to the offline model',
    ok: true,
    ms: 0,
    detail: reason.length > 220 ? `${reason.slice(0, 220)}...` : reason,
  });
}

/**
 * Default note: the customer's most recent note (that is what the assistant is
 * built for). If only internal notes exist we fall back to the last one.
 */
function defaultNote(delivery) {
  const notes = delivery.notes ?? [];
  if (!notes.length) return '';
  const fromCustomer = [...notes].reverse().find((note) => note.author === 'customer');
  return (fromCustomer ?? notes[notes.length - 1]).text;
}

function assistantBlocks(response) {
  const blocks = [];
  if (response.text) blocks.push({ type: 'text', text: response.text });
  for (const call of response.toolCalls ?? []) {
    blocks.push({ type: 'tool_use', id: call.id, name: call.name, input: call.input });
  }
  return blocks;
}

function tryParse(text, message) {
  try {
    return parseJsonLoose(text);
  } catch (cause) {
    const error = new Error(`${message}: ${cause.message}`);
    error.status = 502;
    throw error;
  }
}

function safeInput(input) {
  const copy = { ...(input ?? {}) };
  if (typeof copy.body === 'string' && copy.body.length > 160) {
    copy.body = `${copy.body.slice(0, 160)}...`;
  }
  return copy;
}

function summarise(name, result) {
  switch (name) {
    case 'get_delivery':
      return result.ok ? `${result.delivery.customer.firstName} @ ${result.delivery.address.line1}` : result.error;
    case 'list_delivery_events':
      return result.ok ? `${result.events.length} events, ${result.previousAttempts.length} previous attempts` : result.error;
    case 'search_guidelines':
      return result.ok ? `${result.count} guideline(s): ${result.results.map((r) => r.id).join(', ') || 'none'}` : result.error;
    case 'draft_message':
      return result.ok
        ? `validated (${result.draft.charCount} chars, ${result.draft.channel})`
        : `rejected: ${result.errors.join('; ')}`;
    default:
      return result.ok === false ? result.error : 'ok';
  }
}

export default createAgent;
