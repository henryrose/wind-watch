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
4. Three Apple targets link it: iOS app, watchOS app, watchOS widget extension (complications).
5. Watch app and widget share an App Group cache; the widget's timeline is built from one fetch,
   one entry per hour, so complications roll forward with no network.
6. Stale data is always labelled (fresh < 90 min, stale < 6 h, old beyond). Chart ends at the
   HRRR horizon; nothing is padded.
7. `web/` is a static page consuming the same payload.
8. Signing, bundle prefix, API base come from xcconfig; nothing machine-specific is committed.
9. Accounts (Apple Developer, Cloudflare) live on a different Mac; see
   `docs/HANDOFF-OTHER-MACHINE.md` (written at the end of the build).
10. Build state and decisions: `progress.md`.

## Documents

- `InitialPrompt.md` — the brief.
- `docs/DESIGN.md` — architecture, API contract, refresh model, costs, staged plan.
- `docs/WINDWATCH-DESIGN-HANDOFF.md` — UI contract (tokens, chart spec, per-surface layouts).
  Wins over the design canvas.
- `docs/IMPLEMENTATION_PLAN.md` — multi-agent task breakdown. §0 reconciles the two docs above.
- `docs/LOOP_PROMPT.md` — orchestrator prompt.

## Commands

(Filled in as tasks land.)

```
# Server
export PATH="$HOME/.nvm/versions/node/v24.13.0/bin:$PATH"   # this machine only
cd server && pnpm install && pnpm test

# Swift package
cd apple/WindCore && swift test

# Apple apps (after D1)
# see apple/build.sh
```

## Rules

- Use `pnpm`, not `npm`. Node 24.
- Integers in knots. Arrows rotate `dirFrom + 180`. Never hardcode team ids, bundle prefixes,
  KV ids, or API URLs.
- Never commit `apple/Config/Local.xcconfig`.
