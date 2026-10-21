# Wind Watch — build progress

Maintained by the orchestrator loop only (`docs/LOOP_PROMPT.md`). Agents report; the orchestrator
verifies, commits, and edits this file. Plan: `docs/IMPLEMENTATION_PLAN.md`.

Status legend: `todo` · `in-progress` · `done` · `blocked` · `other-machine`

Last updated: 2026-10-21 (created, nothing started)

## Tasks

| ID | Workstream | Task | Depends on | Status | Verification | Commit / notes |
|---|---|---|---|---|---|---|
| A1 | foundation | Repo hygiene: .gitignore, Local.xcconfig.example, CLAUDE.md skeleton, commit docs | — | todo | `git status` clean | |
| A2 | foundation | Toolchain: xcodegen, node PATH; confirm watchOS runtime | A1 | todo | `xcodegen --version`; `simctl list runtimes` shows watchOS 27.0 | runtime installed 2026-10-21 |
| A3 | foundation | Fixtures: Open-Meteo forecast + meta captures, payload-reference.json | A2 | todo | python loads all three, 45 hours | |
| B1 | server | Scaffold + transform.ts + tests | A3 | todo | `cd server && pnpm test` | |
| B2 | server | sun.ts civil twilight + tests | B1 | todo | `pnpm test` | |
| B3 | server | summary.ts rules + tests | B2 | todo | `pnpm test` | |
| B4 | server | index.ts fetch + scheduled, ETag/304, custom path; wrangler dev curl sequence | B3 | todo | `pnpm test`; curl 200 then 304 | |
| B5 | server | server/README.md deploy runbook | B4 | todo | commands exist in package.json | |
| C1 | core | Package.swift, Payload, Forecast, Beaufort, Compass, TrustState, derivations + tests | A3 | todo | `cd apple/WindCore && swift test` | |
| C2 | core | Twilight stops + tests | C1 | todo | `swift test` | |
| C3 | core | WindClient + AppGroupStore + tests | C2 | todo | `swift test` | |
| C4 | core | TimelineBuilder + tests | C3 | todo | `swift test` | |
| C5 | core | Glyphs, Tokens, TrustLine, WindChart, MiniStrip, previews | C4 | todo | `swift build && swift test` | |
| D1 | apps | project.yml, xcconfig, entitlements, generated .xcodeproj, build script | A2, C5 | todo | iOS sim build + watchOS generic build | |
| D2 | apps | iPhone app: Main, Location settings, About; fixture/state env; screenshots | D1 | todo | build + screenshots reviewed | |
| D3 | apps | watchOS app: Now, 12-h strip, Settings | D2 | todo | watchOS sim build + screenshots reviewed | |
| D4 | apps | Complications: provider + 4 families + previews | D3 | todo | watchOS sim build; complication on a face screenshotted | |
| D5 | apps | Custom-location sync (WatchConnectivity) + watch toggle | D4 | todo | both compiles + WindCore test | |
| E1 | web | Page in fixture mode: chart, table, states, light/dark; node tests; screenshots | A3 | todo | `node --test`; screenshots reviewed | |
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

## Questions for Henry (loop proceeds on the stated default)

| Date | Question | Default taken |
|---|---|---|

## Blockers

| Date | Task | What is blocked | What was tried |
|---|---|---|---|

## Screenshots index

(populated by D2, D3, E1 under `docs/screenshots/`)
