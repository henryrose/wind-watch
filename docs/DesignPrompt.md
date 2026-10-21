# Wind Watch — UI design kickoff prompt

Paste everything below the line into Claude Design. Attach `docs/DESIGN.md` for the
technical contract and, when available, the existing web page HTML under
`docs/reference/`.

---

I'm building **Wind Watch**, a personal app that shows the hourly HRRR wind forecast
for Port Townsend Bay, WA, for the next ~48 hours. I check it from a boat or a dock,
often in bright sun, often with wet hands, often for two seconds. I want you to
design the UI for three surfaces that share one visual system:

1. **Apple Watch** — the primary surface. Standalone over cellular. Complications on
   the watch face matter more than the app itself.
2. **iPhone** — the full hourly chart and table, plus settings.
3. **Web** — a refresh of an existing single-page HTML version so it reads as the
   same product. It will consume the same JSON payload as the apps.

Design, don't code. I'll implement the native screens in SwiftUI and Swift Charts
and the web page by hand, so every element you draw must be buildable with
ordinary bar, line, point, and rectangle marks plus system text.

## The one job

On wrist raise, answer in under two seconds: **how hard is it blowing now, how hard
are the gusts, and from which way, and is that number trustworthy.** Everything
else is secondary and must never compete with that.

## Non-negotiables

- **Numbers in knots.** Sustained and gust as integers. No decimals anywhere.
- **Beaufort-stepped colour ramp** on sustained-wind bars. Discrete steps, not a
  continuous gradient. One ramp shared by all three surfaces and the complication.
- **Gusts drawn as a line with a small tick cap above each bar.**
- **Direction arrows point where the wind blows TO.** The data gives the FROM
  direction; arrows rotate 180°. Text labels, where used, say "from SW".
- **Day/night shading** behind the chart: night fades through civil twilight into
  day, with a small sun marker at sunrise and sunset.
- **Honesty about age beats confidence.** Stale data is labelled, never silently
  shown. "As of 13:05" in amber is correct; a confident old number is a bug.
- **The chart ends where the forecast ends.** HRRR's horizon moves between ~40 and
  ~47 hours. Never pad, never fade out into invented hours. The edge is information.
- **Legible outdoors.** High contrast, large numerals, no thin weights for the
  primary number, no reliance on hue alone (Beaufort colour is reinforced by bar
  height and the number).

## Data you are designing for

The payload below is real: Port Townsend Bay, fetched 2026-10-21 09:00 PDT. Hour
index 0 is 09:00 PDT on Oct 21; the forecast ends 05:00 PDT on Oct 23 (45 hours).
Values are knots and degrees-FROM.

```
kn   [3, 4, 2, 3, 4, 3, 3, 4, 4, 4, 5, 8, 9, 11, 13, 15, 14, 14, 12, 12, 11, 10, 9, 8, 7, 7, 6, 9, 8, 6, 8, 7, 8, 7, 9, 11, 10, 11, 10, 10, 9, 9, 10, 11, 11]
gust [4, 5, 3, 3, 4, 2, 4, 5, 6, 9, 13, 15, 18, 19, 24, 25, 24, 24, 22, 21, 18, 15, 14, 12, 12, 12, 11, 16, 16, 15, 15, 14, 16, 13, 15, 22, 19, 20, 20, 20, 18, 18, 20, 21, 21]
dir  [290, 289, 313, 51, 74, 66, 11, 339, 325, 323, 301, 295, 287, 284, 282, 283, 286, 288, 288, 290, 292, 298, 297, 307, 318, 331, 346, 344, 341, 329, 328, 311, 307, 301, 283, 292, 294, 296, 294, 289, 289, 289, 292, 293, 296]
peak gust 25 kn at 00:00 Oct 22
summary "Light and variable this morning, building to 15 kn W by late afternoon, gusts to 25 overnight. Easing by dawn."
sun (approx, PDT) Oct 21: civil dawn 07:08, rise 07:40, set 18:12, civil dusk 18:44
                  Oct 22: civil dawn 07:09, rise 07:41, set 18:10, civil dusk 18:42
```

Every screen also knows: `fetched` (when the server last got new data), a run label
like "HRRR 15Z", the horizon end time, and whether the device could reach the
server on its last check.

Beaufort steps in knots, for the ramp:

| B | knots | B | knots |
|---|---|---|---|
| 0 | <1 | 6 | 22–27 |
| 1 | 1–3 | 7 | 28–33 |
| 2 | 4–6 | 8 | 34–40 |
| 3 | 7–10 | 9 | 41–47 |
| 4 | 11–16 | 10 | 48–55 |
| 5 | 17–21 | 11+ | 56+ |

