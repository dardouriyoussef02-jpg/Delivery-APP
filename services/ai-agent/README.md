# delivery-ai-agent

Lightweight AI agent service that turns a delivery note into:

1. a **situation** (what the note means for this stop),
2. a **recommended next action** for the driver,
3. a **short customer message** the driver reviews, edits and sends.

It also exposes the delivery endpoints the mobile app needs, so the app has one
base URL to talk to.

## Run

```bash
npm install
npm start          # http://localhost:8787
npm run dev        # auto-reload (node --watch)
npm test           # node --test
```

## Configuration (`.env`)

| Variable | Default | Purpose |
| --- | --- | --- |
| `PORT` | `8787` | HTTP port |
| `LLM_PROVIDER` | `mock` | `mock` (offline, deterministic) or `anthropic` (Claude) |
| `ANTHROPIC_API_KEY` | – | required when provider is `anthropic` |
| `ANTHROPIC_MODEL` | `claude-sonnet-4-5` | any Claude model id |
| `EXISTING_API_BASE_URL` | – | when set, delivery reads/writes are proxied to your real API |
| `EXISTING_API_KEY` | – | bearer token forwarded to that API |
| `DRIVER_API_TOKEN` | – | when set, requests must send it in `X-Driver-Token` |
| `MAX_MESSAGE_CHARS` | `320` | hard limit enforced on drafts **and** final output |
| `MAX_AGENT_TURNS` | `6` | upper bound on the agent loop |

## Endpoints

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| GET | `/health` | – | service + model status |
| GET | `/api/v1/agent/health` | – | AI feature status |
| POST | `/api/v1/agent/suggest` | `{ deliveryId, note?, channel? }` | situation, action, draft, trace |
| POST | `/api/v1/agent/suggest/validate` | a suggestion object | `{ valid, errors }` (dry-run guardrails) |
| POST | `/api/v1/agent/messages` | `{ deliveryId, channel, recipient, body, action }` | `{ status: "sent", messageId }` |
| GET | `/api/v1/deliveries` | – | driver route (live API or demo data) |
| GET | `/api/v1/deliveries/:id` | – | one delivery |
| PATCH | `/api/v1/deliveries/:id/status` | `{ status, label }` | updated delivery |
| GET | `/api/v1/messages/outbox` | – | messages the driver approved |

### Example

```bash
curl -X POST http://localhost:8787/api/v1/agent/suggest \
  -H "content-type: application/json" \
  -d '{"deliveryId":"DLV-1042"}'
```

```jsonc
{
  "situation": { "type": "access_instructions", "label": "Access instructions given" },
  "confidence": 0.91,
  "recommendedAction": {
    "type": "follow_access_instructions",
    "label": "Follow the access instructions in the note",
    "reason": "Using the code avoids a failed attempt at a gated building."
  },
  "message": {
    "channel": "sms",
    "recipient": "Sanne",
    "body": "Hi Sanne, your driver is on the way to 18 Kanalstraat ... - ref DLV-1042.",
    "charCount": 153
  },
  "requiresApproval": true,
  "trace": [
    { "tool": "get_delivery", "label": "Reading delivery context", "ok": true, "ms": 1 },
    { "tool": "search_guidelines", "label": "Looking up company guidelines", "ok": true, "ms": 0 },
    { "tool": "draft_message", "label": "Drafting the customer message", "ok": true, "ms": 1 }
  ]
}
```

## How the agent works

`src/agent/orchestrator.js` runs a bounded tool loop:

```
system prompt + note
   └► model.complete(messages, tools)
         ├─ tool_use  → execute tool → append tool_result → loop (max MAX_AGENT_TURNS)
         └─ text      → parse JSON → validateSuggestion()
                           ├─ invalid → one repair round → re-validate
                           └─ still invalid → HTTP 502 (never a bad suggestion)
```

Tools (`src/agent/tools.js`):

| Tool | Effect |
| --- | --- |
| `get_delivery` | read delivery + customer context |
| `list_delivery_events` | read history / previous attempts |
| `search_guidelines` | keyword search over the company SOP set |
| `draft_message` | **validate only** — length, banned marketing words, number sequences |

Models (`src/agent/llm/`):

* `mock.js` – offline policy engine that speaks the same contract as the real
  model (emits tool calls, reads results, answers with JSON). Used for demos,
  CI and development without spending tokens.
* `anthropic.js` – Claude via the Messages API with native tool use, using the
  built-in `fetch` (no SDK dependency).

Switch by setting `LLM_PROVIDER=anthropic`; nothing else changes.

## Guardrails

* message length `40..320` chars, checked at draft time **and** on the final JSON
* no marketing words (`discount`, `promo`, `free`, …) in service messages
* no long number sequences (phone/bank) in a customer message
* channel must come from the customer's preference
* confidence, reasoning and trace are returned so the UI can be transparent
* the service never sends anything on its own — `/agent/messages` is called by
  the app only after the driver presses **Send**

## Plugging in your existing API

Set two variables and every delivery read/status write is proxied to your
backend with your bearer token:

```bash
EXISTING_API_BASE_URL=https://api.yourcompany.com/v1
EXISTING_API_KEY=...
```

Contract expected (adjust `src/data/gateway.js` if yours differs):

```
GET   /deliveries?driverId=...      -> { deliveries: [...] }
GET   /deliveries/:id               -> delivery
PATCH /deliveries/:id/status        { status, label } -> delivery
POST  /messages                     {...} -> { messageId, ... }
```

While `EXISTING_API_BASE_URL` is empty, the bundled demo dataset in
`src/data/deliveries.js` is used instead.

## Tests

`npm test` covers the note classifier, guideline search, guardrail validation,
JSON parsing, the tool executor, the full agent loop for four different note
situations, and the HTTP API (including the driver-approved send flow).
