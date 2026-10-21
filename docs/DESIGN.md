# Wind Watch — technical design

Status: draft for review, 2026-10-21. No app code exists yet.
Companion to `InitialPrompt.md`, which is the brief this answers.

## 0. Decisions already made

| Topic | Decision |
|---|---|
| OS floor | iOS 26 / watchOS 26 |
| Server | A free-tier Cloudflare Worker is acceptable |
| Xcode project | Checked in as-is, no generator |
| Accounts | Apple Developer and Cloudflare accounts live on a *different* Mac and Claude account. This repo is authored here and built/deployed there. |
| Distribution | TestFlight for personal use (default taken; see §9) |
| "As of" | Fetch time plus horizon end, with HRRR run time carried in the payload because it turns out to be free (default taken; see §6) |
| HRRR tail | Truncate at the real horizon, no model blending (see §6.3) |
| Grid cell | Use Open-Meteo `cell_selection=sea` for the default location (see §2.1) |

Handoff rule that falls out of the accounts split: **everything needed to build and deploy lives in the repo**, nothing is assumed from local keychains, team IDs, or memory. Signing identity, bundle-ID prefix, and the Worker URL are injected from an untracked xcconfig / wrangler vars with a tracked `.example`.

## 1. Recommended architecture

```
                 every 10 min (cron)
Open-Meteo  <────────────────────────  Cloudflare Worker
 (HRRR)     ────────────────────────>   bake → KV["default"]
                                             │
                               GET /v1/wind  │  ~1 KB JSON, ETag, 304s
                                             ▼
            ┌───────────────┬────────────────┴───────────────┐
      Apple Watch app   Watch widget ext.                iPhone app
      (standalone,      (complications:                  (chart + table,
       cellular)         one fetch → ~48 entries)         location settings)
            └──── shared App Group cache ────┘      WatchConnectivity ──> watch
```

One Worker, one KV namespace, one JSON contract, one Swift package shared by three Apple targets. The clients never talk to Open-Meteo.

Why this and not the alternatives (full comparison in §3):

- **The watch's "instant on wrist raise" does not depend on the server at all.** WidgetKit pre-renders complication entries, and the app reads a cached file before any network. The server choice is about payload size, reliability, and whether a second-year-you can reason about it, not about first paint.
- **A pre-baked payload is the only option that gives a last-good copy outside the device.** If Open-Meteo is down or blocks us, the Worker keeps serving the previous bake and the client labels it by age. With no server, an Open-Meteo outage means no data on a fresh install or a wiped cache.
- **Open-Meteo sends no `ETag`/`Last-Modified`.** Conditional requests only exist if we put something in front of it.
- **All forecast-derived logic lives in one place, in TypeScript, testable with a fixture.** Changing the summary wording or twilight handling is a `wrangler deploy`, not a TestFlight build.
- **The cron is the hook for gust alerts later** (out of scope for v1, but the brief asked what paints you into a corner). With no server, alerts would be a rewrite.

What it costs in simplicity: one hosted thing with two handlers (`fetch`, `scheduled`), a `wrangler.toml`, and a KV binding. Roughly 150 lines of TypeScript plus a solar calculator.

## 2. Data source facts that shaped the design

Verified against the live API on 2026-10-21.

### 2.1 Grid cell: the default snaps onto land unless told otherwise

Open-Meteo's `cell_selection` parameter defaults to `land`, which "finds a suitable grid-cell on land with similar elevation." For 48.09, -122.76 that yields 48.116 N, 122.788 W, about 2 km west of downtown Port Townsend, over the peninsula. HRRR land cells carry higher surface roughness than water cells and tend to report lower 10 m wind.

With `cell_selection=sea` the same request snaps to **48.0907 N, 122.7773 W**, which is in Port Townsend Bay. Same-day comparison of the two cells:

| cell | snapped to | mean sustained next 45 h | max gust |
|---|---|---|---|
| land (default) | 48.1163, -122.7881 | 9.0 kn | 24.3 kn |
| sea | 48.0907, -122.7773 | 8.3 kn | 24.7 kn |
| sea, from 48.10,-122.75 | 48.0980, -122.7390 | 10.2 kn | 24.7 kn |

