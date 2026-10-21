# Wind Watch server

A Cloudflare Worker that pulls the HRRR wind forecast for Port Townsend Bay from Open-Meteo
every 10 minutes, bakes it into one ~1 KB JSON payload in Workers KV, and serves it at
`GET /v1/wind` with an ETag. Custom locations (`?lat&lon`) are baked on demand and cached for
10 minutes. The watch, phone and web clients only ever talk to this Worker, never to Open-Meteo.

The payload is the only contract: `docs/DESIGN.md` §4 (endpoint, response shape, headers, cron).

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
| `pnpm tail` | Live logs from the deployed Worker (`scheduled: baked 43 hours, 1023 bytes, etag …` / `scheduled: unchanged …`) |
| `pnpm kv:get <key>` | Read a production KV key: `pnpm kv:get default:etag`, `pnpm kv:get default:meta`, `pnpm kv:get default:body` |

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

1. Cron `*/10 * * * *` → `scheduled()` fetches `meta.json` for `ncep_hrrr_conus` (not rate-limited).
2. If `last_run_availability_time` equals the stored `default:meta`, it logs `unchanged` and stops.
   So KV is written only when Open-Meteo has a new HRRR run, about hourly.
3. Otherwise it fetches the forecast (`cell_selection=sea`, 50 hours, knots, unix times),
   runs `transform()` (truncate at the first null, round to integers, infer the extended run,
   peak gust, sun events, summary line) and serialises with a fixed key order.
4. It writes three KV keys: `default:body` (the JSON), `default:etag`
   (`"sha256-<first 16 hex of SHA-256(body)>"`), `default:meta` (the availability time).
5. Any failure in steps 1–4 is logged and nothing is written: the last bake keeps serving and
   its `fetched` stops advancing, which the clients show as age.
6. `GET /v1/wind` reads body + etag from KV; `If-None-Match` (weak tags and lists accepted)
   → `304` with no body; otherwise `200`. `Cache-Control: no-cache`, CORS `*`.
7. `GET /v1/wind?lat&lon` validates and rounds to 2 dp, looks in `caches.default` under
   `https://wind-watch.cache/v1/wind?lat=..&lon=..`, and on a miss fetches with
   `cell_selection=nearest&timezone=auto`, transforms, and stores a copy for 600 s.
   `loc.name` is empty and `loc.cell` is `"nearest"`; the device shows its own name.
8. `OPTIONS` → 204. Anything else → `404 {"error":"not_found"}`.
9. The only upstream host is in `src/openmeteo.ts`; constants are in `src/config.ts`.
10. Because the ETag changes only when a new run is baked, a client polling every 20 minutes
    downloads about one real body per HRRR run and gets `304` the rest of the time.

Failure modes (server side; the client rows are in `docs/DESIGN.md` §6.2):

| Situation | Worker behaviour | What a client sees |
|---|---|---|
| Open-Meteo unreachable or returns 5xx | Logs, keeps serving the last bake | Same payload, same ETag, `fetched` ages |
| Open-Meteo returns a run with fewer hours | Bakes it; `hours` shrinks | Shorter chart, earlier horizon |
| Forecast entirely null | `transform` throws, caught; last bake kept | Unchanged |
| KV empty (before first bake) | `503 {"error":"no_data"}` | Empty state |
| Bad `lat`/`lon` | `400 {"error":"bad_location"}` | Error |
| Custom path: upstream down and nothing cached | `502 {"error":"upstream"}` | Error; default location unaffected |

## Costs and limits actually used

| Item | Free-plan limit | This Worker |
|---|---|---|
| Requests | 100,000 / day | ~30–100 / day (three clients polling, most answered `304`) |
| Cron triggers | 5 per account | 1 |
| Cron invocations | — | 144 / day |
| KV reads | 100,000 / day | ~150 / day (one `default:meta` read per cron + two per `GET`) |
| KV writes | 1,000 / day | ≈ 3 × number of new HRRR runs ≈ 72 / day (the skip rule avoids the other 120 runs) |
| Open-Meteo calls | 10,000 / day, 5,000 / h, 600 / min | 144 `meta.json` (not counted) + ~24 forecasts + a few custom-location fetches |
| Cost | — | $0 |

## Attribution

Weather data by [Open-Meteo.com](https://open-meteo.com/), CC BY 4.0. Open-Meteo's free API is for
**non-commercial** use only: no ads, no subscriptions, no resale. This app is personal and
unmonetised; the attribution is shown on the iPhone About screen and the watch settings screen.
If that ever changes, Open-Meteo offers a paid API plan, and the Worker needs an API key and a
different host (`customer-api.open-meteo.com`) in `src/openmeteo.ts`.
