# Wind Watch

Personal iPhone + Apple Watch app (plus a one-page web version) showing the hourly HRRR wind
forecast for Port Townsend Bay, WA. One user. Watch complications are the primary surface.

## Architecture in ten lines

1. A Cloudflare Worker (`server/`) runs a cron every 10 min, pulls HRRR from Open-Meteo
   (`cell_selection=sea`), bakes one ~1 KB JSON payload into KV, and serves it at `GET /v1/wind`
   with an ETag. `?lat&lon` serves a custom location on demand.
2. Clients never call Open-Meteo. The payload is the only contract: `docs/DESIGN.md` §4.2.
3. `apple/WindCore` (Swift package) decodes the payload into a `Forecast` view model and holds
   all derivations: Beaufort, compass, trust state, twilight stops, timeline entries, the chart.
   The chart is one Canvas drawing (`WindChart`) over a pure `ChartGeometry` that ports
   `docs/design/reference/chart_reference.py`; the watch strip, phone, landscape and the
   complication mini strip are the same view with different `ChartStyle`s.
4. Three Apple targets link it: iOS app, watchOS app, watchOS widget extension (complications).
5. Watch app and widget share an App Group cache; the widget's timeline is built from one fetch,
   one entry per hour, so complications roll forward with no network.
6. Stale data is always labelled (fresh < 90 min, stale < 6 h, old beyond). Chart ends at the
   HRRR horizon; nothing is padded.
7. `web/` is a static page consuming the same payload.
8. Signing, bundle prefix, API base come from xcconfig; nothing machine-specific is committed.
9. Accounts (Apple Developer, Cloudflare) live on a different Mac; see
   `docs/HANDOFF-OTHER-MACHINE.md` for deploy, signing, device tests and TestFlight.
10. Build state and decisions: `progress.md`.

## Documents

- `InitialPrompt.md` — the brief.
- `docs/DESIGN.md` — architecture, API contract, refresh model, costs, staged plan.
- `docs/design/` — the UI design package. Read `README.md` first, then `DESIGN-HANDOFF.md`
  (the contract: tokens, chart spec, scrub, per-surface layouts, acceptance checklist; wins over
  the renders), `reference/renders/*.png`, `reference/artboards/*.dc.html` (exact values),
  `reference/chart_reference.py` (chart maths). §6.4d (round two) supersedes anything above it.
- `docs/IMPLEMENTATION_PLAN.md` — multi-agent task breakdown. §0 reconciles the two docs above.
- `docs/LOOP_PROMPT.md` — orchestrator prompt.

## Commands

```sh
# Server (Cloudflare Worker, TypeScript)
export PATH="$HOME/.nvm/versions/node/v24.13.0/bin:$PATH"   # authoring Mac only; use nvm/your node 24 elsewhere
cd server && pnpm install && pnpm test && pnpm typecheck
pnpm dev --test-scheduled --port 8787                        # local Worker (no `--` before the flag)
curl -s "http://localhost:8787/__scheduled?cron=*/10+*+*+*+*" # bake into local KV (hits Open-Meteo once)
curl -i localhost:8787/v1/wind                                # 200 + ETag; repeat with If-None-Match → 304
pnpm deploy | pnpm tail | pnpm kv:get default:etag            # deploy Mac only (see server/README.md)

# Swift package (pure logic + shared SwiftUI; tests run on macOS)
cd apple/WindCore && swift test

# Apple apps (XcodeGen project; simulator builds need no signing)
cd apple && ./build.sh gen      # regenerate WindWatch.xcodeproj from project.yml after changing targets/files
./build.sh ios                  # WindWatch scheme → iPhone 18 Pro simulator (compiles all three targets)
./build.sh watch                # WindWatchWatch scheme → Apple Watch Series 12 (46mm) simulator
./build.sh all                  # gen + swift test + ios + watch
# Run with fixture data: launch with env WW_FIXTURE=1 (+ WW_STATE=stale|old|offline|horizon|firstrun|updating,
# WW_NOW=<ISO8601>, WW_TYPE_SIZE=ax3, WW_SCREEN=location|about, WW_SCRUB=<hour index>, WW_LANDSCAPE=1,
# WW_TABLE=1|0 (hourly table open/closed), WW_CANDIDATE="Name,lat,lon" (unsaved point on the Location screen) on iPhone; WW_PAGE=strip|now|settings|complications on watch, strip is the default). Wait ~7 s before a screenshot (first frame compiles a gradient).
# Always address simulators by UDID when two are booted (`xcrun simctl list devices`).

# Web (static page, no build step)
cd web && node --test
python3 -m http.server 8080     # from the repo root, then open http://localhost:8080/web/?state=fresh
```

## Layout

- `server/` — Worker: `src/transform.ts` (Open-Meteo → payload), `sun.ts`, `summary.ts`, `index.ts` (fetch + scheduled), tests in `test/`.
- `apple/WindCore/` — Swift package: `Payload`, `Forecast`, `Beaufort`, `Compass`, `Trust`, `Twilight`, `TimelineBuilder`, `WindClient`, `AppGroupStore`, `ForecastSession`, `SavedLocation`, and `UI/` (tokens, glyphs, `ChartStyle`, `ChartGeometry`, `ChartModel`, `WindChart`, `MiniStrip`, `TrustLineView`). `Tests/…/ChartReferenceTests` checks the geometry against the reference SVGs.
- `apple/WindWatch/` iOS app · `apple/WindWatchWatch/` watchOS app · `apple/WindWatchComplications/` widget extension · `apple/Shared/` views compiled into more than one target.
- `apple/Config/Shared.xcconfig` (tracked) + `Local.xcconfig` (untracked: team id, bundle prefix).
- `web/` — `index.html`, `app.js`, `lib/derive.js` (pure derivations), `config.js` (API base).
- `fixtures/` — captured Open-Meteo responses and `payload-reference.json` (shared by all tests and previews).
- `docs/` — `DESIGN.md`, `design/` (UI package), implementation plan, screenshots (`d7-*` and `web-d7-*` are the round-two design set; `d6-*` the first pass), `HANDOFF-OTHER-MACHINE.md`.

## Rules

- Use `pnpm`, not `npm`. Node 24.
- Integers in knots. Arrows rotate `dirFrom + 180`. Never hardcode team ids, bundle prefixes,
  KV ids, or API URLs.
- Never commit `apple/Config/Local.xcconfig`.
