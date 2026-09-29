import config from '../../config.js';
import { createAnthropicModel } from './anthropic.js';
import { createMockModel } from './mock.js';

/**
 * @param {{provider?: string, hooks: {getDeliveryContext: Function, getNote: Function}}} options
 *
 * Throws an error tagged `code: 'LLM_CONFIG'` when the provider cannot be
 * built (missing API key, unknown provider) so callers can decide whether to
 * fall back to the offline model.
 */
export function createModel({ provider = config.llm.provider, hooks } = {}) {
  const resolved = provider.toLowerCase();

  if (resolved === 'anthropic') {
    return createAnthropicModel();
  }

  if (resolved !== 'mock') {
    const error = new Error(`Unknown LLM_PROVIDER "${provider}" (expected "mock" or "anthropic")`);
    error.code = 'LLM_CONFIG';
    throw error;
  }

  if (!hooks) {
    const error = new Error('mock provider requires hooks (getDeliveryContext / getNote)');
    error.code = 'LLM_CONFIG';
    throw error;
  }
  return createMockModel(hooks);
}

export default createModel;
