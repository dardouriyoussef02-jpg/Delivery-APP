import config from '../config.js';
import { deliveryStore } from './deliveries.js';

/**
 * Single seam between this service and "the existing API" the client already
 * runs. When EXISTING_API_BASE_URL is configured every call is proxied to the
 * real backend; otherwise the bundled demo dataset is used so the product can
 * be demonstrated end-to-end.
 */
export function createDeliveryGateway({ store = deliveryStore, existingApi = config.existingApi } = {}) {
  async function request(path, init = {}) {
    const response = await fetch(`${existingApi.baseUrl}${path}`, {
      ...init,
      headers: {
        accept: 'application/json',
        ...(init.body ? { 'content-type': 'application/json' } : {}),
        ...(existingApi.apiKey ? { authorization: `Bearer ${existingApi.apiKey}` } : {}),
        ...(init.headers ?? {}),
      },
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) {
      throw new Error(`Existing API ${response.status} on ${path}`);
    }
    return response.json();
  }

  if (!existingApi.enabled) {
    return {
      mode: 'demo',
      list: (params) => store.list(params),
      get: (id) => store.get(id),
      updateStatus: (id, status, meta) => store.updateStatus(id, status, meta),
      sendMessage: (message) => store.sendMessage(message),
      // The in-memory demo store keeps an array, the SQLite store a method.
      outbox: async () => (typeof store.outbox === 'function' ? store.outbox() : store.outbox),
    };
  }

  return {
    mode: 'live',
    list: (params) => {
      const query = params?.driverId ? `?driverId=${encodeURIComponent(params.driverId)}` : '';
      return request(`/deliveries${query}`);
    },
    get: (id) => request(`/deliveries/${encodeURIComponent(id)}`),
    updateStatus: (id, status, meta = {}) =>
      request(`/deliveries/${encodeURIComponent(id)}/status`, {
        method: 'PATCH',
        body: JSON.stringify({ status, ...meta }),
      }),
    sendMessage: (message) =>
      request('/messages', {
        method: 'POST',
        body: JSON.stringify(message),
      }),
    outbox: async () => request('/messages'),
  };
}

export default createDeliveryGateway;
