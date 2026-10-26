# Wind Watch server

A Cloudflare Worker that pulls the HRRR wind forecast for Port Townsend Bay from Open-Meteo
every 10 minutes, adds NBM in 3-hour blocks from the HRRR horizon out to 7 days, bakes it into
one ~2.4 KB (~1 KB gzipped) JSON payload in Workers KV, and serves it at `GET /v1/wind` with an ETag. Custom locations (`?lat&lon`) are baked on demand and cached for
10 minutes. The watch, phone and web clients only ever talk to this Worker, never to Open-Meteo.

The payload is the only contract: `docs/DESIGN.md` §4 (endpoint, response shape, headers, cron),
with the 26 Oct additions (`temp`, `cloud`, `precip`, `extended`) in §4.2a.

## Prerequisites

- Node 24. On the authoring Mac it lives at `~/.nvm/versions/node/v24.13.0/bin`; on the deploy
  Mac use `nvm use 24` or any Node ≥ 22.
- `pnpm` (ships with Node via `corepack enable`).
- A Cloudflare account on the **Free** plan. No custom domain is needed; the Worker runs on
  `workers.dev`.
- `server/.npmrc` pins `registry=https://registry.npmjs.org/` on purpose: a user-level `~/.npmrc`
  that points at a private feed must not affect this project. Leave it in place.

## One-time setup on the deploy Mac

Run everything from `server/`.

```sh
pnpm install
pnpm wrangler login          # opens a browser; grants wrangler access to the account
pnpm wrangler whoami         # sanity check: shows the account name
```

Create the KV namespace and paste its id into `wrangler.toml`:

```sh
pnpm wrangler kv namespace create WIND
# prints something like:
#   [[kv_namespaces]]
#   binding = "WIND"
#   id = "0123456789abcdef0123456789abcdef"
```

```toml
# wrangler.toml — replace the placeholder with the id printed above
[[kv_namespaces]]
binding = "WIND"
id = "REPLACE_ON_DEPLOY"
```

Deploy:

```sh
pnpm deploy
# ... Deployed wind-watch triggers
#   https://wind-watch.<account>.workers.dev
#   schedule: */10 * * * *
```

Get the first bake into KV. Either wait: the cron fires within 10 minutes, and because the
Worker skips bakes when Open-Meteo has no new run, the *first* run always bakes. Or trigger it
once by hand. There is no `wrangler cron trigger` command (checked against wrangler 4.151); the
way to run the deployed code with the **production** KV binding is remote dev:

```sh
pnpm wrangler dev --remote --test-scheduled --port 8787
# in another shell:
curl -s "http://localhost:8787/__scheduled?cron=*/10+*+*+*+*"   # → Ran scheduled event
# Ctrl-C the dev server
```

Then check the live URL. Expect `200`, an `ETag`, `Cache-Control: no-cache`, and a body that
starts with `{"v":1,"loc":{"name":"Port Townsend Bay"`:

```sh
curl -i https://wind-watch.<account>.workers.dev/v1/wind
# HTTP/2 200
# content-type: application/json; charset=utf-8
# etag: "sha256-53701f0493b656db"
# cache-control: no-cache
# access-control-allow-origin: *
# access-control-expose-headers: ETag
# content-encoding: br            ← added by Cloudflare, not by the Worker
#
# {"v":1,"loc":{"name":"Port Townsend Bay","lat":48.09075,"lon":-122.777275, ...
```

A `503 {"error":"no_data"}` means KV is still empty: the cron has not run yet.

## Where the URL goes

| File | Setting | Value |
|---|---|---|
| `apple/Config/Shared.xcconfig` | `WW_API_BASE = https:/$()/REPLACE.workers.dev` | `https:/$()/wind-watch.<account>.workers.dev` (keep the `$()`; it stops xcconfig reading `//` as a comment) |
| `web/config.js` | `window.WW_CONFIG = { apiBase: "" }` | `{ apiBase: "https://wind-watch.<account>.workers.dev" }` (empty string = offline fixture mode) |

No trailing slash. The clients append `/v1/wind`.

## Everyday commands

All from `server/`. Every `pnpm <name>` below is a script in `package.json`.

| Command | What it does |
|---|---|
| `pnpm test` | Vitest suite (transform, sun, summary, handlers) inside the Workers runtime; no network |
| `pnpm typecheck` | `tsc --noEmit` |
| `pnpm dev` | Local Worker at `http://localhost:8787` with a local KV; add `--test-scheduled` to expose the cron (pnpm forwards flags; do not insert `--`) |
| `pnpm deploy` | `wrangler deploy`: redeploys code and the cron trigger; KV data is untouched |
| `pnpm tail` | Live logs from the deployed Worker (`scheduled: baked 44 hours (new HRRR) + 41 NBM blocks, 2395 bytes, etag …` / `scheduled: unchanged …` / `nbm: failed …`) |
| `pnpm kv:get <key>` | Read a production KV key: `pnpm kv:get default:etag`, `pnpm kv:get default:meta`, `pnpm kv:get default:nbm_meta`, `pnpm kv:get default:body` |

Local bake and inspection:

```sh
pnpm dev --test-scheduled --port 8787
curl -s "http://localhost:8787/__scheduled?cron=*/10+*+*+*+*"     # bake into local KV (hits Open-Meteo once)
curl -i http://localhost:8787/v1/wind | head -12                   # 200 + ETag
curl -i -H 'If-None-Match: "sha256-…"' http://localhost:8787/v1/wind | head -3   # 304
curl -s "http://localhost:8787/v1/wind?lat=48.10&lon=-122.75" | head -c 200     # custom location
```