The differences are modest on this particular day but the sea cell is the physically right one for a boat on the bay. **Recommendation: default location = 48.09, -122.76 with `cell_selection=sea`.** Custom locations use `nearest` (see §7), because `sea` can wander a long way for an inland point.

### 2.2 Run times are available for free

`https://api.open-meteo.com/data/ncep_hrrr_conus/static/meta.json` returns `last_run_initialisation_time`, `last_run_availability_time`, `update_interval_seconds`, etc. Open-Meteo says metadata calls do not count toward rate limits and advises waiting 10 minutes after availability time for replicas to catch up. Observed today: the 15Z run became available at 16:39Z, i.e. about 1 h 40 min after init.

### 2.3 The forecast API keeps the long run's tail

At 16:50Z the latest run was 15Z (an 18 h run; `data_end_time` in metadata = 10Z next day), yet the forecast call returned 45 non-null hours out to 12Z two days ahead. Open-Meteo splices: the newest run covers the near hours, the newest 48 h run (12Z) covers the rest. So a single payload mixes two runs, and the "extended" run's init time can be inferred as `horizon_end − 48 h`.

### 2.4 Size and compression

The raw Open-Meteo response for 50 hours × 3 variables is ~2.0 KB, 672 bytes gzipped. Our baked payload will be smaller.

### 2.5 Terms

Free tier is non-commercial only (no ads, no subscriptions; a tip jar is allowed), limits 600/min, 5,000/h, 10,000/day, data under CC-BY 4.0. Attribution ("Weather data by Open-Meteo.com") goes on the iPhone About screen and the watch settings screen. Open-Meteo's own terms page suggests Cloudflare Workers for proxies. Our load: 144 cron fetches/day + a few on-demand custom-location fetches, well under limits.

## 3. Server shape: options compared

Usage assumption: one user, ~30 client fetches/day, plus whatever the server does on its own.

| | A. No server (clients → Open-Meteo) | **B. Worker + cron + KV (recommended)** | C. Static object in R2/S3 + CDN, baked by a cron elsewhere | D. Small VPS |
|---|---|---|---|---|
| First paint on watch | Cache/timeline: instant. Same for all. | Same | Same | Same |
| Fresh fetch on cellular | Radio wake + TLS ≈ 0.5–2 s, then ~150–300 ms Open-Meteo, 2 fetches (forecast + meta) | Radio + TLS, then ~20–60 ms KV read at the edge, 1 fetch, 304 when unchanged | Radio + TLS, CDN hit ~20–60 ms; conditional GETs work | Radio + TLS, one origin region, ~50–150 ms |
| Monthly cost | $0 | $0 (Free plan: 100k req/day, 5 cron triggers, KV 100k reads/1k writes per day) | $0–$1 (R2 free tier), but the cron needs a host: GitHub Actions cron is 5-min minimum, drifts under load, and 144 runs/day burns ~2,000+ Actions minutes/month | $4–6 |
| Failure modes | Open-Meteo down or blocking the client IP → nothing on fresh install; no last-good beyond the device. Each client parses raw Open-Meteo and detects the horizon itself. | Open-Meteo down → serve last bake, client labels age. Cloudflare down (rare) → device cache, labeled. KV empty only before the first bake. | Two systems to fail (cron host, object store); stale object if cron silently stops. | Patching, disk full, cert renewal, reboot. Classic single box. |
| What you maintain | Three Swift clients that all embed forecast logic; changes ship via TestFlight | One `wrangler.toml`, ~150 lines TS, one deploy command | A workflow file + bucket policy + CDN config | OS, TLS, process supervision, backups of nothing |
| Alerts later | Needs a server anyway | Cron already exists; add APNs | Cron exists but is in the wrong place to hold tokens | Fine |
| Reasoning about it in a year | Easy, but "why is twilight wrong on the watch but not the phone" is a three-target bug | Easy: one function turns one JSON into another | Two places to look | Easy but you have a pet |

**Rejected:**

