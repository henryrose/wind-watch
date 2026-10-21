# Wind Watch — initial design prompt

A native Apple app (iPhone + Apple Watch) showing the hourly HRRR wind forecast for
Port Townsend Bay, WA. This file is the kickoff prompt for the design phase.

---

I want to build a native Apple app — iPhone + Apple Watch — that shows the hourly
HRRR wind forecast for Port Townsend Bay, WA for roughly the next 48 hours.

Don't write app code yet. I want a technical design first.

## What it has to do

- Hourly sustained wind, gusts, and wind direction, in knots, out to ~48 hours.
- The Apple Watch app must work standalone over cellular, with no iPhone nearby.
  This is the primary surface — I check it from a boat or a dock.
- A watch face complication showing current wind + gusts is highly desirable.
- Default location is Port Townsend Bay (Open-Meteo snaps 48.09,-122.76 to grid
  point 48.116 N, 122.788 W). I want the option to set a different location, but
  it's secondary — don't let it complicate the common path.
- iPhone app shows the full hourly chart and table.

## Priorities, in order

1. **Simplicity** — few moving parts, little to maintain, easy to reason about in a
   year when I've forgotten how it works.
2. **Low latency** — the watch should show numbers almost instantly on wrist raise.
3. **Cheap to own and operate** — ideally a few dollars a month or less, not counting
   the Apple Developer membership.

I'm happy to run a small server if it buys meaningful simplicity or latency. I'm
equally happy to have no server if that's genuinely better. Make the case either way.

## Data source and what I've already learned

Open-Meteo serves HRRR free, no API key:

```
https://api.open-meteo.com/v1/forecast?latitude=48.09&longitude=-122.76&hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m&wind_speed_unit=kn&timezone=America/Los_Angeles&forecast_hours=50&models=ncep_hrrr_conus
```

Things to know:

- `wind_direction_10m` is the direction the wind blows **FROM**.
- HRRR runs hourly but only reaches 18 h on most runs. The 00/06/12/18Z runs reach
  48 h. So the usable horizon oscillates between about 40 and 47 hours depending on
  where you are in the cycle, and the tail hours come back as nulls. I verified this:
  at 15Z on 2026-10-21 the response had 46 non-null hours and then nulls.
  Decide how to handle the tail — truncate honestly, or blend in another model
  (NBM, ECMWF, GFS) and label it clearly as a different source. I lean toward
  truncating and showing the real horizon, but argue me out of it if you disagree.
- Check Open-Meteo's terms for non-commercial use and rate limits, and factor that
  into whether clients hit it directly.

## Questions to answer in the design

**Server shape.** Compare two or three concrete options — e.g. an edge function with a
cron that pre-bakes one small JSON payload; a static object in blob storage behind
a CDN; a small always-on VPS; or no server at all with clients calling Open-Meteo
directly. For each: latency to first paint on the watch, monthly cost at my usage
(one user, maybe 30 fetches a day), failure modes, and how much of it I have to
maintain. Give me a recommendation and say why.

**Payload.** If there's a server, define the exact response. It should be small enough
to land fast on cellular. Decide what gets precomputed server-side versus on-device:
Beaufort bucketing, sunrise/sunset and civil twilight, a one-line plain-English
summary, peak gust and when. Specify conditional requests, compression, and cache
headers.

**Watch refresh and the complication.** How the complication timeline gets built from
one fetch — ideally fetch once, build ~48 timeline entries, no further network until
the next refresh. Cover watchOS background refresh budget, what happens when a
refresh is skipped, and how stale data is labeled rather than silently shown.

**Freshness and failure.** HRRR re-runs hourly. What the app shows when the network is
unreachable, when the cached payload is old, and when HRRR's horizon is short. I'd
rather see "as of 2 h ago" than a confident wrong number.

**Alternate location.** How it gets set and synced. Keep the default path untouched.

**Project layout.** Targets and how code is shared between iOS, watchOS, and the widget
extension. Swift Charts on watchOS, or custom drawing.

**Cost of ownership.** Itemize it, including the Apple Developer membership and what
distribution route that implies — I'm building this for myself, so weigh TestFlight
and personal signing against App Store.

## Visual language to carry over

There's an existing web version whose look I want to keep: a Beaufort-stepped color
ramp for the sustained-wind bars, gusts drawn as a line with tick caps above each
bar, arrows showing where the wind is blowing **TO**, and day/night shading with the
night fading through civil twilight and a small sun marker at sunrise and sunset.
I'll share the HTML if useful.

## Out of scope for v1

Accounts, push alerts on gust thresholds, tides and currents, multi-day beyond the
HRRR horizon. Flag any of these if a v1 decision would paint me into a corner.

## How to proceed

Ask me any clarifying questions first. Then write the design to a markdown file:
the recommended architecture with the alternatives you rejected and why, the API
contract, the refresh model, a cost table, and a staged build plan with a thin
vertical slice first. Stop there — I'll review before any code gets written.
