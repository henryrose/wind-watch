# Wind Watch — web

One static page: `index.html`, `styles.css`, `app.js`, `config.js`, and two pure
modules, `lib/derive.js` (payload → view model, all derivations) and
`lib/cache.js` (the live-mode cache record). No build step, no dependencies,
no CDN.

## Modes

`config.js` is the only place an API URL lives:

```js
window.WW_CONFIG = { apiBase: "" };
```

| `apiBase` | Mode | Data |
|---|---|---|
| `""` (committed default) | **Fixture** | `../fixtures/payload-reference.json`, relative to the page. Clock pinned to `start + 30 min` so the reference reads as fresh. |
| `"https://wind-watch.<account>.workers.dev"` | **Live** | `GET <apiBase>/v1/wind` with `If-None-Match`; last payload cached in `localStorage` (`ww.payload.v1`); live clock. |

## Run locally (fixture mode)

Serve the **repo root** so the fixture path resolves:

```sh
cd <repo root>
python3 -m http.server 8080
open http://localhost:8080/web/
```

Opening `index.html` from the filesystem does not work: `app.js` is an ES module
and the payload is fetched, both of which browsers block on `file://`.

## Live mode

Set `apiBase` to the deployed Worker origin (no trailing slash needed) and serve
the page from anywhere; it only needs `index.html`, `styles.css`, `app.js`,
`config.js` and `lib/`. What the page does:

1. **First paint from cache.** If `localStorage` holds a previous payload it is
   rendered immediately with the `updating` trust line (14 px ring,
   `updating · as of HH:MM`). Numbers are never covered by a spinner.
2. **Conditional check.** `fetch(<apiBase>/v1/wind, { cache: "no-store" })`
   with `If-None-Match: <cached etag>`. `200` → new body + ETag stored,
   `savedAt = now`. `304` → body kept, `lastChecked` updated. Network error or
   5xx → cached body kept with `lastCheckOK = false`.
3. **Trust states** (HANDOFF §3) from the live clock, re-rendered every minute
   so the 90-min and 6-h flips happen without a reload:
   - `as of HH:MM PDT · HRRR 17Z · forecast ends Fri 5am` (`… · ends Fri 5am`
     under 600 px) — fresh (< 90 min since the server
     last got new model data), or amber when stale (< 6 h) / old (≥ 6 h, with
     the day name; numbers and chart desaturate).
   - `Couldn't reach server · showing data from HH:MM` (amber, wifi-slash) —
     the last check failed but a cached payload exists. Age rules still apply.
   - `No forecast · last run HRRR 17Z Wed` — the clock is past the last
     forecast hour; hero shows `—`.
   - `No data yet. Needs cellular or Wi-Fi once.` + `trying…` — nothing cached
     and the check failed (first run). A `503 {"error":"no_data"}` from a
     Worker that has not baked yet shows `No data yet. The server has not baked
     a forecast yet.`
4. **Re-check** every 10 minutes while the tab is visible, and on
   `visibilitychange` when the last check is older than 10 minutes.

### Local test recipe (against the Worker in `server/`)

```sh
export PATH="$HOME/.nvm/versions/node/v24.13.0/bin:$PATH"   # this machine

# 1. Worker on :8787, baked once
cd server && pnpm wrangler dev --test-scheduled --port 8787 &
curl "http://localhost:8787/__scheduled?cron=*/10+*+*+*+*"
curl -i localhost:8787/v1/wind            # 200 + ETag

# 2. Page on :8080 with a TEMPORARY config.js
#    window.WW_CONFIG = { apiBase: "http://localhost:8787" };
cd <repo root> && python3 -m http.server 8080 &
open http://localhost:8080/web/           # trust line: as of HH:MM PDT · HRRR NNZ · forecast ends …

# 3. Offline with cache: stop the Worker, reload the page
pkill -f "wrangler dev"                   # → amber "Couldn't reach server · showing data from HH:MM"

# 4. Restore config.js to apiBase: "" before committing.
```

Headless Chrome does not persist `localStorage` between launches unless you
pass `--user-data-dir=<dir>`; use the same dir for the live and the offline
screenshot.

## Verification query strings

Work in both modes (in live mode they are debugging aids only):