- **A (no server)** is the honest runner-up. It loses on last-good data, on conditional requests, on putting forecast logic into three Swift targets, and on alerts. It wins only on "no hosted component," and you have said a free Worker is acceptable.
- **C** moves the cron to a worse place. The Worker *is* a cron plus a KV store plus a CDN edge in one artifact.
- **D** is strictly more maintenance for no benefit at this scale.

**Also considered: Fly.io and Render (existing accounts).** Fly is a workable second choice: a Node process on the smallest machine at about $2.19/month plus storage, cron as an in-process loop, so the machine must stay running. It costs a Dockerfile, a `fly.toml`, and a long-running process to trust, for no gain over the Worker. Render is out on latency alone: free services spin down after 15 idle minutes and take about a minute to wake, which is exactly the quiet-night-then-dock case, and Open-Meteo names Render as a shared-IP host that can hit limits sooner. Decided 2026-10-21 to stay with the Worker; the server is portable TypeScript if that ever changes.

**Variant considered and rejected: on-demand Worker with the Cache API, no cron, no KV.** About 40 fewer lines, but the Cache API is per-datacenter and evictable, so there is no last-good copy; and there is no cron to hang alerts on. The KV binding is a two-line config cost.

## 4. API contract

### 4.1 Endpoint

```
GET https://<name>.<account>.workers.dev/v1/wind              → default location (KV)
GET https://<name>.<account>.workers.dev/v1/wind?lat=..&lon=.. → custom location (on-demand, cached 10 min)
```

No auth, no API key. The URL is not secret; the Worker is rate-limited by Cloudflare's free tier and the response is public data. If it ever gets abused, add a header check, but don't design for it now.

### 4.2 Response

```jsonc
{
  "v": 1,
  "loc":   { "name": "Port Townsend Bay", "lat": 48.0907, "lon": -122.7773,
             "tz": "America/Los_Angeles", "cell": "sea" },
  "model": "ncep_hrrr_conus",
  "fetched": 1792600800,          // unix s: when the Worker last pulled NEW data from Open-Meteo
  "run":   { "latest": 1792594800, "extended": 1792584000 },  // unix s, HRRR init times (§2.3)
  "start": 1792598400,            // unix s of hour index 0 (the hour that was current at bake)
  "hours": 45,                    // count of non-null hours; the HRRR horizon is start + hours*3600
  "kn":   [3, 4, 3, 5, ...],      // sustained 10 m wind, knots, integers, length == hours
  "gust": [6, 7, 5, 9, ...],      // gusts, knots, integers
  "dir":  [210, 215, 220, ...],   // direction wind blows FROM, degrees true, integers
  "peak": { "gust": 25, "at": 1792670400 },
  "summary": "Light SW this morning, building to 15–20 kn S by 4 pm, gusts to 25. Easing after midnight.",
  "sun": [                        // one per local civil day touched by [start, horizon], unix s
    { "dawn": 1792589100, "rise": 1792591200, "set": 1792629600, "dusk": 1792631700 },
    { "dawn": ..., "rise": ..., "set": ..., "dusk": ... },
    { "dawn": ..., "rise": ..., "set": ..., "dusk": ... }
  ]
}
```

Design notes:

- **Index-addressed arrays, no per-hour timestamps.** `time = start + i*3600`. Removes ~45 ISO strings.
- **Integers.** HRRR 10 m wind to a tenth of a knot is false precision. Direction to the degree is plenty.
- **Civil twilight is computed server-side** with the NOAA solar algorithm (~40 lines, deterministic). Open-Meteo's `daily=sunrise,sunset` does not include civil twilight, so we compute all four ourselves and drop the `daily` request.
- **`fetched` only advances when Open-Meteo has new data.** The cron compares `meta.json`'s `last_run_availability_time` to the value stored with the last bake and skips the forecast fetch if unchanged. Consequences: the ETag is stable between model runs, 304s are the common case, and a silently stale upstream shows up as an old `fetched` rather than being masked by a fresh bake time.
- **Estimated size:** ~800 bytes raw, ~450 bytes gzipped.

### 4.3 What is computed where

