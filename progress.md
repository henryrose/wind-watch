# Wind Watch — build progress

Maintained by the orchestrator loop only (`docs/LOOP_PROMPT.md`). Agents report; the orchestrator
verifies, commits, and edits this file. Plan: `docs/IMPLEMENTATION_PLAN.md`.

Status legend: `todo` · `in-progress` · `done` · `blocked` · `other-machine`

Last updated: 2026-10-25 (design rounds 4–5 implemented, build 1.0 (8); App Store readiness H1–H9 and review reply R1–R8 above)


## Tasks

| ID | Workstream | Task | Depends on | Status | Verification | Commit / notes |
|---|---|---|---|---|---|---|
| A1 | foundation | Repo hygiene: .gitignore, Local.xcconfig.example, CLAUDE.md skeleton, commit docs | — | done | `git status` clean | 9d4b3db |
| A2 | foundation | Toolchain: xcodegen, node PATH; confirm watchOS runtime | A1 | done | `xcodegen --version`; `simctl list runtimes` shows watchOS 27.0 | xcodegen 2.46.0, node 24.13.0, watchOS 27.0 runtime; c812af9 |
| A3 | foundation | Fixtures: Open-Meteo forecast + meta captures, payload-reference.json | A2 | done | python loads all three, 45 hours | c812af9; live forecast fixture has 43 non-null hours (16Z run), reference payload has 45 |
| B1 | server | Scaffold + transform.ts + tests | A3 | done | `cd server && pnpm test` |  6b8cfbf; 19 tests; live fixture → 713 B, 43 h |
| B2 | server | sun.ts civil twilight + tests | B1 | done | `pnpm test` |  268b412; 39 tests; payload 931 B with sun |
| B3 | server | summary.ts rules + tests | B2 | done | `pnpm test` |  59 tests; live payload 1,023 B raw |
| B4 | server | index.ts fetch + scheduled, ETag/304, custom path; wrangler dev curl sequence | B3 | done | `pnpm test`; curl 200 then 304 |  79 tests; local dev: cron bake → 200 (994 B, ETag) → 304; custom path cached |
| B5 | server | server/README.md deploy runbook | B4 | done | commands exist in package.json |  all six pnpm scripts exist; no `wrangler cron trigger` exists, README documents waiting or `dev --remote --test-scheduled` |
| C1 | core | Package.swift, Payload, Forecast, Beaufort, Compass, TrustState, derivations + tests | A3 | done | `cd apple/WindCore && swift test` |  (see commit C1); 43 tests, Swift Testing, tools 6.2 |
| C2 | core | Twilight stops + tests | C1 | done | `swift test` |  51 tests total |
| C3 | core | WindClient + AppGroupStore + tests | C2 | done | `swift test` |  e4beb88; 74 tests |
| C4 | core | TimelineBuilder + tests | C3 | done | `swift test` |  84 tests |
| C5 | core | Glyphs, Tokens, TrustLine, WindChart, MiniStrip, previews | C4 | done | `swift build && swift test` |  99 tests, zero warnings |
| D1 | apps | project.yml, xcconfig, entitlements, generated .xcodeproj, build script | A2, C5 | done | iOS sim build + watchOS generic build |  iOS + watchOS sim builds succeed (re-run by orchestrator); both apps launch in simulators with WW_FIXTURE=1 |
| D2 | apps | iPhone app: Main, Location settings, About; fixture/state env; screenshots | D1 | done | build + screenshots reviewed |  iOS build clean, 105 Swift tests; 11 screenshots reviewed (fresh/stale/old/offline/horizon/firstrun/updating dark, fresh light, location, about, AX reflow); shading direction pixel-verified |
| D3 | apps | watchOS app: Now, 12-h strip, Settings | D2 | done | watchOS sim build + screenshots reviewed |  watch + iOS builds clean, 111 Swift tests; 12 screenshots reviewed on 46 mm and 42 mm |
| D4 | apps | Complications: provider + 4 families + previews | D3 | done | watchOS sim build; complication on a face screenshotted |  both builds clean, 112 tests; 5 DEBUG-page screenshots reviewed (all families, frame rule, tinted); real-face rendering is other-machine |
| D5 | apps | Custom-location sync (WatchConnectivity) + watch toggle | D4 | done | both compiles + WindCore test |  116 tests, both builds clean; phone→watch context round trip proven on paired simulators (screenshot d5-watch-settings-synced) |
| E1 | web | Page in fixture mode: chart, table, states, light/dark; node tests; screenshots | A3 | done | `node --test`; screenshots reviewed |  18 node tests; 13 screenshots in docs/screenshots (web-*); 375 px verified via iframe (headless Chrome clamps window width to 500) |
| E2 | web | Live mode against wrangler dev; offline-with-cache | E1, B4 | done | manual curl/reload sequence |  22 tests; live + offline-cached screenshots in docs/screenshots |
| F1 | handoff | docs/HANDOFF-OTHER-MACHINE.md checklist | B5, D5, E2 | done | orchestrator review |  docs/HANDOFF-OTHER-MACHINE.md |
| F2 | handoff | CLAUDE.md complete, README.md | F1 | done | orchestrator review |  CLAUDE.md commands + layout, README.md |