| Param | Values | Effect |
|---|---|---|
| `state` | `fresh` `stale` `old` `offline` `horizon` `firstrun` `updating` | Forces a HANDOFF §3 trust state. Each also picks a default `now` (stale = fetched + 2 h, old = fetched + 7 h, horizon = past the last hour) unless `now` is given. `firstrun` ignores the cache. |
| `now` | ISO 8601, e.g. `2026-10-22T06:30:00Z`, or `live` | Pins the clock (`live` = real clock, also in fixture mode). |
| `scheme` | `dark` `light` | Forces a colour scheme instead of `prefers-color-scheme` (headless screenshots). |
| `hover` | slot index, e.g. `15` | Applies the chart hover state (highlight + tooltip) for that slot on render, for screenshots. In 48 h a slot is an hour; in 7 d the HRRR slots come first (hourly on desktop, 3-hourly under the slot rule), then one per NBM block. |
| `fixture` | `1` | Fixture mode (the reference payload) even when `config.js` names a live API base. |
| `range` | `48h` `7d` | Presets the chart range control (not saved). |
| `unit` | `f` `c` | Presets the °F / °C footer control (not saved). |
| `table` | `1` `0` | Opens / closes the hourly table (not saved). |
| `nbm` | `stale` `old` `off` | Reshapes the payload: NBM fetched 2 h / 7 h before HRRR, or `extended: null` (7 d then stops at the HRRR edge with `NBM unavailable`). |
| `sky` | `off` | Drops `temp`/`cloud`/`precip` (no sky band, no temperature), as the server served before §4.2a. |

Examples:

```
http://localhost:8080/web/?state=fresh
http://localhost:8080/web/?state=old&scheme=light
http://localhost:8080/web/?state=offline&now=2026-10-22T06:30:00Z
http://localhost:8080/web/?state=horizon
```

## 26 Oct handoff (spec §12a/§12b, `docs/design/handoff-2026-10-26/`)

- **Range control** `48 h | 7 d` in the chart head (`localStorage` `ww.range`, default 48 h). 7 d draws HRRR to its
  horizon, then the NBM blocks from `extended`: seam labels `HRRR` / `NBM · 3-hourly`, NBM region tint, NBM bars 70 %,
  NBM gust line dashed 4/3 at 60 %, day names on the bottom axis, midnight dividers, `ends Tue 9am`. Under 4 px per
  hour (the phone breakpoint) the whole chart goes 3-hourly. Tooltip `Sat 12–3pm · NBM`, peak chip
  `peak G32 · Sat 1pm · NBM`, table rows `Fri 06–09 NBM` under `NBM from Fri 6am · 3-hourly`, trust line
  `… HRRR 15Z + NBM 13Z · forecast ends Tue 9am` with the NBM run amber on its own when NBM is stale (its chart region
  desaturates). `extended` null/missing → 7 d stops at the HRRR edge, `NBM unavailable`.
- **Sun days.** The payload's `sun` covers the HRRR days; for 7 d the missing days are computed in
  `lib/sun.js`, a port of `server/src/sun.ts` (keep the two in step).
- **Sky band** 14 px above the chart (3-h cells, cloud tones, 1–3 rain ticks), whenever the payload has `cloud`.
- **Temperature** only in the tooltip (`Thu 12am · midnight · Overcast · rain · 46°F`) and a table column after
  Beaufort (hidden under 360 px); footer `°F | °C` control (`localStorage` `tempUnit`, default °F), shown only when the
  payload has `temp`.
- **Sun markers**: sunrise filled r 3, sunset ring r 2.25 stroke 1.5. **Item 3**: the first day label is hidden when
  `now` is in the first hour; a tick label that would be clipped by the plot edge is dropped.

## Tests

```sh
export PATH="$HOME/.nvm/versions/node/v24.13.0/bin:$PATH"   # this machine
cd web && node --test
```

`test/derive.test.js` checks the HANDOFF §10 expected values, the §6.2 twilight
fractions, trust-state transitions, labels, and that `styles.css` carries the
exact §4.1 ramp hexes. `test/chart.test.js` checks the chart port
(`derive.chartLayout`, the JS twin of `docs/design/reference/chart_reference.py`)
against the numbers in `docs/design/reference/charts/webhover.svg` and
`webphone48.svg`: bars, gust polyline and caps, arrows, ticks, 12-hour labels,
day band, sun dots, now and edge rules, gradient stops, hour selection.
`test/range.test.js` covers the 26 Oct handoff: `extended` parsing and its absence, range spans, the slot rule,
HRRR 3-h aggregation, the 7-day layout (seam, NBM bars/gust split, arrows, bottom day names, hit-testing), sun
markers every day, block labels, the range peak chip, sky tones/rain ticks/cells, temperature formatting, table rows
and captions, and the two-model trust line.
`test/cache.test.js` checks the live-mode cache record (200 / 304 / error
folding, serialize/parse).