| Computed on the Worker | Computed on device |
|---|---|
| Null-truncation → `hours` | Which index is "now" (depends on the device clock) |
| Run times from `meta.json` + inference | Staleness tier and label (depends on now vs `fetched`) |
| Peak gust and when | Beaufort bucket → color (it's a UI table that must exist in Swift anyway) |
| Summary line (rule-based, not an LLM) | Arrow rotation: `dir + 180` (blowing TO) |
| Sun events incl. civil twilight | All formatting and units display |

Rule: the Worker does everything that is a pure function of the forecast. The device does everything that depends on "now" or on pixels.

### 4.4 Headers

Response:

```
Content-Type: application/json; charset=utf-8
ETag: "sha256-<first 16 hex of body hash>"
Cache-Control: no-cache                  // always revalidate; we drive refresh ourselves
Access-Control-Allow-Origin: *           // lets the existing web page use the same payload
Content-Encoding: gzip | br              // Cloudflare does this automatically on Accept-Encoding
```

Request: clients send `If-None-Match` with the stored ETag. `304 Not Modified` on match, empty body.

Errors (JSON body `{"error": "<code>"}`):

| Status | When |
|---|---|
| 503 `no_data` | KV empty, only possible before the first cron bake |
| 400 `bad_location` | lat/lon missing, non-numeric, or out of range |
| 502 `upstream` | custom-location path and Open-Meteo failed with no cached copy |

### 4.5 Cron

`*/10 * * * *`. Steps: fetch `meta.json` (not rate-limited) → if `last_run_availability_time` unchanged, exit → fetch forecast with `cell_selection=sea&timezone=GMT&timeformat=unixtime&forecast_hours=50` → transform → write `KV["default"] = {body, etag, meta_availability}`. KV writes: ≤144/day, typically ~24/day with the skip. Limit is 1,000/day.

## 5. Watch refresh and the complication

### 5.1 Pieces

- **Watch app** (SwiftUI): current conditions, a 12-hour bar strip, settings.
- **Widget extension** (WidgetKit): `accessoryRectangular`, `accessoryCircular`, `accessoryInline` in v1; `accessoryCorner` later.
- **Shared App Group container** on the watch: `wind.json` (last payload bytes), `wind.meta.json` (`etag`, `lastChecked`, `lastError`). Both targets read it; both may write it.

The watch app does **not** register its own `WKApplicationRefreshBackgroundTask`. The widget timeline reload is the only background mechanism. One mechanism, one cache.

### 5.2 Timeline provider, one fetch → ~48 entries

```
getTimeline(context):
  payload = AppGroupStore.load()                      // sub-ms, may be nil
  if payload == nil || age(payload.fetched) > 20 min || age(meta.lastChecked) > 20 min:
      try await fetch(ifNoneMatch: meta.etag, timeout: 10 s)   // 200 → store; 304 → bump lastChecked; error → keep
  entries = []
  for hour in currentHour ... horizonEnd (≤ 48):
      entries.append(Entry(date: hour, payloadRef, index))
  entries.append(Entry(date: horizonEnd, .noForecast))      // see §6.2
  return Timeline(entries, policy: .after(now + 30 min))
```

Each entry is a date plus an index into one shared payload, so the timeline is cheap to build and the complication rolls forward hourly with **no network**. Views render `kn[index]`, `gust[index]`, `dir[index]`.

### 5.3 Budget and what happens when a refresh is skipped

Apple documents 40–70 timeline reloads per day for a frequently viewed widget, roughly every 15–60 minutes, and the system decides when or whether to honor `.after(...)`. A 30-minute request is within budget (48/day) and leaves headroom. Reloads triggered while the containing app is in the foreground don't count.

If a reload is skipped, nothing breaks: the entries already cover every hour to the horizon, so the numbers keep rolling forward from the last good payload. What changes is the **age**, which the view shows (§6.1). The design treats skipped refreshes as normal, not as errors.

Standalone cellular: the extension's `URLSession` call works when the phone is unreachable. watchOS may defer background networking on cellular when battery is low; the staleness label covers that case too.

### 5.4 App foreground

On `scenePhase == .active`: render from the App Group file immediately (no spinner on first paint), then if `lastChecked` is older than 10 minutes, fetch in the background and animate the change. After a successful fetch, call `WidgetCenter.shared.reloadAllTimelines()` so the complication picks up the new run.

## 6. Freshness and failure

### 6.1 Age tiers

Age = now − `payload.fetched`. (`lastChecked` is kept separately so the app can say "checked 3 min ago, no new run" vs "couldn't reach server since 13:05".)

| Age | Watch display |
|---|---|
| < 90 min | Numbers, no caveat. (One HRRR cycle + ~1 h 40 delivery means data is usually 1–2 h behind the model clock anyway; that is normal and not flagged.) |
| 90 min – 6 h | Numbers plus "as of 13:05" in the secondary line, amber |
| > 6 h | Numbers in gray, "as of Tue 13:05" |
| Entry past horizon | "No forecast — open app", no numbers |

Complication views use `Text(fetchedDate, style: .relative)` where there is room so the age ticks without a reload; where there isn't, a single glyph (•, ⚠) by tier.

### 6.2 Failure matrix

| Situation | Worker | Watch / phone |
|---|---|---|
| Open-Meteo unreachable from Worker | Keeps serving last bake; `fetched` stops advancing | Shows last data, labels age normally |
| Open-Meteo returns a run with fewer hours | `hours` shrinks; chart shortens honestly | Timeline ends earlier; horizon label moves |
| Worker unreachable from device | — | Serves from App Group cache; `lastChecked` stops; app shows "Couldn't reach server, showing data from 13:05" |
| Device never fetched (fresh install, no network) | — | Empty state: "No data yet. Needs cellular or Wi-Fi once." |
| Clock skew / future `fetched` | — | Treat negative age as 0 |
| KV empty (before first bake) | 503 `no_data` | Same as unreachable |

### 6.3 Short horizon: truncate, don't blend

Agreeing with the brief, with the argument for the record:

- The missing hours are 40–48 h out, the least actionable part of the forecast.
- Blending adds a second upstream call, a second code path in the transform, and a per-hour "source" flag that then needs a visual treatment on a 40 mm screen. That is a lot of surface for 2–8 hours.
- A visibly shorter chart with "HRRR ends Fri 05:00" at the edge is itself useful information: it tells you which run you're looking at.

The payload already carries `run.extended`, so the phone can show "HRRR 15Z / 12Z" in the footer for the curious.

The only blending I'd consider later is replacing `hours` beyond the HRRR horizon with NBM and drawing those bars hatched. The `v` field and index-addressed arrays make that additive (a second `kn2/gust2/dir2/src` block), so v1 doesn't foreclose it.

## 7. Alternate location

**Model:** `Location { name, lat, lon, tz }`. `Location.default` is compiled in. At most one custom location in v1, stored in `UserDefaults(suiteName: appGroup)` on each device as `customLocation` plus a `useCustom: Bool`.

**Set on the iPhone only.** Settings screen: search by name (`MKLocalSearch`) or long-press a map; store the placemark's coordinate and time zone (`MKPlacemark.timeZone`, falling back to the Worker's `tz` from `timezone=auto`). Then `WCSession.default.updateApplicationContext(["customLocation": ..., "useCustom": ...])`. Application context is delivered when the watch is next reachable and persists on the watch, so the watch keeps working standalone after that.

