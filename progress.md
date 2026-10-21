# Wind Watch — build progress

Maintained by the orchestrator loop only (`docs/LOOP_PROMPT.md`). Agents report; the orchestrator
verifies, commits, and edits this file. Plan: `docs/IMPLEMENTATION_PLAN.md`.

Status legend: `todo` · `in-progress` · `done` · `blocked` · `other-machine`

Last updated: 2026-10-21 (A, B1–B3, C1–C5, E1 done; B4, D1 running; E2 waits for B4)

## Tasks

| ID | Workstream | Task | Depends on | Status | Verification | Commit / notes |
|---|---|---|---|---|---|---|
| A1 | foundation | Repo hygiene: .gitignore, Local.xcconfig.example, CLAUDE.md skeleton, commit docs | — | done | `git status` clean | 9d4b3db |
| A2 | foundation | Toolchain: xcodegen, node PATH; confirm watchOS runtime | A1 | done | `xcodegen --version`; `simctl list runtimes` shows watchOS 27.0 | xcodegen 2.46.0, node 24.13.0, watchOS 27.0 runtime; c812af9 |
| A3 | foundation | Fixtures: Open-Meteo forecast + meta captures, payload-reference.json | A2 | done | python loads all three, 45 hours | c812af9; live forecast fixture has 43 non-null hours (16Z run), reference payload has 45 |
| B1 | server | Scaffold + transform.ts + tests | A3 | done | `cd server && pnpm test` |  6b8cfbf; 19 tests; live fixture → 713 B, 43 h |
| B2 | server | sun.ts civil twilight + tests | B1 | done | `pnpm test` |  268b412; 39 tests; payload 931 B with sun |
| B3 | server | summary.ts rules + tests | B2 | done | `pnpm test` |  59 tests; live payload 1,023 B raw |
| B4 | server | index.ts fetch + scheduled, ETag/304, custom path; wrangler dev curl sequence | B3 | in-progress (agent server) | `pnpm test`; curl 200 then 304 | |
| B5 | server | server/README.md deploy runbook | B4 | todo | commands exist in package.json | |
| C1 | core | Package.swift, Payload, Forecast, Beaufort, Compass, TrustState, derivations + tests | A3 | done | `cd apple/WindCore && swift test` |  (see commit C1); 43 tests, Swift Testing, tools 6.2 |
| C2 | core | Twilight stops + tests | C1 | done | `swift test` |  51 tests total |
| C3 | core | WindClient + AppGroupStore + tests | C2 | done | `swift test` |  e4beb88; 74 tests |
| C4 | core | TimelineBuilder + tests | C3 | done | `swift test` |  84 tests |
| C5 | core | Glyphs, Tokens, TrustLine, WindChart, MiniStrip, previews | C4 | done | `swift build && swift test` |  99 tests, zero warnings |
| D1 | apps | project.yml, xcconfig, entitlements, generated .xcodeproj, build script | A2, C5 | in-progress (agent core) | iOS sim build + watchOS generic build | |
| D2 | apps | iPhone app: Main, Location settings, About; fixture/state env; screenshots | D1 | todo | build + screenshots reviewed | |
| D3 | apps | watchOS app: Now, 12-h strip, Settings | D2 | todo | watchOS sim build + screenshots reviewed | |
| D4 | apps | Complications: provider + 4 families + previews | D3 | todo | watchOS sim build; complication on a face screenshotted | |
| D5 | apps | Custom-location sync (WatchConnectivity) + watch toggle | D4 | todo | both compiles + WindCore test | |
| E1 | web | Page in fixture mode: chart, table, states, light/dark; node tests; screenshots | A3 | done | `node --test`; screenshots reviewed |  18 node tests; 13 screenshots in docs/screenshots (web-*); 375 px verified via iframe (headless Chrome clamps window width to 500) |
| E2 | web | Live mode against wrangler dev; offline-with-cache | E1, B4 | todo | manual curl/reload sequence | |
| F1 | handoff | docs/HANDOFF-OTHER-MACHINE.md checklist | B5, D5, E2 | todo | orchestrator review | |
| F2 | handoff | CLAUDE.md complete, README.md | F1 | todo | orchestrator review | |

## Needs the other machine (from plan §7)

| Item | Status | Where verified |
|---|---|---|
| Worker deploy + KV + cron live | other-machine | HANDOFF-OTHER-MACHINE §deploy |
| Real API base in Shared.xcconfig and web/config.js | other-machine | same |
| Signing, device install | other-machine | same |
| Cellular standalone, hour-boundary rollover, 90-min/6-h flips on wrist | other-machine | device matrix |
| TestFlight upload | other-machine | same |

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
| 2026-10-21 | Relative-time bands: morning 05–11, afternoon 12–16, evening 17–22, around midnight 23–00, overnight 01–04; night belongs to the preceding day | core agent (C1) | makes Thu 00:00 peak read "around midnight" at Wed 09:00 per HANDOFF §8.1 |

## Questions for Henry (loop proceeds on the stated default)

| Date | Question | Default taken |
|---|---|---|

## Blockers

| Date | Task | What is blocked | What was tried |
|---|---|---|---|

## Screenshots index

- `docs/screenshots/web-<state>-<scheme>-1180.png` for fresh, stale, old, offline, horizon, firstrun × dark, light; `web-fresh-dark-375.png` (true 375 px via iframe). Captured 2026-10-21 from E1.
