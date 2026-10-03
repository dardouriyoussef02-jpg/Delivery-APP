# Delivery‑Driver‑App – Full Overview (Markdown)

Below is a self‑contained Markdown document that sums up everything you asked for: the app’s architecture, data model, storage, languages, how data flows, and the recent cleanup we performed. You can copy‑paste this into a `.md` file (e.g., `APP_OVERVIEW.md`) or read it directly in the chat.

---## Delivery‑Driver‑App – Quick‑but‑complete overview  

| Layer | What it does | Main tech |
|------|--------------|-----------|
| **Mobile front‑end** | • Shows the driver a list of deliveries (stops) <br>• Lets the driver sign‑in, view a profile, see a map, open a detail screen for each stop <br>• Communicates with a remote API or falls back to bundled demo data when offline | **Flutter** (Dart) – a single‑code‑base that compiles to iOS, Android, Web, Desktop |
| **API / Backend service** | • Authenticates drivers (login / register) <br>• Serves the list of deliveries, their items, and statistics <br>• Provides a tiny “agent” endpoint that the AI‑assistant calls <br>• Persists tokens, driver profile, and statistics in a database | **Node.js** (Express) + **SQLite** (file‑based) for the demo; in production it would be a proper relational DB (PostgreSQL/MySQL) |
| **AI‑agent (chat‑assistant)** | • Receives a driver’s question, talks to an LLM (e.g. Claude, OpenAI) or a local “mock” model, then returns a suggestion (route, SKU, etc.) <br>• Its own tiny HTTP service (`services/ai-agent`) runs on `:8787` in the demo setup | **Node.js** (plain JavaScript/TypeScript) – the agent is a small Express server that forwards requests to an LLM provider |
| **Offline/demo data** | • A JSON file (`assets/demo/deliveries.json`) that the app loads when the backend cannot be reached <br>• Contains 4 sample deliveries (espresso machine, TV, chair, shoes) with names, categories, SKU, and image URLs (Wikimedia thumbnails) | Plain **JSON**; the Flutter side reads it as a normal Dart `Map` |
| **Local storage on the phone** | • **SharedPreferences** (key‑value) stores the driver’s e‑mail, the last‑used base‑URL (now a compile‑time constant), and a few booleans (auto‑suggest, channel) <br>• **Secure storage** (native secure‑enclave/keystore) holds the bearer token that the app attaches to every API call | Flutter plugins: `shared_preferences`, `secure_storage` (or `sqflite` for a real SQLite DB on the device) |
| **Routing / map** | • Shows a depot point and the stops on a map (OpenStreetMap tiles) <br>• Calculates simple routes for the driver | Flutter map package (OSM tile URLs are hard‑coded, no external map API key needed) |

---## 2. Data model – what the app actually stores / sends  

### 2.1. `Delivery` (the core object)

| Field | Type | Meaning |
|------|------|---------|
| `deliveryId` | string (e.g. `DLV‑1042`) | Unique identifier for the stop |
| `customerName` | string | Name the driver sees first |
| `item` | **`DeliveryItem`** (nullable) | – `name` – e.g. “Espresso machine” <br>– `imageUrl` – Wikimedia thumb URL (960 px) <br>– `category` – free‑text (e.g. “home‑appliance”) <br>– `sku` – stock‑keeping unit <br>– `hasImage` – bool, true when `imageUrl` is present |
| `status` | enum‑like string | “pending”, “in_transit”, “delivered” … |
| `lat / lng` | number | Coordinates of the stop (used on the map) |
| `timestamp` | DateTime | When the record was created / last updated |

> **Why `item` is nullable?** Older payloads from a real backend might not contain the new field, so the model tolerates `null`. The app still shows a placeholder parcel icon when there is no image.

### 2.2. `DeliveryItem` (the “photo + name” block)

```dart
class DeliveryItem {
  final String name;
  final String? imageUrl;   // nullable → may be missing
  final String category;
  final String sku;
  final bool hasImage;
}
```

* The `imageUrl` is **always an HTTP(S) URL** (Wikimedia thumbnail).  
* When the URL is missing or fails to load, the widget shows a grey “parcel” icon instead of crashing.

### 2.3. `Session` (driver sign‑in)

| Field | Source |
|------|--------|
| `driverId` | static demo value `DRV‑77` (real back‑end would assign it) |
| `driverName` / `driverEmail` | entered on sign‑in |
| `token` | JWT‑style bearer token, stored **securely** (not in SharedPreferences) |
| `baseUrl` | **compile‑time constant** (`AppConfig.defaultBaseUrl = 'http://localhost:8787'`). In the demo it can be overridden at build time; the UI no longer lets the driver change it. |
| `autoSuggest`, `channel`, etc. | miscellaneous preferences in `SharedPreferences` |

---## 3. Data flow – from sign‑in to a delivery card  

1. **Sign‑in**  
   * The driver types e‑mail/password → `POST /api/v1/auth/login` (Node backend).  
   * On success the backend returns a token → stored securely.  
   * The app now uses the **fixed** `baseUrl`; the old “enter your own URL” screen has been removed.

2. **Loading the route**  
   * `GET /api/v1/deliveries?driverId=DRV-77` (or the offline JSON).  
   * The response is a JSON array of `Delivery` objects, each possibly carrying an `item`.

3. **Displaying a stop card**  
   * The `ItemImage` widget loads `Image.network(item.imageUrl)` with a spinner while it fetches, and a parcel‑icon placeholder on error.  
   * The card also shows the item’s `name` and `category` beneath the picture.