**On the watch:** a single toggle in settings, "Port Townsend Bay / <custom name>", so you can switch from the wrist without the phone. No editing on the watch.

**Worker:** `?lat&lon` → round to 2 decimals (cache key), fetch with `cell_selection=nearest&timezone=auto`, transform with the same function, store in the Cache API for 10 minutes, same response shape with `loc.cell = "nearest"` and `loc.name` empty (the device shows its own stored name). No KV, no cron for custom locations.

**Default path untouched:** no query string → KV read. The custom path is a separate `if` at the top of the handler.

## 8. Project layout

```
wind-watch/
├── CLAUDE.md                     # architecture summary + build/deploy commands for the other machine
├── docs/DESIGN.md                # this file
├── server/                       # Cloudflare Worker
│   ├── wrangler.toml             # name, KV binding, cron; no secrets
│   ├── src/index.ts              # fetch() + scheduled()
│   ├── src/transform.ts          # Open-Meteo JSON → payload v1
│   ├── src/sun.ts                # NOAA solar: rise/set/civil dawn/dusk
│   ├── src/summary.ts            # rule-based one-liner
│   └── test/                     # vitest; fixtures/openmeteo-2026-10-21.json captured today
└── apple/
    ├── WindWatch.xcodeproj
    ├── Config/
    │   ├── Shared.xcconfig       # tracked: WW_API_BASE, versions, deployment targets
    │   ├── Local.xcconfig        # UNTRACKED: DEVELOPMENT_TEAM, WW_BUNDLE_PREFIX
    │   └── Local.xcconfig.example
    ├── WindCore/                 # local Swift package, no UI framework deps beyond SwiftUI
    │   ├── Payload.swift         # Codable mirror of §4.2, hour(at:), age tiers
    │   ├── WindClient.swift      # URLSession + ETag handling
    │   ├── AppGroupStore.swift   # read/write wind.json + meta
    │   ├── Beaufort.swift        # bucket + color ramp
    │   ├── Location.swift
    │   └── WindChart.swift       # Swift Charts view parameterised by hour window
    ├── WindWatch/                # iOS app: chart, table, settings, About (attribution)
    ├── WindWatchWatch/           # watchOS app
    └── WindWatchComplications/   # watchOS WidgetKit extension
```