## Design package reconciliation (docs/design, 2026-10-21 evening)

Henry dropped the Claude Design package into `docs/design/` (README → DESIGN-HANDOFF → renders,
artboards, `chart_reference.py`). `docs/design/GAP-ANALYSIS.md` records the render-vs-build audit
made before any change (removed by the round-two package; it is in git history at `da65590`).
The old `docs/WINDWATCH-DESIGN-HANDOFF.md` was a strict subset and is gone.

| ID | Screen(s) | Task | Status | Verification | Notes |
|---|---|---|---|---|---|
| G1 | Chart spec | Port `chart_reference.py::svg()` into one `WindChart` (Canvas) over a pure `ChartGeometry`; styles phonePortrait / phoneLandscape / phoneClamped / watchStrip / mini; selection; 12-hour labels; day band | done | `cd apple/WindCore && swift test` (122; `ChartReferenceTests` compare bars, gust vertices, caps, sun dots, grid, now/edge rules, stops, arrows, ticks, day dividers with `reference/charts/*.svg`) | Swift Charts dropped; MiniStrip is now `WindChart(.next6, .mini)` |
| G2 | iPhone main, scrub, landscape, trust states, AX table, location, about | Header 22 + card gear; readout 60 with scrub plate; full-bleed chart card with title + hint; summary under the chart; table `W` / `B`; landscape view; AX reflow; Location/About to the artboards | done | iOS build; `docs/screenshots/d6-iphone-*.png` reviewed against `Phone-*.png` | `WW_SCRUB`, `WW_LANDSCAPE` DEBUG env; landscape orientations enabled in Info.plist |
| G3 | Watch Now, strip, settings; rectangular dash | Hero 84, artboard rhythm, `ViewThatFits` summary (3 → 2 → 1 lines), first-run copy split, two-line settings labels + blue check, 42 mm metrics preset, 40×5 dash | done | watch + iOS builds, 122 package tests; `d6-watch-now-{fresh,stale,offline,firstrun,updating}.png`, `-42` variants, `d6-watch-strip-{fresh,short}.png`, `d6-watch-settings-fresh.png`, `d6-watch-complications-rectangular*.png` reviewed against `Watch-*.png` / `Comp-Rectangular.png` | orchestrator rebuilt and reviewed the screenshots |
| G5 | All | Acceptance checklist §11 walked line by line | done | "Acceptance checklist" below: 14 pass, item 11 pass/held (Smart Stack) | |
| G6 | Round two (§6.4d) | Fixed 96 pt readout plate on iPhone (`Now · Wed 9:25am` label, same structure while scrubbing, ring only), edge-to-edge 402 pt chart, collapsible hourly table (`@AppStorage("hourlyTableExpanded")`, 52/60 pt row), footer attribution; landscape 48 pt header with the now label, plot = screen − 40 (834); watch strip is the launch page with the compact hero line; web `<details>` table remembered in `localStorage`; first day label at x + 4 and never hidden | done | 123 package tests (`phonebig`/`phonesel`/`land` re-copied at 402/834 and day-label x checked), 38 web tests (`webhover.svg` regenerated from the round-two script: only `Wed` moved 5 → 4); `d7-iphone-*`, `d7-watch-*`, `web-d7-*` reviewed against the round-two renders | readout top row shares label + peak text (artboard's third column overflows 354 pt; the render clips it); 42 mm strip plot 74 pt |
| G7 | Brand (§10a) | "Wake" app icon from `reference/brand_icon.py` (full/small/tiny tiers, Icon Composer layers, round watch icon), wordmark lockups on iPhone main eyebrow / About / web header, favicon + apple-touch-icon, footers "Wind Watch · weather data by Open-Meteo.com", watch Settings footer; About and Watch-Settings artboards revised | done | deploy Mac | 2026-10-22. `apple/scripts/render_icons.swift` renders every PNG from the brand_icon.py geometry (square, no alpha; iPhone 20 pt tiny, 29/40 pt small, 60 pt + 1024 full; watch 1024 full, clipped by watchOS; web favicon 16/32 tiny, apple-touch 180 full). `WindCore/UI/Brand.swift`: `BrandMark` (tier by size, round option), `Wordmark`, `BrandLockup`. iPhone eyebrow 17/15 portrait only, About lockup 30/26 + version, watch Settings footer (round mark 12 + "Wind Watch <ver>" Rounded Bold 11, artboard at 2×), web lockup row 28/26 (24/22 under 600 px, tagline shortens to "HRRR wind"), title "Wind Watch — <location>". Not done: Icon Composer `.icon` layers (tinted/glass); flat PNGs ship instead. Version text reads CFBundleShortVersionString (0.1.0 until MARKETING_VERSION becomes 1.0). |
| G4 | Web desktop + phone | Port `svg()` to JS (`webhover` / `webphone` geometry), hover tooltip + keyboard, legend, table, header/footer, phone layout | done | `cd web && node --test` (37; `chart.test.js` vs `webhover.svg` / `webphone48.svg`); `web-d6-desktop-{dark,light,hover}.png`, `web-d6-phone-dark.png` reviewed against `Web-Desktop.png` / `Web-Phone.png` | orchestrator re-ran tests and reviewed all four screenshots |

## App Store submission readiness (evaluated 2026-10-23, deploy Mac)

Verified on this Mac: 134 WindCore tests pass, iOS and watch simulator builds clean with zero
warnings, Worker live (200 + ETag, bake a few minutes old), TestFlight builds 0.1.0 (1)–(6)
uploaded 2026-10-22/23 from the archive → export-upload flow in docs/HANDOFF-OTHER-MACHINE.md §7.

Already in place, no task: bundle ids and the App Group come from xcconfig; app icons at every
iPhone size plus 1024 marketing, watch 1024, none with alpha; `ITSAppUsesNonExemptEncryption = NO`
in all three Info.plists; four privacy manifests (app, watch, complications, WindCore) that match
`web/privacy.html` and `server/src/usage.ts` (Product Interaction + Coarse Location, not linked,
no tracking, UserDefaults reasons CA92.1/1C8F.1); no `NSLocation*UsageDescription` needed (place
search is `MKLocalSearch` + `CLGeocoder`, no `CLLocationManager`); DEBUG-only surfaces gated
(`ComplicationsDebugView`, `WW_SAVE_CUSTOM`, `WW_CANDIDATE`; the `WW_*` env reads in release
code are inert outside a debugger); Open-Meteo CC BY 4.0 attribution, privacy link and contact
address on About; iOS 18 / watchOS 11 targets with `#available(iOS 26)` guards around the new
MapKit APIs; landscape, Dynamic Type/AX reflow and VoiceOver walked in §11 above; watch app
runs independently (`WKRunsIndependentlyOfCompanionApp`). Review-risk read: low. Guideline 4.2
(minimum functionality) is covered by the chart, scrub, table, custom HRRR locations, watch app
and four complication families; no sign-in, no demo account, no background modes.

| ID | Task | Status | Verification | Notes |
|---|---|---|---|---|
| H1 | Version for release: `MARKETING_VERSION` 0.1.0 → 1.0 and `CURRENT_PROJECT_VERSION` 6 → 7 in `apple/project.yml`; `./build.sh gen`; revert the `Local.xcconfig` file ref gen adds to `project.pbxproj` on this Mac | done | 2026-10-23: project.yml and pbxproj at 1.0 (7); About screen and watch Settings footer read 1.0 in the simulator (`docs/appstore/iphone-69-05-about.png`, `watch-46-03-settings.png`) | the usage labels (`X-WW-Client`) change to `ios/1.0+7` etc.; `pnpm usage` groups by version |
| H2 | Device test matrix, HANDOFF §6 rows 1–10, on the paired iPhone + watch from the TestFlight build, including the iOS 18 first-launch Welcome fix (e4b8467) | todo | tick the rows in "Needs the other machine" below with the date and build | the simulator cannot prove rows 3–6 (real face, cellular, hour rollover, 90 min / 6 h flips); none is ticked yet |
| H3 | App Store screenshots. iPhone: a 6.9" set (1320 × 2868; iPhone 18 Pro Max simulator — the `d7-iphone-*` set is 1206 × 2622, the optional 6.3" slot) of main, scrub, table open, location, about, dark scheme, `WW_FIXTURE=1` so the numbers are stable. Apple Watch: 416 × 496 (Series 12/11/10 46 mm; the Series 12 simulator already produces this size, `d7-watch-*.png`) of strip, now, settings, plus a face carrying the rectangular + circular complications captured on the real watch (unsigned simulators get no shared App Group, see "Needs the other machine") | in-progress | simulator sets done 2026-10-23 in `docs/appstore/`: `iphone-69-01-main`, `02-scrub`, `03-table`, `04-location`, `05-about` (1320 × 2868, iPhone 18 Pro Max, dark, 9:41 status bar) and `watch-46-01-strip`, `02-now`, `03-settings` (416 × 496, Series 12 46 mm); all PNG, alpha stripped. Left for Henry: a watch face carrying the rectangular + circular complications, captured on the real watch | `xcrun simctl status_bar <udid> override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3` before iPhone captures; ASC accepts up to 10 per slot, 3–5 is plenty 2026-10-23 later: ASC's required iPhone slot is "Dynamic Island (medium display)" = 1179×2556 or 1206×2622; the 1320×2868 set belongs in the optional "large display" slot (uploading it there was refused as "File dimensions are invalid"). Added `iphone-63-01…05.png` (1206×2622, iPhone 18 Pro simulator) for the required slot. |
| H4 | App Store Connect listing: confirm the public name ("Wind Watch Sailing" on the record; bundle display name is "Wind Watch"), subtitle, promotional text, description, keywords, support URL (`https://windwatch.wilder-roses.com`), privacy policy URL (`…/privacy.html`), category Weather, copyright, age-rating questionnaire (the 2025 questionnaire is mandatory for new submissions), App Privacy answers published (Product Interaction + Coarse Location, not linked, no tracking, matches the manifests), price Free, availability, watchOS app information with the watch screenshots | todo | every ASC section shows no red "missing" marker; Version 1.0 ready to submit | keep the description honest about the single default bay and custom HRRR points (CONUS only) so 2.3 metadata accuracy is not a question |
| H5 | App Review notes on the version page: default location is Port Townsend Bay, any HRRR point selectable; where custom locations live (Location screen, search or long-press, refused outside HRRR coverage with the reason shown); the watch app works standalone and the four complication families are added from the face editor under "Wind"; no account or login; the server is public, so no demo credentials; contact `windwatch@wilder-roses.com` | todo | notes saved on the version | reviewers test iPhone-only apps on iPad too; nothing to do, the layout is portrait-safe at iPhone widths |
| H6 | Decision: public listing or unlisted (DESIGN §9 says unlisted). Unlisted needs Apple's request form after the build is submittable, is meant for "limited audiences", and a personal app may be turned down, which falls back to a public listing anyway | done (public) | decision row in the log | default if silent: submit as a public app with manual release, decide at release time; nothing in the build differs between the two |
| H7 | Pre-archive gate: `git status` clean (commit or `git checkout` the two regenerated `.xcscheme` files currently modified), `cd apple && ./build.sh all`, `cd server && pnpm test && pnpm typecheck`, `curl -i …/v1/wind` → 200 + ETag; archive Release, generic iOS device, `-allowProvisioningUpdates`; upload build 7; install it from TestFlight and check the watch app and all four complications before submitting that same build | in-progress (gate passed 2026-10-23: 134 package tests, iOS + watch builds clean with zero warnings, 89 server tests + typecheck, Worker 200 + ETag, tree committed; archive, upload and the TestFlight check are Henry's) | build 7 processed in ASC, TestFlight install run through HANDOFF §6 rows 1–3 | re-login `wrangler` is not needed for an Apple upload; ASC upload needs Xcode's Apple ID session | 2026-10-23 20:55: build 1.0 (7) archived (Release, generic iOS, 4 Swift 6 actor-isolation warnings in `MainView.swift:145` haptics, harmless) and uploaded via `xcodebuild -exportArchive` with method app-store-connect / destination upload; "Upload succeeded". Remaining: TestFlight install check, then attach build 7 to version 1.0 in ASC. |
| H8 | Polish before 1.0, no review impact: the complication gallery description reads "for Port Townsend Bay" whatever location is active (`WindWatchComplications.swift`, `.description`) → location-neutral wording; consider a one-line "Forecast guidance, not a substitute for marine warnings" on About (not required by Apple; honest for a sailing app) | done / open | description now "Sustained wind, gusts and direction, hour by hour" (2026-10-23); the About line is Henry's call and not added | both are one-line edits; do them before H7 so they ship in build 7 | About disclaimer line: no answer from Henry before the build 7 upload, so not in 1.0; candidate for 1.0.1. |
| H9 | After approval: link the App Store page from the web footer and README; stop the 90-day TestFlight cycle; record the route taken in DESIGN §9 | later | | |

### App Review rejection, 2026-10-24 (1.0 build 7): information requested

Apple asked for six things, replied in Resolution Center **and** copied into App Review
Information → Notes. Draft text for items 2–6: `docs/appstore/review-reply.md`.

| ID | Task | Owner | Status | Notes |
|---|---|---|---|---|
| R1 | Screen recording on a physical iPhone on the latest iOS (and watch on latest watchOS): start from launch; first-launch chooser, chart + scrub, hourly table, Location search/pin + Save, About, then watch app pages and a face with the complications. No account/UGC/paid flows exist; the reply says so | Henry | todo | Control Center → Screen Recording; delete and reinstall from TestFlight first so the Welcome chooser shows; the watch cannot screen-record, so film it with another phone and attach that clip too; keep under ~2 min, trim in Photos |
| R2 | Purpose and target audience | Claude | drafted | review-reply.md §2 |
| R3 | Setup instructions, no credentials | Claude | drafted | review-reply.md §3 |
| R4 | External services list | Claude | drafted | review-reply.md §4: own Worker, Open-Meteo, Apple MapKit |
| R5 | Regional differences | Claude | drafted | review-reply.md §5: same everywhere; HRRR coverage limits custom points |
| R6 | Regulated industry / third-party material | Claude | drafted | review-reply.md §6: not applicable; CC BY 4.0 attribution |
| R7 | Henry reviews the draft, edits anything wrong, pastes §1–6 into the Resolution Center reply with the video attached, and into App Review Information → Notes; save | Henry | todo | the reply alone is not enough; Apple asked for both |
| R8 | Resubmit (no new build needed unless the reply prompts one) | Henry | todo | |

## Design package rounds 4–5 (docs/design/CHANGES.md, 2026-10-25)

Pulled `893d30f` from GitHub. The server and the payload are untouched: every change is in the
clients, so builds ≤ 7 in the field keep working against the same `/v1/wind` and `?lat&lon`.

| ID | Change (CHANGES.md) | Status | Verification | Notes |
|---|---|---|---|---|
| R4a | Rectangular complication: one numbers row (`15 · G25 · ▸ from W · as of 23:30`, no `kn`, trust text Medium 11 never smaller), full-width 12-hour strip below (§6.3, §7.1) | done | `ComplicationStripTests` (12 slots, 14 pt slot at 168 pt, no labels/grid/arrows); DEBUG page at 46 mm and `WW_RECT=42` reviewed against `Comp-Rectangular.png` | `ViewThatFits` order: drop `from W` → drop `G` → 20 pt number. Old reads `Wed 09:00` (no "as of"). Past horizon: dash + `No forecast` + `15Z Wed`, dashed box `Open app to refresh`. New `ComplicationStrip` + `ChartWindow.complication12` + `ChartStyle.complicationStrip`; the 6-hour `MiniStrip` is kept for its reference tests but no longer shipped. Smart Stack still held |
| R4b | Locations: up to 12 equal rows, Port Townsend Bay seeded as row 1 but deletable/renamable/reorderable, last row can't be deleted, selected row drives every surface (§8.3) | done | `SavedLocationTests` (fresh install, round trip, build-7 migration, list rules, context incl. legacy keys), `ForecastSessionSyncTests` (fallback to row 1, last row stays, stops at 12); screenshots of 5 and 12 rows | Stored as `locations` + `selectedLocationID` in the App Group; the old `customLocation`/`useCustom` keys are migrated on load and still written (defaults and WatchConnectivity context) so a build-7 watch app follows a build-8 phone. The Port Townsend Bay point (whatever its name) still fetches the baked `/v1/wind`; every other row `?lat&lon`. Rename via the row's context menu; new points get a name field + Add |
| R4c | Watch Settings: the same list, Crown-scrolled; `first in list` / `set on iPhone` | done | watch screenshot with three rows | a wrist tap selects locally; the phone's next context wins (unchanged rule) |
| R5a | Locations: permanent Edit button, swipe still works, full list opens in Edit mode with a `List full (12)` banner, map long-press shows `List full — delete a location first` | done | `loc12` screenshot | standard `List` edit mode puts the minus on the left (the render draws it right) |
| R5b | Scrub readout: degrees back, small and secondary, only while scrubbing; at rest `peak G25 · 12am` over a number-only Beaufort chip; 124 pt number column | done | main + scrub screenshots vs `Phone-Main*.png` | landscape readout follows the same degrees rule. `Derivations.peakReadoutText` adds the day when the peak is ≥ 18 h away |
| R5c | Chart: first day label suppressed while `now` is on the plot; first tick label dropped at the plot edge (portrait phone) | done | `ChartReferenceTests` now also compare tick labels (phone/web) with the refreshed `phonebig`/`phonesel`/`land` SVGs; web `chart.test.js` vs `webhover.svg` | landscape and web keep `9am` in slot 0, as the reference does |
| R5d | Build 8: version 1.0 (8), haptic actor warning fixed | done | `./build.sh all`: 141 Swift tests, both builds zero warnings; server 89, web 38 | |

## Needs the other machine (from plan §7)

| Item | Status | Where verified |
|---|---|---|
| Worker deploy + KV + cron live | done | 2026-10-21: https://wind-watch.wind-watch-server.workers.dev; cron bake verified, 200 + ETag, 304 on If-None-Match, ?lat&lon 200 |
| Real API base in Shared.xcconfig and web/config.js | done | 2026-10-21; web tests 22/22 |
| Signing, device install | done | 2026-10-22: paid team, automatic signing, TestFlight installs on the phone + watch |
| Complications on a real watch face + shared App Group cache between app and extension | other-machine (H2 row 3) | unsigned simulator builds get no group container, so app and extension cannot share the cache here; DEBUG page `WW_PAGE=complications` verified the views |
| Cellular standalone, hour-boundary rollover, 90-min/6-h flips on wrist | other-machine (H2 rows 4–6) | device matrix |
| WatchConnectivity custom-location round trip on hardware (simulator round trip done) | other-machine (H2 rows 8–9) | device matrix rows 8–9 |
| TestFlight upload | done | 0.1.0 builds (1)–(6) uploaded 2026-10-22/23; next upload is build 7 (H1, H7) |

## Decisions log

| Date | Decision | Made by | Why |
|---|---|---|---|
| 2026-10-21 | Wire payload = DESIGN §4.2; view model = HANDOFF §2; see plan §0 | plan | two docs describe two layers |
| 2026-10-21 | Keep six-bar strip on rectangular; hold Smart Stack; keep "G" | plan (defaults for HANDOFF §12) | Henry can overrule |
| 2026-10-21 | XcodeGen project.yml is the source; generated .xcodeproj is also committed | plan | Henry wants the project checked in |
| 2026-10-21 | `run.extended` = lastHour − 48 h, kept only if a 6-hourly UTC init earlier than `run.latest`, else null | server agent (B1) | matches DESIGN §2.3 and the reference payload; −47 h gave a non-init hour |
| 2026-10-21 | `peak` computed on rounded gusts, first occurrence wins; a null in any wind array ends the forecast; empty forecast throws (B4 must catch and keep last bake) | server agent (B1) | wire value always equals some `gust[i]` |
| 2026-10-21 | `server/.npmrc` pins the public npm registry; `compatibility_date = 2026-08-01` | server agent (B1) | `~/.npmrc` on this Mac routes to a private feed (401); the vitest Workers pool's bundled workerd rejects newer dates |
| 2026-10-21 | `@cloudflare/vitest-pool-workers` is deprecated in favour of `@cloudflare/vitest-plugin`; kept for now, migrate in B4 if cheap | server agent (B1) | brief named the old package |
| 2026-10-21 | Swift tools-version 6.2; Swift Testing; `Beaufort.step` returns true 0–12 and colour merging happens in `colorToken` | core agent (C1) | `.v26` platforms need tools 6.2 |
| 2026-10-21 | TrustState precedence: firstRun > pastHorizon > updating > offlineCached > old > stale > fresh; `AgeTier` exposed separately so numbers dim under offline/updating | core agent (C1) | HANDOFF §3 "age rules still apply" |
| 2026-10-21 | Twilight: empty `sun` → day = 1; interpolation on absolute dates so any window shares `day(at:)`; fixture Thu sun times are 07:09/07:41 (handoff text says 07:08/07:40), §6.2 fractions still within ±0.002 | core agent (C2) | fixture is the oracle, not the handoff prose |
| 2026-10-21 | Sun day range is `[start, start+(hours−1)h]` inclusive; polar days clamp (rise=set=noon etc.) with `dawn ≤ rise ≤ set ≤ dusk` always | server agent (B2) | consistent with plan §0 `horizon` |
| 2026-10-21 | `WindClient` is a Sendable final class; requests use `.reloadIgnoringLocalCacheData`; `refresh()` always fetches and callers consult `RefreshPolicy.shouldFetch` first; store writes under `<container>/WindWatch/` and falls back to Application Support when the group is not entitled | core agent (C3) | keeps 304 handling honest; degrades without crashing in unsigned builds |
| 2026-10-21 | Web: tick labels sit inside the plot bottom with a halo; narrow breakpoint uses 22/16 insets; gridline labels live in the card padding; past-horizon boundary = `start + hours·3600`; peak chip dot = Beaufort of the peak gust; `?scheme=` and `?now=` are verification aids | web agent (E1) | §6.1 web insets leave no room below the arrow row |
| 2026-10-21 | Timeline: single past-horizon entry once `now > horizon` (not only after the +1 h boundary); cap drops furthest-out hours first; `lastCheckOK` applies to every entry | core agent (C4) | HANDOFF §3 defines past horizon as `now > horizon` |
| 2026-10-21 | Summary: aligned non-overlapping 6-h windows; whole-forecast calm short-circuits to `Calm through …`; no compass under 4 kn; daytime periods take "by", night periods don't; trims whole clauses easing → gusts → building | server agent (B3) | sliding windows failed the briefed "building to 15 kn W" |
| 2026-10-21 | Chart: `.all` plots every hour from `start` (not from now); arrow cadence/ticks derive from the window; bars use hour-interval x with `.ratio(0.72)`; Old desaturation applied to the whole Chart view; `ChartStyle.watch` in points (198×92 plot); past-horizon trust line is amber; `PreviewData` is `static let` | core agent (C5) | pixel tuning deferred to D2/D3 screenshots |
| 2026-10-21 | Worker tests mock upstream with `vi.stubGlobal("fetch")` (no `fetchMock` in pool-workers 0.23 or vitest-plugin 1.4); stayed on pool-workers. Custom cache key rounds to 2 dp; cached copy max-age 600, client sees no-cache; non-GET → 404 | server agent (B4) | brief's codemod fallback would not have helped |
| 2026-10-21 | Web live mode: 304 keeps the derived forecast; 503 `no_data` → first-run wording; other 5xx/4xx/network → offline-with-cache or first-run; checks coalesced; `?state=` still works in live mode | web agent (E2) | |
| 2026-10-21 | `pnpm dev --test-scheduled` (no `--`): pnpm 12 passes a literal `--` through to wrangler, which then treats the flag as a positional script | server agent (B5) | tripped a probe run |
| 2026-10-21 | Watch app is a single-target watchOS app (no WatchKit extension), embedded by XcodeGen from a plain target dependency; `Local.xcconfig` is included at the end of Shared so it overrides; `WindCore.TimelineEntry` to be renamed `WindTimelineEntry` in D4 to avoid the WidgetKit clash; always address simulators by UDID (two booted sims make `booted` ambiguous) | core agent (D1) | |
| 2026-10-21 | iPhone: arrows drawn in a chartOverlay band under the axis labels; default card shows the sea-cell coords 48.09, −122.78; table rows start at the hero hour; peak chip dot = Beaufort of the peak gust; `WW_TYPE_SIZE` env replaces the content-size launch arg (ignored under simctl); Map tiles don't load in headless screenshots, MKLocalSearch/geocoding need an interactive run | core agent (D2) | |
| 2026-10-21 | Watch: Settings is page 3 of the vertical TabView (no long-press); `Next N h` uses whole hours left; summary fixed at 2 lines; shared `@Observable ForecastSession` in WindCore replaces the app-local model, takes `bundleInfo:` for testability, returns Bool from refresh so each app calls WidgetCenter itself; pages size from GeometryReader ignoring the bottom safe area | core agent (D3) | TabView vertical pages squeezed multi-line text otherwise |
| 2026-10-21 | Complication views live in `apple/Shared/Complications/` compiled into both the extension and the watch app (WindCore stays WidgetKit-free); rectangular past-horizon uses a capsule dash, not the em-dash glyph; rectangular/inline trust text uses the age tier even when offline; corner gauge is a `Gauge(.accessoryLinear)` with a ramp gradient (no discrete segments or dashing on the corner arc); provider treats a `REPLACE` host as no client; `ww.fixture` group flag mirrors fixture data for the extension | core agent (D4) | |
| 2026-10-21 | Location sync: the iPhone is the editor and its `useCustom` wins when a context arrives; the watch toggle is local-only between contexts and never pushes back; `reloadPreferences()` clears the cache only when the active location changed; iOS re-pushes the full preference on activation | core agent (D5) | DESIGN §7 |
| 2026-10-21 | Relative-time bands: morning 05–11, afternoon 12–16, evening 17–22, around midnight 23–00, overnight 01–04; night belongs to the preceding day | core agent (C1) | makes Thu 00:00 peak read "around midnight" at Wed 09:00 per HANDOFF §8.1 |
| 2026-10-21 | Chart is a Canvas port of `chart_reference.py`, not Swift Charts: one `WindChart` for strip/phone/landscape/mini; `ChartStyle.unit` = 0.5 on watch surfaces because the reference draws them at 2× px; tick hours are hour-of-day anchored (3-h at 00/03/…, 6-h at 03/09/15/21) so labels don't drift as the forecast rolls; the y-domain follows §6.1 everywhere (the reference `watchstrip` call pinned 30, rule gives 20 for hours 0–11); sun/twilight events past the horizon edge are not drawn (§6.2); the mini strip keeps 6 slots with an empty tail (§6.3) where the reference `minishort` stretched 4 | orchestrator (G1) | README says port `svg()`; doc wins over the script's pinned defaults |
| 2026-10-21 | iPhone order is header → readout → chart card → summary → table (render / §6.4 "centrepiece"), not §8.1's summary-before-chart; scrub uses `highPriorityGesture` so touching the plot never scrolls; first-day label hidden when `now` sits under it (README nit); landscape plot height flexes (236 on a 402-tall phone) so the hint sits under the tick labels; AX sizes drop the `ends …` suffix (`Phone-Table-LargeType`) | orchestrator (G2) | |
| 2026-10-21 | Location default card shows the sea-cell coordinates to 3 decimals (48.091, −122.777), not the artboard's 48.117, −122.760 (that is the town, not the HRRR point) | orchestrator (G2) | honesty about the actual grid point |
| 2026-10-21 | Web: tooltip also flips right of the rule within 160 px of the left edge; a touch selection stays until a tap outside the chart (doc only says `pointerleave` clears); light-scheme tooltip uses the light ground with a dark ring; hour-of-day tick anchoring as on the phone | web agent (G4) | hours 0–5 would otherwise spill the card; a tap on a phone would only flash the card |
| 2026-10-21 | Watch Now: the system clock inset (~52 pt, not the artboard's 22) leaves room for 2 summary lines at the 84 pt hero on 46 mm, so the summary uses `ViewThatFits` (3 → 2 → 1 lines); 42 mm uses a reduced metrics preset from the artboard's fourth panel (hero 75) because 84 pt leaves no room for any summary there; direction row top padding 11 (measured from the hero box whose pill hangs below the line); `TrustLine.firstRunTitle` / `firstRunBody` split the first-run copy, `firstRunText` stays the accessibility label; strip short-horizon header counts whole hours left (`Next 4 h` at 00:05) | watch agent (G3) | screenshots vs the artboards |
| 2026-10-21 | Corner complication keeps the `Gauge(.accessoryLinear)` gradient and solid amber (render: stepped segments, dashed amber) — WidgetKit draws the corner arc itself | orchestrator (G3) | not reproducible in WidgetKit |
| 2026-10-23 | Public App Store listing with manual release, not unlisted (H6). | Henry | unlisted is for limited audiences and may be refused for a personal app; nothing in the build differs |
| 2026-10-23 | iPhone first-launch Welcome chooser (`WelcomeView`, `Welcome` in ForecastSession): Port Townsend Bay in one tap, or "Somewhere else" → the Location screen, which closes it on Save. Overrides HANDOFF "no onboarding" at Henry's request. Shown only with no flag, no custom location and no cache, so upgrades skip it; `WW_WELCOME=1` forces it. Watch unchanged (it follows the phone). | Henry | fresh-install and relaunch screenshots in the simulator |

## Acceptance checklist (DESIGN-HANDOFF §11), walked 2026-10-21

| # | Item | Result | Evidence |
|---|---|---|---|
| 1 | Hero shows sustained, gust, arrow, `from X`, trust line on first paint from cache, no spinner | pass | `d6-iphone-main.png`; watch `d6-watch-now-fresh.png`; `ForecastSession` paints the cache synchronously, spinner only on first run |
| 2 | Every wind number is an integer in knots, VoiceOver included | pass | `Forecast.Hour` is `Int`; `heroAccessibility` / `rowLabel` tests |
| 3 | Bars use exactly the §4.1 ramp, no interpolation | pass | `hexesMatchHandoff41` test; Canvas fills from `Beaufort.colorToken` |
| 4 | Gust line through cap centres; caps bar + 2 | pass | `ChartReferenceTests` (caps vs reference SVG) |
| 5 | Arrows rotate `dirFrom + 180`; labels say `from`; inline snaps to 8 points | pass | `Compass` tests; `ChartReferenceTests` arrow rotations; inline uses `arrowSymbolName` |
| 6 | Shading ramps linearly dawn→rise, set→dusk; sun dots only at rise/set | pass | `Twilight` tests; reference gradient stops match within 0.0015 |
| 7 | Last bar is the last forecast hour; dashed edge + label; no padding | pass | `ChartReferenceTests` edge at `X(45)`; `d6-iphone-main.png` |
| 8 | Trust flips at 90 min and 6 h without a refresh | pass | `TimelineBuilder` tests (entries at fetched + 90 min / + 6 h); app `tick()` every 60 s |
| 9 | Offline with cache shows the reason and the cached time | pass | `d6-iphone-offline.png`, `d6-watch-now-offline.png` |
| 10 | Circular: `8` and `15` keep arrow/gust still; ring survives tint; stale ring dashed | pass | `d4-complications-circular.png` (frame-rule row and tinted row; views unchanged) |
| 11 | Rectangular never shows the location; Smart Stack does | pass / held | rectangular has no name; Smart Stack widget held (decision 2026-10-21) |
| 12 | Default location one tap, card never moves | pass | `d6-iphone-location.png`: default card first, static; button on the whole card |
| 13 | Phone table reflows at AX; chart clamps at 152 | pass | `d6-iphone-ax.png` (`ChartStyle.phoneClamped`, two-line rows) |
| 14 | Web reads in both schemes and at 375 px with a scrolling table | pass | `web-d6-desktop-dark.png`, `web-d6-desktop-light.png`, `web-d6-phone-dark.png` (compact table in an `overflow-x: auto` wrapper) |
| 15 | VoiceOver: chart `45-hour wind chart: … ends Friday 05:00`; hero `15 knots, gusting 25, from the west, as of 23:30` | pass | `WindChart.accessibilityText`; `heroAccessibility` test |

## Questions for Henry (loop proceeds on the stated default)

| Date | Question | Default taken |
|---|---|---|
| 2026-10-23 | H6: public App Store listing or unlisted (DESIGN §9 chose unlisted; Apple may refuse unlisted for a personal app)? | Henry answered 2026-10-23: public listing, manual release |

## Blockers

| Date | Task | What is blocked | What was tried |
|---|---|---|---|

## Screenshots index

- `docs/screenshots/web-<state>-<scheme>-1180.png` for fresh, stale, old, offline, horizon, firstrun × dark, light; `web-fresh-dark-375.png` (true 375 px via iframe). Captured 2026-10-21 from E1.
- `docs/screenshots/d1-iphone-placeholder.png`, `d1-watch-placeholder.png`: D1 pipeline proof (placeholder UIs, real WindChart on the phone). Chart arrows overlap tick labels here; fixed in D2.
- `docs/screenshots/d2-iphone-<state>-<scheme>.png`: iPhone app states plus location, about, and AX reflow. From D2.
- `docs/screenshots/d3-watch-<page>-<state>.png` (46 mm) and `d3-watch42-<page>-fresh.png` (42 mm): watch app pages. From D3.
- `docs/screenshots/d4-complications-<family>.png`: every family × fresh/stale/old/horizon from the DEBUG page, plus the circular frame rule and tinted rows. From D4.
- `docs/screenshots/d5-watch-settings-synced.png`: watch Settings after the phone pushed a custom location over WatchConnectivity (paired simulators). From D5.
- `docs/screenshots/d6-iphone-<name>.png`: post-design-package iPhone set — main, scrub (hour 15), land / land-idle (landscape), ax (AX3), old, offline, light, location, about. From G2.
- `docs/screenshots/d6-watch-<page>-<state>[-42].png`: watch Now (fresh, stale, offline, firstrun, updating; 42 mm fresh/firstrun), strip (fresh, short horizon), settings, rectangular complication rows. From G3.
- `docs/screenshots/web-d6-{desktop-dark,desktop-light,desktop-hover,phone-dark}.png`: web after the design package (hover = `?hover=15`). From G4.
- `docs/screenshots/d7-iphone-{main,scrub,table-open,ax3,landscape,landscape-scrub}.png`, `d7-watch-{strip,strip-short,strip-42mm,now}.png`, `web-d7-{desktop-hover-table,phone-dark}.png`: round two (§6.4d). From G6.
- `docs/appstore/iphone-69-*.png` (1320 × 2868) and `docs/appstore/watch-46-*.png` (416 × 496): App Store screenshot sets from the simulators with fixture data, no alpha. From H3, 2026-10-23.
- `docs/screenshots/web-live-1180.png` (live against local Worker, HRRR 17Z, 42 h) and `web-offline-cached-1180.png` (Worker killed, cached data with amber offline line). From E2.
