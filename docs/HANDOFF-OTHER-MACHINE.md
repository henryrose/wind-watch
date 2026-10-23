# Wind Watch — handoff to the deploy Mac

Written 2026-10-21. This is the checklist for the machine that owns the Apple Developer and
Cloudflare accounts. Everything up to here was built and verified on a different Mac with no
accounts: server logic and local run, the Swift package, the iPhone and watch apps and
complications in simulators, and the web page. What is left is deploy, signing, device
behaviour, and TestFlight.

Read first: `CLAUDE.md` (architecture in ten lines), then `progress.md` (what was verified and
the decisions log), then this file. `docs/DESIGN.md` and `docs/design/DESIGN-HANDOFF.md`
are the contracts if you need to change behaviour.

## 1. Clone and tools

```sh
git clone <repo> wind-watch && cd wind-watch
# Node 24 (nvm: `nvm install 24 && nvm use 24`), pnpm 12+, Xcode 27 with the watchOS simulator runtime
brew install xcodegen
```

`server/.npmrc` pins the public npm registry on purpose (the authoring Mac's global npmrc
pointed at a private feed). Leave it.

## 2. Deploy the Worker (Cloudflare account)

Full runbook: `server/README.md`. Short form, all from `server/`:

```sh
pnpm install
pnpm wrangler login
pnpm wrangler kv namespace create WIND     # paste the printed id into wrangler.toml, replacing REPLACE_ON_DEPLOY
pnpm deploy                                 # prints https://wind-watch.<account>.workers.dev
```

Then either wait up to 10 minutes for the cron's first bake, or run it once by hand:

```sh
pnpm wrangler dev --remote --test-scheduled --port 8787
curl -s "http://localhost:8787/__scheduled?cron=*/10+*+*+*+*"     # in another shell → "Ran scheduled event"
```

Confirm:

```sh
curl -i https://wind-watch.<account>.workers.dev/v1/wind | head -20
# expect 200, ETag: "sha256-…", Cache-Control: no-cache, body starting {"v":1,"loc":{"name":"Port Townsend Bay"
curl -i -H 'If-None-Match: "<that etag>"' https://wind-watch.<account>.workers.dev/v1/wind | head -3
# expect 304
```

Commit the `wrangler.toml` change (the KV id is not a secret).

## 3. Point the clients at it

| File | Setting | Set to |
|---|---|---|
| `apple/Config/Shared.xcconfig` | `WW_API_BASE = https:/$()/REPLACE.workers.dev` | `https:/$()/wind-watch.<account>.workers.dev` (keep the `$()`; it stops xcconfig reading `//` as a comment) |
| `web/config.js` | `window.WW_CONFIG = { apiBase: "" }` | `{ apiBase: "https://wind-watch.<account>.workers.dev" }` |

The apps treat a host containing `REPLACE` as "no server" and never fetch, so until this is set
they only work in fixture mode. Commit both.

## 4. Signing (Apple account)

```sh
cp apple/Config/Local.xcconfig.example apple/Config/Local.xcconfig   # untracked, gitignored
```

Edit `Local.xcconfig`: `WW_TEAM_ID = <10-char team id>`, `WW_BUNDLE_PREFIX = <your reverse-DNS prefix>`.
Bundle ids become `<prefix>.windwatch`, `.windwatch.watchkitapp`, `.windwatch.watchkitapp.complications`
and the App Group `group.<prefix>.windwatch`. Nothing else needs editing.

Open `apple/WindWatch.xcodeproj` (or `cd apple && ./build.sh gen` first if you changed
`project.yml`). With automatic signing, Xcode registers the three bundle ids and the App Group
on first build. If it complains about the group, add it once in the developer portal with the
same name.

## 5. Build and run on devices

Select the `WindWatch` scheme and your iPhone; the watch app is embedded and installs on the
paired watch. Then select `WindWatchWatch` and the watch to run it standalone for debugging.

Simulator builds without signing still work here: `cd apple && ./build.sh all`.

