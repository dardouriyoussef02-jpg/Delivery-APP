# Stitch design assets

Pulled from Google Stitch project **"Delivery Driver App Interface"**
(`projects/18183481777792757198`, visibility `PRIVATE`) via the Stitch MCP API
(`https://stitch.googleapis.com/mcp`) on 2026-10-03.

## Files

| File | Screen ID | Size | Notes |
|---|---|---|---|
| `shift-queue-dashboard.png` | `106865b03e2747699429431860839cb4` | 780 × 3132 | Full-screen render of the main dashboard |
| `shift-queue-dashboard.html` | *" | — | Generated HTML + Tailwind (source of truth for markup) |
| `shiftflow-logo.png` | `2ac37ea8739f4870ae3d4089fc15b23d` | 512 × 512 | Logo raster |
| `shiftflow-logo.svg` | *" | — | Logo vector (`image/svg+xml`) |
| `driver-avatar.jpg` | `5cca008f61dd499fac8cd82603091e6d` | 1024 × 1024 | Courier avatar (served as JPEG despite `screenshot` role) |
| `project.json` | — | — | Full project: theme, `namedColors`, embedded `DESIGN.md` |
| `screens.json` | — | — | Screen list with download URLs |

## Design system — "ShiftFlow Courier UI"

Dark, `ROUND_EIGHT` roundness, **Inter** throughout.

| Token | Hex | Token | Hex |
|---|---|---|---|
| `primary` | `#4edea3` | `secondary` | `#7bd0ff` |
| `primary-container` | `#10b981` | `secondary-container` | `#00a6e0` |
| `on-primary` | `#003824` | `on-secondary` | `#00354a` |
| `tertiary` | `#ffb95f` | `tertiary-container` | `#e29100` |
| `background` / `surface` | `#0f141b` | `surface-container-low` | `#171c23` |
| `surface-container` | `#1b2027` | `surface-container-high` | `#252a32` |
| `surface-container-highest` | `#30353d` | `surface-container-lowest` | `#090f15` |
| `on-surface` | `#dee2ec` | `on-surface-variant` | `#bbcabf` |
| `outline` | `#86948a` | `outline-variant` | `#3c4a42` |
| `error` | `#ffb4ab` | `error-container` | `#93000a` |

### Type scale (px / line-height / tracking / weight)

| Token | Size | LH | LS | W |
|---|---|---|---|---|
| `display-metric` | 36 | 44 | -0.03em | 700 |
| `headline-lg` | 28 | 36 | -0.02em | 700 |
| `headline-md` | 22 | 28 | -0.01em | 600 |
| `headline-sm` | 18 | 24 | 0 | 600 |
| `body-lg` | 16 | 24 | 0 | 500 |
| `body-md` | 14 | 20 | 0 | 400 |
| `body-sm` | 12 | 16 | 0.01em | 400 |
| `label-lg` | 14 | 18 | 0.02em | 600 |
| `label-md` | 12 | 16 | 0.04em | 600 |
| `label-badge` | 11 | 14 | 0.06em | 700 |

### Spacing

`space-xs` 4 · `space-sm` 8 · `space-md` 16 · `space-lg` 24 · `space-xl` 32 · `gutter` 16

## Screen structure

1. **Fixed header** (h-80) — logo, `SHIFTFLOW • DELIVERY QUEUE`, pulsing `ON DUTY` + elapsed timer, GPS/battery pill, avatar with presence dot
2. **Shift performance banner** — `ACTIVE SHIFT` pill, `Peak Boost +$2.50`, progress bar `3h 42m / 6h` (62%), 3-column bento: Earnings / Drop-offs / Vehicle
3. **Current stop hero card** — left gradient ribbon, stop #, countdown pill, recipient + address, package pill bar, amber customer-note box, primary `Start Turn-by-Turn` (h-56) + Call / Scan ID / Arrived split
4. **Delivery queue** — `Optimize` button, filter chips (All / Priority / Standard), cards with coloured left accent bars
5. **Cockpit utilities** — Dispatch / Take 15m / Report Gate
6. **Bottom nav** (h-80) — Queue · HUD · Earnings · Support