Targets: iOS app, watchOS app, watchOS widget extension, plus the `WindCore` package linked by all three. No iOS widget in v1 (a lock-screen widget would be ~50 lines later, reusing the same provider).

**Signing and IDs for handoff:** `PRODUCT_BUNDLE_IDENTIFIER = $(WW_BUNDLE_PREFIX).windwatch[.watchkitapp[.complications]]`, App Group `group.$(WW_BUNDLE_PREFIX).windwatch`, `DEVELOPMENT_TEAM = $(WW_TEAM_ID)`. Entitlements files reference the variables. On this machine, `Local.xcconfig` can hold a free personal team or nothing at all: everything through Stage 3 runs in the iOS + watchOS simulators, which render complications. Cellular/standalone behaviour is device-only and is tested on the deploy machine.

**Swift Charts vs custom drawing.** Swift Charts on both apps, one `WindChart` view in `WindCore` with a `window` parameter (48 h on the phone, 12 h on the watch). Marks: `BarMark` for sustained wind coloured by Beaufort, `LineMark` + `PointMark` (custom tick-cap symbol) for gusts, `PointMark` with a rotated `Image(systemName: "arrow.up")` for direction (blowing TO), `RectangleMark` with a `LinearGradient` for night fading through civil twilight, and `PointMark` sun glyphs at rise/set. The **complication** does not use Swift Charts: the rectangular family draws a six-bar strip with plain `Rectangle`s, which keeps the widget render cheap and the memory footprint small. If Swift Charts proves heavy on the watch app (unlikely for 12 bars), the fallback is a `Canvas` implementation of the same view, which is why the chart takes a prepared `[HourPoint]` array rather than the raw payload.

## 9. Cost of ownership

| Item | Monthly | Yearly | Notes |
|---|---|---|---|
| Apple Developer Program | $8.25 | $99 | Required for TestFlight and App Groups on device. Held by the deploy account. |
| Cloudflare Workers, Free plan | $0 | $0 | 100,000 req/day, 10 ms CPU/req, 5 cron triggers. We use ~30 req/day and 1 cron. |
| Workers KV, Free | $0 | $0 | 100k reads / 1k writes per day. We use ~30 reads, ≤144 writes. |
| `workers.dev` subdomain | $0 | $0 | No custom domain needed. |
| Open-Meteo | $0 | $0 | Non-commercial, CC-BY attribution in-app. |
| **Total excluding Apple** | **$0** | **$0** | |
| **Total** | **$8.25** | **$99** | |

If Cloudflare's free tier ever changes, the Worker is ~150 lines of portable TypeScript; the same shape runs on Deno Deploy or Vercel cron with minor edits.

**Distribution routes, personal use:**

