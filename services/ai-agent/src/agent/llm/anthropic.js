import config from '../../config.js';

/**
 * Claude (Anthropic Messages API) adapter using the built-in fetch, so the
 * service has no SDK dependency and stays trivially portable.
 *
 * Returns the same shape as the mock model:
 * `{ stopReason, text, toolCalls: [{ id, name, input }] }`
 *
 * Failures are tagged so the orchestrator can tell them apart from bugs:
 *   - `code: 'LLM_CONFIG'`    - the provider was not configured (missing key)
 *   - `code: 'LLM_TRANSPORT'` - network/timeout/API error while calling Claude
 *
 * The API key is read from the server environment only and never leaves this
 * process (it is never included in a response body either).
 */
export function createAnthropicModel({ key, model, maxTokens, url, timeoutMs } = {}) {
  const apiKey = key ?? config.llm.anthropicKey;
  const modelName = model ?? config.llm.anthropicModel;
  const endpoint = url ?? config.llm.anthropicUrl;
  const tokens = maxTokens ?? config.llm.anthropicMaxTokens;
  const timeout = timeoutMs ?? config.llm.anthropicTimeoutMs;

  if (!apiKey) {
    const error = new Error(
      'LLM_PROVIDER=anthropic requires ANTHROPIC_API_KEY. Set it in services/ai-agent/.env ' +
        `(or switch back with LLM_PROVIDER=mock; LLM_FALLBACK=${config.llm.fallback}).`,
    );
    error.code = 'LLM_CONFIG';
    throw error;
  }

  return {
    name: 'anthropic',

    async complete({ system, messages, tools }) {
      let response;
      try {
        response = await fetch(endpoint, {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
          },
          body: JSON.stringify({
            model: modelName,
            max_tokens: tokens,
            system,
            messages,
            ...(Array.isArray(tools) && tools.length > 0 ? { tools } : {}),
          }),
          signal: AbortSignal.timeout(timeout),
        });
      } catch (error) {
        // DNS failures, refused connections, aborted by the timeout...
        const reason = error?.name === 'TimeoutError' || error?.name === 'AbortError'
          ? `Anthropic request timed out after ${timeout}ms`
          : `Anthropic request failed: ${error?.message ?? error}`;
        throw transport(reason, error);
      }

      if (!response.ok) {
        const detail = await response.text().catch(() => '');
        throw transport(`Anthropic API ${response.status}: ${detail.slice(0, 400)}`);
      }

      let payload;
      try {
        payload = await response.json();
      } catch (error) {
        throw transport('Anthropic returned a non-JSON response', error);
      }

      const text = (payload.content ?? [])
        .filter((block) => block.type === 'text')
        .map((block) => block.text)
        .join('');

      const toolCalls = (payload.content ?? [])
        .filter((block) => block.type === 'tool_use')
        .map((block) => ({ id: block.id, name: block.name, input: block.input ?? {} }));

      return {
        stopReason: payload.stop_reason ?? 'end_turn',
        text,
        toolCalls,
        usage: payload.usage,
      };
    },
  };
}

function transport(message, cause) {
  const error = new Error(message);
  error.code = 'LLM_TRANSPORT';
  if (cause) error.cause = cause;
  return error;
}

export default createAnthropicModel;