4. **Opening the detail screen**  
   * A new “What you are delivering” card appears: 176 px photo, name, category, plus two pills: **parcel** and **SKU**.  
   * The SKU pill is just the `sku` field; the parcel pill is a static label.

5. **AI assistant (optional)**  
   * The driver can tap the “AI assistant” button.  
   * The request goes to `POST /api/v1/agent/suggest` → Node agent forwards it to an LLM (or a mock model).  
   * The answer is rendered as a short textual suggestion plus a “trace” of the steps it took.  
   * **Important:** The assistant’s provider name or data‑mode are **not shown** to the driver any more (they were removed for security).

6. **Offline fallback**  
   * If the network request fails (no internet, wrong base URL, timeout), the app loads `assets/demo/deliveries.json` instead.  
   * A banner at the top says “You are offline – showing your saved demo route.”

---## 4. Languages & ecosystems  

| Piece | Language(s) | Why that language? |
|------|-------------|-------------------|
| **Mobile UI** | **Dart** (Flutter framework) | One code base → iOS, Android, Web, Desktop. Fast UI rendering, reactive model. |
| **Backend API** | **Node.js** (JavaScript/TypeScript) | Very quick to prototype the small‑scale demo (auth, deliveries, agent endpoints). Express gives a minimal HTTP layer. |
| **AI agent** | **Node.js** (same process) | The agent is just a few routes that forward to an LLM SDK (e.g. `@anthropic-ai/sdk` or the OpenAI SDK). Running it in the same process as the API keeps the demo simple. |
| **Local storage** | **Dart** (via plugins) | `shared_preferences` (KV) and `secure_storage` are pure Dart, no native code needed for the demo. |
| **SQLite (demo DB)** | **Node.js** `better-sqlite3` (or `sqlite3`) | The agent service stores a tiny file‑based SQLite (`ai-agent/src/data/database.js`) to demo persistence without a full server DB. In production you’d replace this with PostgreSQL/MySQL. |
| **Demo data (JSON)** | **JSON** (language‑agnostic) | The app reads it as plain Dart `Map<String,dynamic>`; easy to edit without recompiling. |

> **Mot‑technique** note: the whole stack is “full‑stack JavaScript/TypeScript on the server, Dart on the client”. The only native bits are the Flutter engine and the secure‑storage plugins; they are abstracted away by the framework.

---## 5. Recent cleanup (what we just did)

| What we removed | Why |
|-----------------|-----|
| **“API settings” panel** on the sign‑in screen (URL field + “Test connection” button) | That URL is a **build‑time constant**, not something a driver should edit – it would let anyone point the app at a different backend, which is a security risk. |
| **Hint text** that mentioned `services/ai-agent/.env`, `npm start`, etc. | Those paths belong to the developer’s machine, not to the driver’s UI. |
| **Error messages** that exposed host, port, endpoint paths, or “Check the API URL in Settings” | Same security reason – the UI must never reveal internal networking details. |
| **Profile “Test connection”** now returns only generic “Connected / cannot reach” messages | Still useful for the driver, but no backend model/provider names leak. |
| **Doc updates** (`README.md`, `ARCHITECTURE.md`) | Keep the written documentation consistent with the new “build‑time URL” approach. |

All of those changes were **purely UI / wording** – the underlying data model, database schema, and API contracts stayed exactly the same.

---## 6. Quick cheat‑sheet of the most important files (paths relative to the repo root)

| Path | Role |
|------|------|
| `mobile/lib/main.dart` | Entry point – boots the `DeliveryApp` widget. |
| `mobile/lib/screens/login_screen.dart` | Sign‑in UI (now stripped of API‑settings). |
| `mobile/lib/screens/route_screen.dart` / `delivery_detail_screen.dart` | Lists stops & shows the “what you are delivering” card. |
| `mobile/lib/widgets/item_image.dart` | Reusable picture widget with spinner/placeholder. |
| `mobile/lib/models/delivery.dart` | Dart classes `Delivery` + `DeliveryItem`. |
| `mobile/lib/services/api_client.dart` | Tiny HTTP wrapper; now generic error texts. |
| `mobile/lib/state/session_controller.dart` | Holds driver session, the fixed `baseUrl`, and the generic `testConnection`. |
| `services/ai-agent/src/server.js` | Node Express server (ports 8787 + 8686). |
| `services/ai-agent/src/data/deliveries.js` | In‑memory demo dataset (the 4 items with image URLs). |
| `services/ai-agent/src/data/schema.js` / `database.js` | SQLite schema v2, migration, seeding of demo items. |
| `mobile/assets/demo/deliveries.json` | Offline fallback JSON (same shape as the API returns). |
| `mobile/test/signup_flow_test.dart` | Widget test that now asserts no “API settings” text appears. |

---## 7. How you could extend / hack  

| Idea | What you’d touch |
|------|------------------|
| **Add a real backend** (PostgreSQL, user accounts) | Replace the `sqlite_store.js` + `database.js` with a proper DB, adjust the Express routes, keep the same `Delivery` JSON shape. |
| **Swap the LLM provider** (e.g. GPT‑4 instead of Claude) | Edit `services/ai-agent` routes and the SDK call; the Flutter side stays unchanged. |
| **Add more item fields** (e.g., weight, dimensions) | Extend `DeliveryItem` in `mobile/lib/models/delivery.dart`, update the JSON demo, and add UI widgets as needed. |
| **Change the offline banner text** | Edit the few strings in `mobile/lib/screens/deliveries_screen.dart` and `mobile/lib/screens/notifications_screen.dart`. |

--- 

You can save the whole block above into a file named `APP_OVERVIEW.md` (or any name you prefer). If you need the file created on disk, just let me know and I’ll write it for you.