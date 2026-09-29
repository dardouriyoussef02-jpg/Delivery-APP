# Architecture

## System overview

```
┌────────────────────────── mobile/ (Flutter) ──────────────────────────┐
│  Login ─ Home shell ─ Deliveries ─ Route ─ Profile                    │
│                                │                                      │
│                     Delivery detail screen                           │
│                                │  "AI assistant"                      │
│                     AssistantController (state)                       │
│                        │                    │                         │
│              DeliveryRepository        AiAgentService                 │
│                        └───────────┬──────────┘                       │
│                              ApiClient (http)                         │
└────────────────────────────────────┼──────────────────────────────────┘
                                     │  base URL (build config)
                       ┌─────────────▼──────────────┐
                       │  services/ai-agent (Node)   │
                       │                             │
                       │  express routes             │
                       │   ├── /api/v1/deliveries ───┼──► existing API (optional)
                       │   ├── /api/v1/agent/suggest │        │
                       │   └── /api/v1/agent/messages│        │
                       │            │                │        │
                       │      agent orchestrator     │        │
                       │        ├── tools            │        │
                       │        ├── guidelines (SOP) │        │
                       │        └── model adapter ───┼──► Claude API (optional)
                       └─────────────────────────────┘
```

## Why a separate agent service

* **Keeps secrets off the device.** The Anthropic key, prompt and guardrails
  live on the server; the app only ever sees a validated suggestion.
* **One place to swap models.** `src/agent/llm/` has two implementations of the
  same contract (`mock`, `anthropic`) — the rest of the system is identical.
* **Reuse.** The same endpoints can later power a dispatcher web console.
* **Cheap for the client.** Node runs anywhere their API runs, no extra infra.

## The agent loop

`src/agent/orchestrator.js`

1. Build the user message: the note plus the driver-selected delivery, and a
   rule-based first read (confirm-or-overrule hint).
2. `model.complete()` with four tool schemas.
3. While the model asks for tools: execute them, append results, repeat —
   capped at `MAX_AGENT_TURNS` (default 6) so a misbehaving model cannot spin.
4. Model answers with JSON → `validateSuggestion()`.
5. If validation fails: **one** repair round with the exact error list.
   A second failure returns HTTP 502 instead of a sloppy suggestion.
6. Response carries a `trace` (tool, label, ok, ms, detail) so the app can show
   *how* the answer was reached.

Reads are side-effect free; `draft_message` only validates; **the only
write is `POST /agent/messages`, invoked by the app after the driver taps
Send.**

## Data contracts

Everything the app consumes is JSON produced by the service and mirrored by
Dart models:

* `Delivery` (`mobile/lib/models/delivery.dart`) — id, status, window, ETA,
  address (with `accessHint`), customer (first name, phone, preferred channel,
  language), notes, events, history.
* `AiSuggestion` (`mobile/lib/models/ai_suggestion.dart`) — `situation`,
  `confidence`, `reasoning`, `recommendedAction`, `message`, `requiresApproval`,
  `trace`, `latencyMs`.

The demo dataset exists twice on purpose: `src/data/deliveries.js` (service) and
`assets/demo/deliveries.json` (app fallback). Both follow the same shape, and
both are replaced by the real API in production.

## Guardrails

| Layer | Rule |
| --- | --- |
| Tool | `draft_message`: 40–320 chars, no marketing words, no long number sequences |
| Output | `validateSuggestion()` re-checks types, enums, confidence, length, banned words |
| Recovery | one repair round, then refuse (502) |
| Human | driver edits freely; send is explicit; `requiresApproval: true` always |
| Transport | optional `X-Driver-Token`, bearer token to the upstream API, request body capped at 64 KB |

## Offline & demo strategy

* App: if the API is unreachable, deliveries load from the bundled asset and an
  “offline demo” banner appears. AI actions show a clear, actionable error.
* Service: `LLM_PROVIDER=mock` gives identical behaviour without network or
  cost — used by the 20 backend tests.

## Integrating with the client's existing API

1. Set `EXISTING_API_BASE_URL` + `EXISTING_API_KEY` (see
   `src/data/gateway.js`).
2. Align field names — the expected shape is documented in
   `services/ai-agent/README.md`; only that file needs changing.
3. Replace `search_guidelines` data with a real SOP endpoint (same signature).
4. Point the app at the real API for auth (replace the demo
   `SessionController.signIn`, ~20 lines).

## Security / privacy notes

* Customer name + order reference only in messages; no other customer data.
* Access codes are never repeated back in a message — only “I will use the
  instructions from your note”.
* Production checklist: HTTPS everywhere, real driver auth (JWT/OAuth),
  rate limiting on `/agent/suggest`, log redaction (note text is personal data),
  retention policy for the outbox, and `NSAllowsLocalNetworking` removed from
  `Info.plist` / `usesCleartextTraffic` removed from the manifest.

## Suggested next steps

1. **Streaming** — stream the trace to the app so steps appear live.
2. **Evaluation set** — 30 real notes with expected situation/action as a CI
   regression suite for prompt changes.
3. **Multilingual** — the customer's `language` field is already passed to the
   model; add a locale rule to the prompt.
4. **Cost/latency** — `claude-haiku` for classification, Sonnet only for
   ambiguous notes (route by confidence).
5. **Dispatcher console** — same endpoints, different UI.
