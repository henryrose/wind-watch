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
   - `as of HH:MM · HRRR 17Z · ends Fri 05:00` — fresh (< 90 min since the server
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
open http://localhost:8080/web/           # trust line: as of HH:MM · HRRR NNZ · ends …

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

Examples:

```
http://localhost:8080/web/?state=fresh
http://localhost:8080/web/?state=old&scheme=light
http://localhost:8080/web/?state=offline&now=2026-10-22T06:30:00Z
http://localhost:8080/web/?state=horizon
```

## Tests

```sh
export PATH="$HOME/.nvm/versions/node/v24.13.0/bin:$PATH"   # this machine
cd web && node --test
```

`test/derive.test.js` checks the HANDOFF §10 expected values, the §6.2 twilight
fractions, trust-state transitions, labels, and that `styles.css` carries the
exact §4.1 ramp hexes. `test/cache.test.js` checks the live-mode cache record
(200 / 304 / error folding, serialize/parse).
