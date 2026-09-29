# Delivery APP — driver app + AI delivery-note assistant

A complete, working implementation of the job brief:

> *“…help drivers deal with delivery notes and customer updates faster. The new
> flow should understand the note or situation, suggest the next action, and
> prepare a short message the driver can review and send.”*

Two deliverables, both runnable today:

| Folder | What it is | Stack |
| --- | --- | --- |
| `mobile/` | The driver app: route, stops, notes, and the AI assistant sheet | **Flutter / Dart**, Material 3, **Kotlin** + **Swift** native modules |
| `services/ai-agent/` | The lightweight AI agent service behind the feature | **Node.js** (Express), Claude (Anthropic) or offline mock model |
| `docs/` | Architecture and integration notes | — |

---

## The AI flow

```
 driver taps "AI assistant" on a stop
        │
        ▼
 POST /api/v1/agent/suggest  { deliveryId, note }
        │
        ├─► get_delivery            → customer, address, access hints, COD
        ├─► list_delivery_events    → past attempts at this address
        ├─► search_guidelines       → company SOP for this situation
        ├─► draft_message           → guardrail check (length, marketing, PII)
        │        └─ ✗ rejected → one repair round, then refuse
        ▼
 { situation, confidence, recommendedAction, message, trace }
        │
        ▼
 bottom sheet: suggested next action + editable draft
        │   driver reviews / edits
        ▼
 POST /api/v1/agent/messages   ← the only place a message is actually sent
```

The agent **proposes, never sends.** Sending is always an explicit driver
action, and the text is sent exactly as approved.

## Quick start

### 1. Agent service (Node 20+)

```bash
cd services/ai-agent
npm install
npm start                 # → http://localhost:8787
```

Out of the box it runs in **mock mode** (deterministic, no API key) against a
bundled demo route, so the whole product is demonstrable offline.

To use the real Claude model:

```bash
cp .env.example .env
# LLM_PROVIDER=anthropic
# ANTHROPIC_API_KEY=sk-ant-...
npm start
```

### 2. Driver app (Flutter 3.27+)

```bash
cd mobile
flutter pub get
flutter run
```

Sign in with any e-mail/password. If `android/` or `ios/` is ever missing,
regenerate it without touching your code:

```bash
flutter create --project-name delivery_driver --org com.example --platforms android,ios .
```

| Where the app runs | Backend URL to set (Profile → Connection) |
| --- | --- |
| iOS simulator / desktop | `http://localhost:8787` (default) |
| Android emulator | `http://10.0.2.2:8787` |
| Real device | `http://<your-lan-ip>:8787` |

## Try the feature in 60 seconds

1. Start the service, run the app, sign in.
2. Open **DLV-1042 – Sanne de Vries** (note: *“Gate code 4482, leave with the
   neighbour…”*).
3. Tap **AI assistant** → it reads the note, checks the SOP and returns:
   *Situation: access instructions* → *Next action: follow the access
   instructions* → a ready SMS draft you can edit.
4. Edit the draft, press **Send** → the message lands in the service outbox
   (`GET /api/v1/messages/outbox`).

Other notes to try: damaged parcel (DLV-1043), reschedule (DLV-1044), hard of
hearing (DLV-1045).

## Tests

```bash
cd services/ai-agent && npm test     # 20 tests  ✔
cd mobile && flutter analyze         # no issues  ✔
cd mobile && flutter test            # 18 tests   ✔
```

## Feature checklist → code

| Brief requirement | Where |
| --- | --- |
| Improve the existing driver app | `mobile/lib/screens/*`, `mobile/lib/state/*` |
| Understand the note / situation | `src/agent/heuristics.js` + agent tool loop |
| Suggest the next action | `recommendedAction` in `src/agent/orchestrator.js` |
| Prepare a short message to review & send | `assistant_sheet.dart` (editable draft, send button) |
| Existing API integration | `src/data/gateway.js`, `mobile/lib/services/api_client.dart` |
| Lightweight AI agent workflow | `src/agent/orchestrator.js`, `tools.js`, `llm/*` |
| Flutter / Dart | `mobile/` |
| Kotlin + Swift | `mobile/android/.../MainActivity.kt`, `mobile/ios/Runner/AppDelegate.swift` |
| Python/Node for AI integrations | Node.js agent service (runs on Node 20+) |

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the design decisions and
the production integration checklist.
