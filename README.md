# wind-watch

Personal iPhone + Apple Watch app (plus a one-page web version) showing the hourly HRRR wind
forecast for Port Townsend Bay, WA. Knots, gusts, direction, honest about age.

- Start with `CLAUDE.md` for the architecture and commands.
- `docs/DESIGN.md` is the technical design, `docs/WINDWATCH-DESIGN-HANDOFF.md` the UI contract.
- `progress.md` records what was built, verified, and decided.
- `docs/HANDOFF-OTHER-MACHINE.md` is the checklist for deploying the Worker, signing, device
  tests, and TestFlight on the Mac that holds the accounts.

Status (2026-10-21): everything that can be built and verified without accounts is done and
committed: the Cloudflare Worker (79 tests, local run verified), the Swift package (116 tests),
the iPhone app, the watch app, the complications, custom-location sync (all in simulators), and
the web page (22 tests, live and offline modes). Screenshots are under `docs/screenshots/`.