Redeploy after a code change: `pnpm test && pnpm typecheck && pnpm deploy`.

## How it works

1. Cron `*/10 * * * *` → `scheduled()` fetches `meta.json` for `ncep_hrrr_conus` and
   `ncep_nbm_conus` (not rate-limited).
2. If HRRR's `last_run_availability_time` equals `default:meta` and NBM's equals
   `default:nbm_meta`, it logs `unchanged` and stops. So KV is written only when a model has a
   new run, about twice an hour.
3. New HRRR: fetch the forecast (`cell_selection=sea`, 50 hours, knots, unix times, wind +
   `temperature_2m,cloud_cover,precipitation`), run `transform()` (truncate at the first null
   wind hour, round, fill sky/temperature holes from the nearest hour, infer the extended run,
   peak gust, sun events, summary line); top-level `fetched` = now. No new HRRR: the stored
   payload's HRRR part is reused unchanged, `fetched` included.
4. NBM (`src/nbm.ts`): request exactly `[start + hours h, start + 168 h)` in whole 3-hour blocks
   (`start_hour`/`end_hour`, GMT, same `cell_selection`), aggregate per block (max kn/gust,
   vector-mean dir, mean temp/cloud, max precip). Skipped when the NBM run and the HRRR horizon
   are both unchanged. `extended.fetched` changes only with a new NBM run.
5. NBM failure (error, all null, outside its grid, meta down) never fails a bake: the previous
   `extended` is kept if it re-cuts to whole blocks at the new `from`, else `extended` is null.
   `default:nbm_meta` is then cleared so the next cron retries NBM alone.
6. `enforceExtended` drops any `extended` that doesn't start exactly at `start + hours*3600`,
   then the payload is serialised with a fixed key order. KV keys are written only when their
   value changed: `default:body`, `default:etag` (`"sha256-<first 16 hex of SHA-256(body)>"`),
   `default:meta`, `default:nbm_meta`. Same data → same bytes → same ETag.
7. Any HRRR failure in steps 1–3 is logged and nothing is written: the last bake keeps serving
   and its `fetched` stops advancing, which the clients show as age. A stored body from before
   §4.2a counts as no bake (the next cron refetches HRRR).
8. `GET /v1/wind` reads body + etag from KV; `If-None-Match` (weak tags and lists accepted)
   → `304` with no body; otherwise `200`. `Cache-Control: no-cache`, CORS `*`.
9. `GET /v1/wind?lat&lon` validates and rounds to 2 dp, looks in `caches.default` under
   `https://wind-watch.cache/v1/wind?lat=..&lon=..`, and on a miss fetches both models with
   `cell_selection=nearest` (HRRR `timezone=auto`), transforms, and stores a copy for 600 s.
   NBM failing gives `extended: null`, never an error. `loc.name` is empty and `loc.cell` is
   `"nearest"`; the device shows its own name.
10. `OPTIONS` → 204. Anything else → `404 {"error":"not_found"}`.
11. The only upstream host is in `src/openmeteo.ts`; constants are in `src/config.ts`.

Failure modes (server side; the client rows are in `docs/DESIGN.md` §6.2):

| Situation | Worker behaviour | What a client sees |
|---|---|---|
| Open-Meteo unreachable or returns 5xx | Logs, keeps serving the last bake | Same payload, same ETag, `fetched` ages |
| Open-Meteo returns a run with fewer hours | Bakes it; `hours` shrinks | Shorter chart, earlier horizon |
| Forecast entirely null | `transform` throws, caught; last bake kept | Unchanged |
| NBM down, all null, or outside its grid | HRRR bakes; previous `extended` kept if it still lines up, else `null`; retried next cron | 7 d stops at the HRRR edge (`NBM unavailable`) |
| KV empty (before first bake) | `503 {"error":"no_data"}` | Empty state |
| Bad `lat`/`lon` | `400 {"error":"bad_location"}` | Error |
| Custom path: upstream down and nothing cached | `502 {"error":"upstream"}` | Error; default location unaffected |

## Costs and limits actually used

| Item | Free-plan limit | This Worker |
|---|---|---|
| Requests | 100,000 / day | ~30–100 / day (three clients polling, most answered `304`) |
| Cron triggers | 5 per account | 1 |
| Cron invocations | — | 144 / day |
| KV reads | 100,000 / day | ~500 / day (three reads per cron + two per `GET`) |
| KV writes | 1,000 / day | ≤ 4 per bake, ~48 bakes (24 HRRR + 24 NBM runs) ≈ 150 / day |
| Open-Meteo calls | 10,000 / day, 5,000 / h, 600 / min | 288 `meta.json` (not counted) + ~24 HRRR + ~48 NBM forecasts + two per custom-location miss |
| Cost | — | $0 |

## Attribution

Weather data by [Open-Meteo.com](https://open-meteo.com/), CC BY 4.0. Open-Meteo's free API is for
**non-commercial** use only: no ads, no subscriptions, no resale. This app is personal and
unmonetised; the attribution is shown on the iPhone About screen and the watch settings screen.
If that ever changes, Open-Meteo offers a paid API plan, and the Worker needs an API key and a
different host (`customer-api.open-meteo.com`) in `src/openmeteo.ts`.
