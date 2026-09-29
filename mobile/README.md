# Delivery Driver — Flutter app

The driver-facing app: today's route, stop details, delivery notes, and the AI
assistant that turns a note into a suggested next action plus a message the
driver reviews and sends.

* **UI:** Material 3, single codebase for **iOS and Android**
* **State:** `provider` + `ChangeNotifier` (`lib/state/`)
* **Backend:** one `ApiClient` (`lib/services/api_client.dart`)
* **Native:** Kotlin (`MainActivity.kt`) and Swift (`AppDelegate.swift`) modules
  exposed over the `delivery.driver/native` method channel

## Run

```bash
flutter pub get
flutter run
```

Sign in with any e-mail/password (demo build).

If the `android/` or `ios/` folder is missing (e.g. after a fresh checkout of
only `lib/`), regenerate it — existing files such as `main.dart`,
`MainActivity.kt` and `AppDelegate.swift` are **not** overwritten:

```bash
flutter create --project-name delivery_driver --org com.example --platforms android,ios,web .
```

### Backend URL

Profile → **Connection → Backend base URL** (persisted with
`shared_preferences`):

| Runner | URL |
| --- | --- |
| iOS simulator / desktop / web | `http://localhost:8787` (default) |
| Android emulator | `http://10.0.2.2:8787` |
| Physical device | `http://<computer-lan-ip>:8787` |

If the backend cannot be reached, the delivery list falls back to the bundled
`assets/demo/deliveries.json` and shows an “offline demo” banner, so a demo
never ends on a blank screen. The AI assistant still needs the service running.

## Structure

```
lib/
├── main.dart                 # entry point
├── app.dart                  # providers + splash/login/shell switching
├── core/
│   ├── app_theme.dart        # Material 3 theme + icon/colour vocabulary
│   └── formatters.dart       # time, ETA, distance, money, previews
├── models/
│   ├── delivery.dart         # Delivery, Customer, Note, Event, statuses
│   └── ai_suggestion.dart    # situation, action, draft, trace
├── services/
│   ├── api_client.dart       # HTTP wrapper, timeouts, ApiException
│   ├── delivery_repository.dart  # deliveries + offline demo fallback
│   ├── ai_agent_service.dart # /agent/suggest + /agent/messages
│   ├── contact_actions.dart  # call, SMS, WhatsApp, navigation
│   └── native_platform.dart  # method channel wrapper (graceful fallback)
├── state/
│   ├── session_controller.dart      # auth, base URL, preferences
│   ├── deliveries_controller.dart   # load, filter, search, status updates
│   └── assistant_controller.dart    # analyse → review → send
├── screens/
│   ├── login_screen.dart
│   ├── home_shell.dart        # bottom navigation
│   ├── deliveries_screen.dart # list, search, filters, refresh
│   ├── delivery_detail_screen.dart
│   ├── assistant_sheet.dart   # ★ the AI feature
│   ├── route_screen.dart      # ordered stops + progress
│   └── profile_screen.dart    # settings, connection test, sign out
└── widgets/
    ├── delivery_card.dart
    ├── status_chip.dart
    └── section_card.dart
```

## The assistant sheet

| Phase | What the driver sees |
| --- | --- |
| `idle` | note selector, editable note field, channel chips, “Analyse note” |
| `thinking` | the four steps the agent is running |
| `ready` | situation + confidence, **suggested next action**, editable message, char counter, `Regenerate` / `Share` / **Send**, collapsible trace |
| `sending` | in-flight state |
| `sent` | confirmation |
| `failure` | readable error + retry |

The draft is editable at all times, is limited to 320 characters with a live
counter, and **nothing is sent until the driver presses Send** (which calls
`POST /api/v1/agent/messages`).

Set *Profile → Analyse automatically* off to open the sheet without firing a
request.

## Native modules

| | Android (Kotlin) | iOS (Swift) |
| --- | --- | --- |
| `ping` | ✅ | ✅ |
| `openNavigation` | `google.navigation:` intent → Maps URL fallback | `MKMapItem.openInMaps` (driving mode) |
| `shareText` | `ACTION_SEND` chooser | `UIActivityViewController` |

Dart calls `NativePlatform` first and silently falls back to `url_launcher`
(`tel:`, `sms:`, `wa.me`, Google Maps directions) when the channel is missing —
which is also what happens in widget tests.

## Tests

```bash
flutter analyze     # no issues
flutter test        # 18 tests
```

* `test/models_test.dart` – parsing of deliveries and agent responses, format helpers
* `test/assistant_flow_test.dart` – the full analyse → edit → approve → send flow,
  including guardrail rejection and backend failures (stubbed agent)
* `test/widget_test.dart` – boot, sign-in validation, driver shell