| Route | Expiry | Effort | Verdict |
|---|---|---|---|
| Xcode direct install, free personal team | 7 days | Cable, both devices, weekly | No |
| Xcode direct install, paid team | 1 year | Cable, both devices, yearly | Fine as a backup |
| **TestFlight internal** | 90 days per build | Upload from the deploy Mac; install from the TestFlight app; the watch app comes along | **Start here** |
| App Store, unlisted | None | One App Review pass; non-commercial is fine for Open-Meteo's terms | Move here once stable to stop the 90-day re-upload |

## 10. Visual language

Carried over from the web version (HTML to be shared and dropped under `docs/reference/`):

- Beaufort-stepped colour ramp on sustained-wind bars. The ramp table lives once in `Beaufort.swift`; the complication uses the same table.
- Gusts as a line with tick caps above each bar.
- Direction arrows point where the wind blows **TO** (`dir + 180`), on the chart and on the complication.
- Day/night shading: night band fading through civil twilight to day, small sun marker at rise and set.
- Watch: same vocabulary at 12 hours, no axis labels, time ticks every 3 h, "now" line.

Exact colours, bar widths, and the twilight fade curve wait for the HTML.

## 11. Out of scope: what v1 does and doesn't foreclose

| Later feature | v1 posture |
|---|---|
| Push alerts on gust thresholds | **Kept open by design.** The cron already evaluates every bake; alerts add an APNs key as a Worker secret, a `POST /v1/device` to register a token in KV, and a threshold check. No client refactor. |
| Tides and currents | Additive: a `tide` block in the payload from a second source. The chart's x-axis is time, so an overlay slots in. |
| Multi-day beyond HRRR | Additive via a second model block (§6.3). |
| Accounts | Never needed for one user; the Worker is unauthenticated public data. |
| Multiple saved locations | `customLocation` becomes `[Location]`; the Worker already handles arbitrary lat/lon. |

## 12. Staged build plan

Each stage ends with something runnable. Stage 1 is the thin vertical slice.

**Stage 0 — scaffold (this machine).** Repo layout above, `CLAUDE.md`, xcconfig split with `.example`, capture today's Open-Meteo response and `meta.json` as test fixtures, `wrangler.toml` with KV binding. Exit: `npm test` runs an empty suite; Xcode project opens with three targets and the package.

**Stage 1 — vertical slice.** Worker `scheduled()` + `fetch()` for the default location only, `transform.ts` with tests against the fixture, no summary, no sun. `WindCore.Payload` + `AppGroupStore` + `WindClient`. Watch app shows current hour (kn, gust, direction arrow). Rectangular complication built from one fetch with hourly entries and `.after(30 min)`. iPhone app shows a plain table. Run in simulators here against `wrangler dev`; first real deploy from the other machine. Exit: complication rolls forward across an hour boundary in the simulator with the network disabled.

**Stage 2 — freshness.** ETag/304 on both ends, `meta.json` skip logic in the cron, age tiers and labels, horizon-end entry, empty and error states. Device test over cellular with the phone off (deploy machine). Exit: pull the Worker offline for an hour and the watch says so.

**Stage 3 — iPhone chart.** Sun block in the Worker, `WindChart` in Swift Charts with the full visual language, table under it, About screen with attribution.

**Stage 4 — watch polish.** 12-hour chart in the watch app, circular + inline complications, summary line in the Worker (rule-based), peak gust callout.

**Stage 5 — alternate location.** iPhone settings with map search, WatchConnectivity context, watch toggle, Worker custom path with Cache API.

**Stage 6 — ship.** TestFlight internal build from the deploy machine, README for the year-later you, decision point on App Store unlisted.

## 13. References

- Open-Meteo terms and limits: https://open-meteo.com/en/terms
- Open-Meteo GFS & HRRR docs (`cell_selection`, run lengths): https://open-meteo.com/en/docs/gfs-api
- Open-Meteo model updates and metadata API: https://open-meteo.com/en/docs/model-updates
- HRRR metadata endpoint: https://api.open-meteo.com/data/ncep_hrrr_conus/static/meta.json
- Cloudflare Workers pricing and limits: https://developers.cloudflare.com/workers/platform/pricing/ , https://developers.cloudflare.com/workers/platform/limits/
- Apple, Keeping a widget up to date (refresh budget): https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