Debug environment variables (set in the scheme's Run → Arguments → Environment):

| Variable | Effect |
|---|---|
| `WW_FIXTURE=1` | load `fixtures/payload-reference.json` instead of the network; also mirrors it into the App Group so complications render it |
| `WW_STATE=stale\|old\|offline\|horizon\|firstrun\|updating` | force a trust state |
| `WW_NOW=<ISO8601>` | pin the clock |
| `WW_SCREEN=location\|about` (iPhone) / `WW_PAGE=now\|strip\|settings\|complications` (watch) | open a screen directly; `complications` is DEBUG-only and takes `WW_FAMILY=rectangular\|circular\|corner\|inline` |
| `WW_TYPE_SIZE=xl…ax5` (iPhone) | Dynamic Type override |
| `WW_SAVE_CUSTOM="Name,lat,lon"` (iPhone, DEBUG) | save and select a custom location at launch, pushing it to the watch |

## 6. Device test matrix

These are the things a simulator cannot prove. Tick them in `progress.md` when done.

| # | Test | Expect |
|---|---|---|
| 1 | Fresh install, phone on Wi-Fi, open the iPhone app | first paint `No data yet…` then live numbers within ~2 s; trust line `as of HH:MM · HRRR nnZ · ends …` |
| 2 | Open the watch app with the phone nearby | same data; `WidgetCenter` reload after the fetch |
| 3 | Add the rectangular, circular, inline and corner complications to a face | all four render from one fetch; circular frame rule: `8` vs `15` do not move the arrow |
| 4 | Phone off or in airplane mode, watch on cellular, open the watch app and pull to the strip | fetch succeeds over cellular; numbers update |
| 5 | Watch in airplane mode for over an hour, glance at the complication across an hour boundary | numbers roll to the next hour with no network; after 90 min the trust text turns amber (`as of HH:MM`), circular ring goes dashed amber |
| 6 | Leave it 6+ hours | numbers dim to `ink.old`, label gains the weekday |
| 7 | Break the server (`wrangler delete` the route, or set a wrong `WW_API_BASE` in a debug build) and open the app | amber `Couldn't reach server · showing data from HH:MM` over the cached numbers, never blank |
| 8 | On the phone, save a custom location (search or long-press the map), select it | phone shows the custom name; watch Settings shows the custom plate within a minute (WatchConnectivity application context; the phone's choice wins over a wrist toggle) and the watch fetches `?lat&lon`. Already proven once on paired simulators; this row confirms it on hardware, including delivery while the watch app is suspended |
| 9 | On the watch, toggle back to Port Townsend Bay with the phone away | works standalone; the toggle is local |
| 10 | Let the forecast run past its horizon (or `WW_STATE=horizon` on device) | complications show `—` / `No forecast — open app`, app shows `No forecast · last run HRRR nnZ <Day>` |
| 11 | Open the web page at the deployed `apiBase` | live data; kill the Worker route → amber offline line with cached data on reload |

## 7. TestFlight

Archive `WindWatch` (Product → Archive, Any iOS Device), Distribute → App Store Connect →
Upload. Internal testing needs no review; add yourself as an internal tester and install from
the TestFlight app; the watch app comes along. Builds expire after 90 days, so re-upload
quarterly, or move to an unlisted App Store release later to stop that (DESIGN §9).

Before archiving: `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `apple/project.yml`
(currently 0.1.0 / 1), real app icons in the two `Assets.xcassets` (the sets are empty), and
the About screen's attribution is already in place.

External testers or an App Store listing need a privacy policy URL and support contact:
`https://windwatch.wilder-roses.com/privacy.html` (`web/privacy.html`) and
`windwatch@wilder-roses.com` (Squarespace forwarding). App Privacy answers to match the page:
no tracking; Usage Data and Coarse Location (custom spot, rounded to 0.01°) collected, not
linked to the user, used for app functionality and analytics.

## 8. Rows in `progress.md` marked other-machine

| Item | Verified by |
|---|---|
| Worker deploy + KV + cron live | §2 |
| Real API base in Shared.xcconfig and web/config.js | §3 |
| Signing, device install, App Group container shared by app and extension | §4, §5 |
| Cellular standalone, hour-boundary rollover, 90-min / 6-h flips on a wrist | §6 rows 4–6 |
| Complications on a real face | §6 row 3 |
| WatchConnectivity custom-location round trip | §6 rows 8–9 |
| TestFlight upload | §7 |

## 9. Everyday commands afterwards

```sh
# server
cd server && pnpm test && pnpm typecheck      # before deploying
pnpm deploy                                    # redeploy code + cron; KV untouched
pnpm tail                                      # live logs
pnpm kv:get default:etag                       # inspect the bake

# apple
cd apple && ./build.sh all                     # gen + swift test + both simulator builds
cd apple/WindCore && swift test                # package only

# web
cd web && node --test
```