Port Townsend Bay rarely exceeds Beaufort 8. Design the ramp so 2–7 are easily
distinguishable at a glance and 8+ is unmistakably alarming.

## Surfaces and screens

### Apple Watch (watchOS 26, design at 46 mm and check at 42 mm)

Priority order:

1. **Complications**, each in fresh and stale variants:
   - `accessoryRectangular`: sustained + gust + direction arrow + a six-hour mini bar
     strip in Beaufort colours, and the age/trust indicator. This is the one I'll
     look at most.
   - `accessoryCircular`: sustained large, gust small, arrow. Must survive being
     rendered tinted/monochrome by the watch face.
   - `accessoryInline`: one line of text with an SF Symbol, e.g. "↗ 12 G25 kn".
   - `accessoryCorner` (nice-to-have): a Beaufort-coloured gauge.
   Show how each looks when data is fresh, 2 h old, 8 h old, and past the horizon
   ("No forecast — open app"). Show the circular family in the tinted rendering mode.

2. **App, "Now" screen**: the first thing on launch. Big sustained number, gust,
   arrow, "from" text, the summary line, and the trust line ("as of 13:05 · HRRR
   15Z"). First paint comes from cache; there is no loading spinner, only a subtle
   "updating" state if a refresh is in flight.

3. **App, 12-hour strip**: a scrolled-down or swiped-to view with 12 hourly bars,
   gust line, arrows, day/night shading, a "now" marker, time ticks every 3 h. No
   axis labels beyond the ticks. Show how it looks when the horizon is only 6 h away.

4. **App, settings**: a single toggle "Port Townsend Bay / <custom name>", the
   attribution line "Weather data by Open-Meteo.com", and nothing else.

Watch is dark-only. Assume Liquid Glass materials where the system provides them,
but don't let glass effects reduce contrast behind the primary number.

### iPhone (iOS 26, design at 402×874 pt, light and dark)

1. **Main screen**: the 48-hour chart with the full visual language, then an hourly
   table under it (time, sustained, gust, arrow + from-direction, Beaufort
   number). Header carries location name, summary line, peak gust callout ("25 kn
   gusts around midnight"), and the trust line. Show the stale and offline variants
   of the trust line. Show the chart with a short horizon (ending at 05:00 Thu
   with the edge labelled "HRRR ends 05:00").
2. **Location settings**: default location card, one custom location with map
   search and a long-press-to-pin map. Keep the default path untouched: choosing
   the default must be one tap.
3. **About**: attribution, model/run explanation in three sentences, the ramp legend.

Dynamic Type must work up to the Large accessibility sizes on the table; the chart
may clamp.

### Web (desktop and phone widths)

Bring the existing page into the same system: same ramp, same chart grammar, same
trust line, same header. One page, no navigation. It should feel like the iPhone
main screen's sibling, not a dashboard. Light and dark via `prefers-color-scheme`.

## States to cover everywhere

| State | What the user should understand |
|---|---|
| Fresh (< 90 min) | Numbers, no caveat |
| Stale (90 min – 6 h) | Numbers plus "as of HH:MM" in amber |
| Old (> 6 h) | Numbers desaturated, "as of Tue 13:05" |
| Past horizon | No numbers; "No forecast — open app" |
| Offline but cached | "Couldn't reach server, showing data from 13:05" |
| First run, no data | "No data yet. Needs cellular or Wi-Fi once." |
| Short horizon | Chart visibly ends early with a labelled edge |
| Custom location active | Location name visible; nothing else changes |

## Deliverables

1. Screens for everything above, with the states listed, as frames I can view side
   by side.
2. A **component sheet**: the Beaufort ramp as colour tokens (light, dark, and
   watch), type scale, spacing, the arrow glyph, the tick-cap glyph, the sun marker,
   the trust-line treatment per state.
3. A **chart spec** precise enough to implement once in Swift Charts and once in
   plain SVG/Canvas: bar width and gap, gust line weight, tick-cap size, arrow size
   and placement, twilight gradient stops as fractions of the dawn→rise and
   set→dusk intervals, "now" marker, horizon edge label.
4. A short list of **things you decided and why**, and anything you'd push back on.

## Don'ts

- No weather-app clichés: no sun/cloud icons, no "feels like", no temperature.
- No maps on the watch. No login, no onboarding, no tabs.
- No continuous gradients on the bars; the ramp is stepped.
- No fake precision, no sparkline-only treatments that hide the number.
- No element on the complication that needs a tap to be useful.

## Questions I'd like you to answer back before finalising

- How do you handle a 2-digit vs 1-digit sustained number in the circular family
  without reflow?
- Where does the direction arrow live on the rectangular complication so it reads
  at a glance and doesn't look like a chart element?
- Does the rectangular mini strip earn its space at six bars, or should it be a
  single "next 6 h max gust" number?
