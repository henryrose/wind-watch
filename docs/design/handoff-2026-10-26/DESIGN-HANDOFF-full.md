# Wind Watch — design handoff for implementation

Scope: Apple Watch (watchOS 26, complications + app), iPhone (iOS 26), and a single-page web refresh. All three consume the same JSON payload. This document is the implementation contract; the design canvas ("Wind Watch" in Claude Design) is the visual reference. Where this doc and the canvas disagree, this doc wins.

Target stack: SwiftUI + Swift Charts for watch and phone; plain HTML/CSS/JS with inline SVG (or Canvas) for web. Every element below is a bar, line, rule, point, rectangle, or system text.

---

## 1. The one job

On wrist raise, in under two seconds: sustained wind now, gust now, direction (where it blows TO), and whether the number can be trusted. Nothing may compete with these four.

Hard rules (non-negotiable, from the brief):

- Knots only. Sustained and gust are integers. No decimals anywhere in the UI.
- Beaufort-stepped colour on sustained bars. Discrete steps. One ramp everywhere.
- Gusts: a line joining per-hour gust values, with a short horizontal tick cap over each bar.
- Arrows point TO. `rotation = fromDegrees + 180`. Text says "from W".
- Day/night shading behind every chart, twilight ramped linearly, sun dot at sunrise/sunset.
- Stale data is always labelled. A confident old number is a bug.
- Chart ends where the forecast ends. Never pad, never fade.
- Legible outdoors: no weight lighter than Semibold on any wind number; colour never carries meaning alone.
- No sun/cloud icons, no temperature, no "feels like", no maps on watch, no tabs, no login, no onboarding, nothing on a complication that needs a tap.

---

## 2. Data contract (what the UI assumes)

```
payload {
  location: { name: String, lat: Double, lon: Double, isDefault: Bool }
  run:      String          // e.g. "HRRR 15Z"
  fetched:  Date            // when the SERVER last got new model data
  start:    Date            // hour index 0, local time
  horizon:  Date            // last forecast hour (inclusive)
  hours:    [ { kn: Int, gust: Int, dirFrom: Int } ]   // 1-hour steps from `start`
  sun:      [ { date: LocalDate, civilDawn, sunrise, sunset, civilDusk: Time } ]
  summary:  String          // one sentence, ≤ 110 chars
  peakGust: { kn: Int, at: Date }
}
device-side: lastCheckSucceeded: Bool, lastCheckAt: Date, cachedAt: Date
```

Derived on device:

- `nowIndex` = fractional hours between `start` and now (may be negative before `start`; clamp to 0 for the hero, never for the chart).
- `hero` = `hours[floor(nowIndex)]`; if `nowIndex > horizon` → **Past horizon** state.
- `age` = now − `fetched`.

### Beaufort (sustained knots → step)

```
B0–1: kn <= 3       B2: 4–6       B3: 7–10      B4: 11–16     B5: 17–21
B6: 22–27           B7: 28–33     B8: 34–40     B9: 41–47     B10+: 48+
```

B0 and B1 share a colour (`bft.calm`); B10, B11, B12 share `bft.10`.

### Compass label (8-point)

`["N","NE","E","SE","S","SW","W","NW"][Int((dirFrom + 22.5) / 45) % 8]`. Label text is always `"from \(label)"`. Inline complication arrow uses the same 8 points (it cannot rotate an image).

### Twilight / shading fraction

For each hour-axis position `t` (fractional hours since `start`):

```
day(t) = 1 inside [sunrise, sunset]
       = 0 inside [civilDusk, nextCivilDawn]
       = linear 0→1 across [civilDawn, sunrise]
       = linear 1→0 across [sunset, civilDusk]
```

Emit gradient stops at exactly those four times per day, as fractions of the plotted hour range; hold the value flat outside. Sun dots at `sunrise` and `sunset` only (not dawn/dusk).

---

## 3. Trust states (shared by every surface)

| State | Condition | Treatment |
|---|---|---|
| Fresh | age < 90 min, last check OK | Trust line in `ink.secondary`: `as of HH:MM · HRRR 15Z` |
| Stale | 90 min ≤ age < 6 h | Trust line in `trust.amber`, Semibold. Numbers untouched. |
| Old | age ≥ 6 h | Trust line amber with day name: `as of Tue 13:05 · HRRR 15Z`. All wind numbers and arrows drop to `ink.old` (72 %). Charts: `saturation 0.35, opacity 0.7`. |
| Past horizon | now > horizon | No numbers. Hero shows `—`. Text: `No forecast — open app` (complications) / `No forecast · last run HRRR 15Z Tue` (app). |
| Offline, cached | last check failed, cache exists | Trust line amber with `wifi.slash` glyph: `Couldn't reach server · showing data from 13:05`. The reason replaces the run label. Age rules above still apply to the numbers. |
| First run | no cache | Hero `—`, body: `No data yet. Needs cellular or Wi-Fi once.` Footer: spinner + `trying…`. The only screen allowed a spinner. |
| Updating | refresh in flight over a cache | Trust line gets a 14 px activity ring + `updating · as of 09:00`. Never a spinner over numbers. First paint always from cache. |
| Short horizon | horizon − now < 12 h | Chart edge label; watch strip keeps 12 slots and leaves the tail empty; phone/web plot stops at the edge. |
| Custom location | `isDefault == false` | Only the location name changes. Nothing else. |

Small-slot rule (circular, corner): no room for text, so the Beaufort ring/gauge turns **amber and dashed** (`dash 7/6`) for Stale and Old. Dashing is what survives tinted rendering.

Inline rule: single colour on most faces, so the words carry it: `15 G25 kn · 13:05` (stale), `15 G25 kn · Tue 13:05` (old), `Wind — open app` (past horizon).

---

## 4. Tokens

### 4.1 Beaufort ramp (Asset Catalog colour set names in `code`)

| Step | Dark / Watch | Light | Name |
|---|---|---|---|
| 0–1 | `#5C6B7A` | `#8A97A6` | `bft.calm` |
| 2 | `#4FA3D8` | `#2A86C4` | `bft.2` |
| 3 | `#3FC2A0` | `#1E9E80` | `bft.3` |
| 4 | `#8DD44A` | `#5FA82E` | `bft.4` |
| 5 | `#F2D13D` | `#C9A800` | `bft.5` |
| 6 | `#F59A2B` | `#E07F12` | `bft.6` |
| 7 | `#EC5A2A` | `#D6451A` | `bft.7` |
| 8 | `#E0245E` | `#C7154B` | `bft.8` |
| 9 | `#A32CD1` | `#8C1FB3` | `bft.9` |
| 10+ | `#F5F5F7` + 2 pt inset stroke `bft.8` | `#1B1B1F` + 2 pt inset stroke `bft.8` | `bft.10` |

Watch uses the dark column. Lightness rises with step so the ramp survives greyscale; 8+ changes hue family on purpose. Tinted complications drop the ramp entirely.

### 4.2 Ground and ink

| Token | Dark | Light | Use |
|---|---|---|---|
| `ground.watch` | `#000000` | — | watch app background |
| `ground` | `#0B0E12` | `#F4F5F7` | phone/web page |
| `card` | `#171C23` | `#FFFFFF` | chart card, settings cards, chips |
| `hairline` | `#2A2F36` | `#D9DDE3` | table rules |
| `ink.primary` | `#FFFFFF` | `#0B0E12` | numbers, titles |
| `ink.body` | `#C7CED8` | `#3A414B` | summary text |
| `ink.secondary` | `#9AA4B1` | `#5F6975` | labels, fresh trust line |
| `ink.old` | `#B8BEC7` | `#7A8390` | numbers in Old state |
| `ink.disabled` | `#5C6B7A` | `#A0A8B2` | `—` placeholder |
| `trust.amber` | `#FFB340` | `#B86E00` | stale/old/offline trust line, sun dots use dark value on both |
| `sun` | `#FFB340` | `#E08A00` | sun markers |
| `complication.plate` | `rgba(255,255,255,0.10)` | — | rectangular/circular background |

Contrast: every text/ground pair above meets 4.5:1 (secondary on dark ground = 7.1:1; amber on dark = 9.9:1; `#B86E00` on `#F4F5F7` = 4.6:1).

### 4.3 Type

Numerals: **SF Pro Rounded**, `.monospacedDigit()`, never below Semibold. Words: SF Pro Text. Web: `-apple-system, system-ui, "Segoe UI", Roboto, sans-serif` with `font-variant-numeric: tabular-nums`.

| Role | Watch (pt) | iPhone (pt) | Web (px) |
|---|---|---|---|
| Hero sustained | Rounded Heavy 84, tracking −3 % | Rounded Heavy 72 | 72 |
| Hero unit "kn" | Semibold 18, secondary | Semibold 20 | 20 |
| Gust `G 25` | Rounded Bold 27 ("G" Semibold 16 secondary) | Rounded Bold 26 ("G" 17) | 26 |
| Direction `from W` | Text Semibold 18 | Semibold 17 | 17 |
| Summary | Text Regular 13, `ink.body`, 2 lines max on watch | 15 | 16 |
| Trust line | Text Medium 12 (Semibold when amber) | 13 | 14 |
| Location name | Text Semibold 11, secondary | Bold 28 | 32 |
| Axis ticks | Rounded Semibold 11 | 11 | 12 |
| Table row | — | 17 body, 12 header | 15 / 12 |
| Complication primary | Rounded Heavy 30 (rect) / 18 (circular) | — | — |
| Complication gust | Rounded Bold 15 (rect) / 8 (circular) | — | — |

Watch values above are points; the canvas draws watch at 2× pixels (46 mm = 416×496 px).

Dynamic Type: phone table supports up to AX5. From AX1 the row reflows to two lines: line 1 `Thu 00:00` + Beaufort chip; line 2 `15 kn  G 25  ▸ W`. The chart clamps at 152 pt height and its text does not scale.

### 4.4 Spacing

4-pt grid. Watch edge inset 10 pt; phone 16 pt; web gutter 24 pt, content max-width 1180. Card radius 14 (phone), 10 (web), 13 (complication plates, i.e. 26 px). Hit targets ≥ 44 pt.

Hero stack rhythm (watch Now, top to bottom): location → 2 → number row (number, "kn" baseline-aligned; gust + Beaufort pill right-aligned) → 5 → direction row → 9 → summary → flexible space → trust line.

---

## 5. Glyphs (geometry, all drawable as paths)

**Arrow (direction, points TO).** Kite in a unit box: `M0,-0.5 L0.38,0.5 L0,0.2 L-0.38,0.5 Z`, scaled to size `s` and rotated `dirFrom + 180` about its centre. Fill = current ink. Sizes: chart 9 pt (phone/web), 14 px watch strip, 18 pt hero row (phone), 18 pt watch hero, 11 pt rectangular text row, 7 px circular.

**Tick cap (gust).** Horizontal line, width = bar width + 2, stroke = gust-line stroke, round caps, centred on the bar at the gust value. The gust line is a polyline through cap centres, 75 % ink; caps are 100 % ink.

**Sun markers.** On the plot's top edge (`y = plotTop − 1`): **sunrise = filled circle** r 3 pt (5 px watch), `sun`; **sunset = ring** r 2.25 pt (4.25 px watch), 1.5 pt stroke, no fill, same colour. "On after it rises, off after it sets." Swift Charts: `PointMark` with `.symbol(.circle)` filled vs `.symbol(Circle().stroke(lineWidth: 1.5))`. Applies to every chart including the Smart Stack strip; the rectangular complication strip has no sun markers.

**Now marker.** Rule 1.5 pt, 100 % ink, from `plotTop − 6` to `plotBottom`, at `x(nowIndex)`. Label `now` Semibold, left-aligned 4 pt right of the rule at `plotTop − 8`.

**Horizon edge.** Rule 1 pt, dash 3/3, 70 % ink, at `x(lastHour + 1)`. Label `HRRR ends 05:00` Semibold 70 %, right-aligned 4 pt left of the rule at `plotTop − 8`. If the edge is within 12 slots of the now marker, drop "HRRR " to avoid collision.

**Beaufort pill (hero).** 48×6 pt (phone/web), 36×5 pt watch, radius = half height, filled with the hero's step colour. Sits under the gust number, right-aligned. In Old state apply the chart desaturation.

**Beaufort chip (table).** 24-wide min, 2 pt vertical padding, radius 6, step colour fill, black Semibold 13 label with the step number.

**wifi.slash.** Use the SF Symbol on Apple platforms; the web uses the inline path drawn in the canvas (two arcs, dot, diagonal).

---

## 6. Chart spec

Swift Charts marks: `RectangleMark` (day shading, full plot height, x-range per gradient segment or one mark with a horizontal gradient), `BarMark` (sustained), `LineMark` + `RuleMark` per hour (gust line + caps), `PointMark` (sun), `RuleMark` (now, horizon), annotations for arrows (a rotated `Image` or `Path` in `.annotation(position: .bottom)`), and `AxisMarks` for ticks.

### 6.1 Shared geometry

| Property | Watch 12-h strip (px @2×) | iPhone (pt) | Web (px) |
|---|---|---|---|
| Hours plotted | 12-slot window from `floor(nowIndex)` | all remaining (≤ 48) | all |
| Plot width | 396 | 370 | fluid, ≤ 1120 |
| Plot height | 184 | 152 | 230 (≥ 900 px wide) / 162 |
| Inset top / bottom | 24 / 22 | 22 / 16 | 28 / 22 |
| Slot = plotWidth ÷ slots | 33 | 8.2 | 24.9 at 1120 |
| Bar width | 0.72 × slot, min 3 | same | same |
| Bar corner radius | 2 | 1.5 | 1.5 |
| Gust line stroke / opacity | 2.5 / 75 % | 1.5 / 75 % | 1.5 / 75 % |
| Tick cap | (bar + 2) × 2.5 | (bar + 2) × 1.5 | (bar + 2) × 1.5 |
| Arrow size / cadence | 14 / every hour | 9 / every 3 h | 10 / every hour ≥ 900 px, else every 3 h |
| Arrow row centre y | plotBottom + bottomInset ÷ 2 | same | same |
| Time ticks | every 3 h, 1 px 50 %, 3 tall | every 6 h | every 3 h |
| Tick labels | `HH` Rounded Semibold 22 px 60 %, no day | `HH` 11 pt | `HH` 12 px + day name at 00:00 |
| Y domain | `0 … max(20, ceil((maxGust + 3) / 10) × 10)` | same | same |
| Gridlines | every 10 kn, 1 px 12 % ink; label right-aligned 10–11 pt 45 % | same | same |
| Day shade (dark) | white 7 % day, 0 % night | same | same |
| Day shade (light) | — | black 0 % day, 8 % night | same |
| Sun dot | r 5 | r 3 | r 3 |
| Now marker | 1.5 px | 1.5 pt | 1.5 px |
| Horizon edge | 1 px dash 3/3 70 % | same | same |

Y domain is computed over the hours actually plotted. Bars sit on the plot baseline; nothing is drawn at 0 kn beyond a 1 pt stub.

### 6.2 Twilight stops for the reference payload

Hour index 0 = Wed 21 Oct 09:00 PDT, 45 points, horizon index 44 (Fri 05:00).

| Event | Index | Fraction of 45-h range |
|---|---|---|
| sunset Wed 18:12 | 9.20 | 0.2044 |
| civil dusk 18:44 | 9.73 | 0.2163 |
| civil dawn Thu 07:08 | 22.13 | 0.4918 |
| sunrise 07:40 | 22.67 | 0.5037 |
| sunset Thu 18:10 | 33.17 | 0.7370 |
| civil dusk 18:42 | 33.70 | 0.7489 |

Chart starts in day (1.0) and ends in night (0.0). Fri dawn (index ~46.1) is past the horizon and is not drawn.

### 6.3 Complication strip (rectangular, Smart Stack)

**Next 12 hours** from the current hour, full plate width. Rectangular: 168×31 pt (336×62 px @2×), slot 14 pt, bar 0.72 slot. Smart Stack: 184×37 pt with 3-hourly labels `12am · 3am · 6am · 9am` (8 pt). **Y domain = max(20 kn, window max gust rounded up to 5), and it only grows within a forecast run** — never shrinks between timeline entries, so bars don't swell as a peak scrolls out of the window; it resets on a new HRRR run. Gust line + caps 1 pt (2 px), caps bar + 1. 0.5 pt ticks every 3 h under the baseline. **Rectangular strip has no night shading and no sun dot** (invisible at 7 % on the plate); the Smart Stack keeps both. **No arrows, no gridlines, no axis labels on the rectangular.** Past-horizon slots stay empty; Old state: `saturation 0.35, opacity 0.7`.

### 6.4 Hour selection (scrub) — iPhone and web

The chart is the centrepiece of the iPhone main screen: full-bleed card, plot 250 pt tall (insets 26 / 18), title row `Hourly · to Fri 05:00` left and a hint right (`touch a bar for that hour`). Header title drops to Bold 22 and the hero to 60 so they don't compete.

Interaction: touch or drag anywhere on the plot.

- The first day label is suppressed when the `now` marker sits at the plot start (the readout already names the day); the first tick label is likewise dropped at the plot edge.
- Selected hour = `round(proxy.value(atX:))` (Swift Charts `chartOverlay` + `DragGesture(minimumDistance: 0)`); web: `pointermove` over the SVG, `floor((x − plotLeft) / slot)`.
- Selected bar: 1.5 pt white outline (radius 2.5), full plot-height white rule 1.5 pt through the slot centre (from `plotTop − 6` to the arrow row). All other bars `opacity 0.45`; gust line, caps, arrows, shading untouched.
- The now-readout row swaps to the selected hour: a `Thu 00:00` label with a 2 pt white bar glyph, hero `15 kn`, `G 25`, arrow + `from W · 283°`, Beaufort chip `4`, and `now 3 kn` kept small (Medium 12 secondary) on the right as the anchor. Row gets `card` fill, radius 12, 1.5 pt white inset stroke.
- Hint text changes to `release to return to now`.
- Release → snaps back to now immediately. No sticky selection, so a glance never shows an hour that isn't now. `UIImpactFeedbackGenerator(.light)` on each hour change; VoiceOver: chart is an adjustable element, swipe up/down steps hours and reads `"Thursday 00:00, 15 knots gusting 25 from the west, Beaufort 4"`.
- Watch strip: no scrub (Digital Crown already pages; a 2-second glance should never land on a selected hour).

### 6.4a Time labelling (iPhone and web, after review)

- Day band above the plot: day name (Semibold, 75 % ink) at the left edge for the first day, then at each midnight; a dotted 1 pt divider (dash 2/3, 28 % ink) drops from the day name through the full plot height at 00:00.
- Tick labels are 12-hour with am/pm: every 6 h on the iPhone portrait chart (`9am · 3pm · 9pm · 3am`), every 3 h on landscape and web (`9am · noon · 3pm · 6pm · 9pm · 12am · 3am · 6am`).
- Chart title `Wed 9am → Fri 5am`; edge label `ends Fri 5am`; header `… ends Fri 5am`. The scrub/tooltip hour label reads `Thu 12am · midnight` (and `Thu 12pm · noon`).
- Table rows and the trust line stay 24-hour (`as of 13:05`).
- Top inset grows to 38 pt (portrait) / 40 (web) to make room for the day band above the now/edge labels.

### 6.4b iPhone landscape

Same `Chart` view, switched on `verticalSizeClass == .compact`. Table, summary and peak chip are hidden; the chart fills everything under one 48 pt header line (location + trust line left; readout right — the now numbers, or the touched hour while a finger is down). Plot 756×236 pt inside safe areas (59 pt each side). Arrows every hour, labels every 3 h. Hint bottom-right: `release to return to now · rotate back for the table`. Scrub rules identical to portrait.

### 6.4c Web hover / touch

One `pointermove` listener on the SVG; `hour = floor((x − plotLeft) / slot)`. Highlight = white 1.5 px outline on the bar + full-height rule; other bars `opacity 0.45`. Tooltip card: dark ground, white 1.5 px ring, radius 10, anchored to the slot centre 4 px below the day band; content `Thu 12am · midnight · 15 kn · G 25 · ▸ from W · 283° · [B4]`. Flip to the left of the rule within 160 px of the right edge. `pointerleave` clears. On touch (narrow widths) the card docks to the top of the chart card. SVG is focusable; ←/→ step the hour; the card text lives in an `aria-live="polite"` region.

### 6.4d Second-round refinements (supersede anything above that conflicts)

- **Readout row has a fixed height.** iPhone portrait: 96 pt, `card` fill, radius 12, horizontal margin 12. Both states render the same structure — a 13 pt label line (`Now · Wed 9:25am` with a blue 2 pt bar, or `Thu 12am · midnight` with a white bar), the number (56 pt) in a 124 pt column, `G 4` over arrow + `from W` (+ `283°` Medium 13 secondary while scrubbing), right column = `peak G25 · 12am` (now) or `now 3 kn` (scrubbing), Medium 12 secondary, over the Beaufort chip (number only, no word). Degrees appear only in the scrub state and in the table. Scrubbing only adds a 1.5 pt white inset ring. Nothing above the chart may change height while a finger is down; use `.frame(height: 96)` and never let text reflow (single-line, `.lineLimit(1)`, `.minimumScaleFactor(0.85)`). Landscape: 48 pt, same rule.
- **Chart is edge to edge.** Portrait plot width = screen width (402 on the reference device): no horizontal padding on the chart card; the y-axis labels and the `now`/edge labels are drawn inside the plot. `.ignoresSafeArea(.container, edges: .horizontal)` on the chart only; the title row above it keeps the 16 pt inset. Landscape: plot width = screen width − 40 (20 pt each side) — 834 on the reference device — so the first and last hour are not under the Dynamic Island; everything else ignores the side safe areas.
- **Hourly table is collapsible, collapsed by default.** iPhone: a 52 pt disclosure row under the summary (`Hourly table` Semibold 17 · `45 hours · Wed 9am → Fri 5am` 13 secondary · chevron), `card` fill, radius 12; tapping expands the table in place with the standard spring; state persists in `@AppStorage("hourlyTableExpanded")`. At AX sizes the row is 60 pt. Web: a `<details>` with a styled `<summary>` of the same content; closed by default, state remembered in `localStorage`; `prefers-reduced-motion` disables the height animation.
- **Watch: the 12-hour strip is the launch screen.** Page order is strip → Now detail → (Crown/long-press) Settings. The strip's header carries the compact hero so the one job still lands on wrist raise: `3 kn · G 4 · ▸ from W` (Rounded Heavy 32 / Bold 17 / Semibold 13) with a secondary line `Port Townsend Bay · next 12 h · gusts to 15`. The Now detail page keeps the big number, summary and full trust line. Page dots: strip is dot 1.

### 6.5 Web implementation notes

One `<svg viewBox="0 0 W H">` scaled to 100 % width; recompute `W` at two breakpoints (≥ 900 px: 1120×280, else 358×200) so stroke weights stay in CSS px. Shading is a single `<rect>` with a horizontal `<linearGradient>` whose stops come from §2. `prefers-color-scheme` swaps the token columns in §4; nothing else changes.

---

## 7. Apple Watch

Design at 46 mm (208×248 pt), verify at 42 mm (187×223 pt). Dark only. Liquid Glass may be used for the settings buttons and page indicator; never behind the hero number (keep the hero on solid `ground.watch`).

### 7.1 Complications (WidgetKit accessory families)

**accessoryRectangular** — the primary target. 184×72 pt. Plate `complication.plate`, radius 13, padding 6/8/5/8.

- Row 1 (25 pt, one line, no wrap): sustained Rounded Heavy 23 · `G25` Rounded Bold 11 at 90 % ink · arrow 9 pt + `from W` Semibold 9 · flexible space · **trust text Medium 11 pt, never smaller** (`as of 23:30`; Semibold amber `as of 13:05` when stale; `Tue 13:05` amber when old). No `kn` (same as the circular).
- **When row 1 doesn't fit** (`ViewThatFits`, in order): drop `from W` and keep the bare arrow → drop the `G` prefix → shrink the number to 20 pt. The trust text is never removed or shrunk. On 41/42 mm (plate ≈ 166×65 pt) the first fallback is the normal state — see the 42 mm cards on the canvas.
- Row 2: the 12-hour strip, full plate width (§6.3), 3 pt below row 1.
- Old: numbers and arrow `ink.old`, strip desaturated.
- Past horizon: row 1 = `—` in `ink.disabled` + `No forecast` Bold 12 secondary + `15Z Tue` right; row 2 becomes a 1 pt dashed rounded box with `Open app to refresh` Semibold 10 centred.
- No location name. Never. (The Smart Stack widget adds location + run label in a footer.)

**accessoryCircular** — 52×52 pt.

- Beaufort ring: track `rgba(255,255,255,0.18)`, 3 pt; value arc = step colour, 3 pt, round caps, from 12 o'clock, length = `B / 12` of the circumference.
- Arrow 7 pt at (centre, 10.5 pt from top), ink.
- Sustained Rounded Heavy 18, centred in a **fixed 22×17 pt frame** (two tabular digits). The frame, not the glyphs, positions everything; `8` and `15` never move the arrow or gust. Cap at 99.
- Gust `G25` Rounded Bold 8, 85 % ink, 3.5 pt from bottom. No `kn`.
- Stale/Old: ring becomes amber, dash 7/6; Old also 72 % ink. Past horizon: no ring value, `—` + `open app` (Bold 6.5).
- `widgetAccentable()` the ring and arrow; numbers stay primary so tint can't hide them. Tinted Old = 60 % tint ink.

**accessoryInline** — `Image(systemName: arrow8) + Text`. Text Rounded Semibold: `15 G25 kn`; stale `15 G25 kn · 13:05`; old `15 G25 kn · Tue 13:05`; past horizon `Wind — open app` with `wind` symbol. Snap arrow to 8 points (`arrow.up`, `arrow.up.right`, … ) using the TO bearing.

**accessoryCorner** — nice-to-have. Inner label: sustained Rounded Heavy 20 over arrow 8 pt over `G25` Bold 9. Outer gauge (`widgetLabel` with a `Gauge`): 8 equal stepped segments for B0–7 in ramp colours, 3.5 pt; white 3 pt dot at the current value. B8+ pins the dot at the end — that is the alarm. Stale/Old: gauge becomes a single amber dashed arc. Past horizon: empty track, `—`, `open app`.

**Smart Stack widget** (optional, `accessoryRectangular`-sized system widget): same content as rectangular; strip full width; adds `Port Townsend Bay` left and `as of 23:30 · HRRR 05Z` right in the footer. Relevance: `sustained ≥ 10 || next6hMaxGust ≥ 18`.

Timeline: one entry per hour boundary plus entries at `fetched + 90 min` and `fetched + 6 h` to flip trust state without a refresh.

### 7.2 App — Now (launch screen)

Vertical stack, insets 22 pt top (clock), 12 pt sides, 14 pt bottom:

1. Location — Semibold 11 secondary.
2. Hero row — sustained Rounded Heavy 84 (tracking −3 %) with `kn` Semibold 18 secondary baseline-aligned 5 pt right; right-aligned column: `G 25` Rounded Bold 27 and the Beaufort pill 36×5 under it.
3. Direction row — arrow 18 + `from W` Semibold 18, 5 pt gap.
4. Summary — Regular 13 `ink.body`, 2 lines, truncate tail (3 lines on 46 mm if room).
5. Spacer.
6. Trust line — Medium 12 secondary / Semibold amber per §3. Offline: `wifi.slash` + two-line reason; summary is dropped to make room.

First paint from cache, synchronously. No spinner except First run. Digital Crown / swipe left → 12-h strip. Long-press or Crown-scroll past the strip → Settings. Vertical page style with 2 dots.

### 7.3 App — 12-hour strip

Header: `Next 12 h` Rounded Bold 13 left; `gusts to 15` Semibold 11 secondary right (window max gust). Chart per §6.1, 198×115 pt. Footer: trust line left, page dots right. Short horizon: header says `Next 6 h`; axis keeps 12 slots; edge label `ends 05:00`.

### 7.4 App — Settings

Title `Location`. Two full-width buttons (44 pt min, radius 12, plates 14 % / 8 % white): default `Port Townsend Bay · default` with filled check; custom `<name> · set on iPhone` with empty ring. Footer `Weather data by Open-Meteo.com` Regular 10 secondary. Nothing else.

---

## 8. iPhone (402×874 pt reference)

### 8.1 Main

Top inset 62 (large-title region not used; custom header). Vertical stack, gap 14, side inset 16:

1. Header — `Port Townsend Bay` Bold 28; trust line 13 under it (`as of 09:00 · HRRR 15Z · ends Fri 05:00`); 44 pt gear button right → Location settings.
2. Now block — hero 72 + `kn` 20; right of it `G 4` Rounded Bold 26 over arrow 18 + `from W` Semibold 17; far right a peak-gust chip (`card` fill, radius 999, 13 Semibold, leading 10 pt dot in the peak's Beaufort colour: `25 kn gusts around midnight`) over the Beaufort pill 48×6.
3. Summary — Regular 15 `ink.body`.
4. Chart card — `card`, radius 14, padding 10/0/12; chart 370×190 incl. insets per §6.1.
5. Table — columns `56 | 56 | 56 | 1fr | 36`: hour (secondary), sustained (Rounded Bold 17), gust (`ink.body`), arrow 14 + compass, Beaufort chip. Row height 44, hairline `card`. Header row 12 Semibold secondary with the day name in the first column; day changes get a sticky day header. Scrolls with the page.

Peak-gust chip text: `"\(peak.kn) kn gusts \(relativeTimePhrase)"` where phrase ∈ {`this morning`, `this afternoon`, `this evening`, `around midnight`, `overnight`, `tomorrow morning`, …}.

### 8.2 Trust-line variants (same header, see canvas "iPhone · header trust-line states")

Stale → amber Semibold; Old → amber + day name, numbers `ink.old`, pill desaturated; Offline → `wifi.slash` + `Couldn't reach server · showing data from 13:05`; Custom location → name only.

### 8.3 Locations

Back chevron + `Locations` Bold 28, counter right (`5 of 12`, 13 Semibold secondary; `12 of 12 · full` in `ink.body`). One list of **up to 12 locations, all equal**: Port Townsend Bay is seeded on first launch as row 1 but is an ordinary row — renamable, reorderable, deletable. Rows (52 pt; 44 pt in Edit mode): selection ring/check · name Semibold 16 · coords 12 secondary. Tap a row to switch; swipe left to delete; **Edit** (nav bar, always present, standard `EditButton`) shows the minus buttons and drag handles for delete and reorder. **The selected location drives every surface** (hero, chart, complications, web); list order carries no meaning beyond order. A fresh install seeds Port Townsend Bay as the only row and selects it. **The last remaining location cannot be deleted** (no swipe action, no minus button) so the watch never has nothing to show. Under the list: search field (44 pt, `Search a place or paste lat, lon`) and a 250 pt map with every location pinned (selected = blue, others white) and a `Long-press the map to add a location` pill; new pins snap to the nearest 3 km HRRR cell and prompt for a name.

**Naming.** Every row has a trailing ⓘ (44 pt) that opens the location sheet. The same sheet appears after a map long-press or a search pick, titled `New Location`: a NAME field pre-filled with the reverse-geocoded suggestion, focused with the text selected so typing replaces it; a hint `Suggested from the map. Change it to what you call this spot; your name is never overwritten.`; a map thumbnail showing the pin and the 3 km HRRR cell it resolves to; POSITION and FORECAST POINT tiles; suggestion chips (the geocoder's other nearby names, tap to fill); `Save`. For an existing location the sheet is titled with its name, the primary button is `Done`, and a `Delete Location` button sits at the bottom (hidden for the last remaining location). Rules: the user's name is stored verbatim and never re-geocoded; renaming never moves the pin; Save requires a non-empty name; a duplicate gets a ` 2` suffix suggested, not blocked; names show on the watch and complications after the next refresh. Max 40 characters; the hero header truncates with an ellipsis past ~22 at default type.

**When the list is full (12 of 12):** opening Locations lands in Edit mode (nav button reads `Done`), with a banner `List full (12). Delete one to add a new pin.` above the list. Minus buttons use the standard two-tap pattern (minus → row-level `Delete` confirm pill with a 10 % red tint). The map stays live for viewing; a long-press shows a centred toast `List full — delete a location first` instead of adding. Watch settings shows the same list in the same order, Crown-scrolled.

### 8.4 About

Three cards: model explanation (three sentences, text in canvas), Beaufort legend (step, swatch, knots range + gust/arrow caption), attribution `Weather data by Open-Meteo.com · CC BY 4.0` + version line.

---

## 9. Web

One page, no navigation. `max-width: 1180px`, gutters 24 px (16 px under 600 px). Header: h1 32 + trust line 14; right cluster = hero 72 + gust/direction + peak chip + pill (wraps under 700 px). Summary 16. Chart card `card` radius 10, padding 16/28/20, plus a legend row (ramp swatches 12 px, gust glyph, arrow "blowing to", sun dot). Table: semantic `<table>`, `overflow-x: auto` wrapper, 15 px body, same five columns, Beaufort chips. Footer: attribution + `times in PDT`. Light/dark via `prefers-color-scheme` using §4 columns; amber is `#B86E00` in light.

---

## 10. Reference payload (for previews and tests)

```
start   2026-10-21T09:00-07:00    horizon 2026-10-23T05:00-07:00   run "HRRR 15Z"
kn   [3,4,2,3,4,3,3,4,4,4,5,8,9,11,13,15,14,14,12,12,11,10,9,8,7,7,6,9,8,6,8,7,8,7,9,11,10,11,10,10,9,9,10,11,11]
gust [4,5,3,3,4,2,4,5,6,9,13,15,18,19,24,25,24,24,22,21,18,15,14,12,12,12,11,16,16,15,15,14,16,13,15,22,19,20,20,20,18,18,20,21,21]
dir  [290,289,313,51,74,66,11,339,325,323,301,295,287,284,282,283,286,288,288,290,292,298,297,307,318,331,346,344,341,329,328,311,307,301,283,292,294,296,294,289,289,289,292,293,296]
peak 25 kn at 2026-10-22T00:00-07:00
sun  Oct 21: dawn 07:08 rise 07:40 set 18:12 dusk 18:44 · Oct 22: 07:09 07:41 18:10 18:42
summary "Light and variable this morning, building to 15 kn W by late afternoon, gusts to 25 overnight. Easing by dawn."
```

Expected derived values: hour 0 → `3 kn G4 from W`, B1, arrow rotation 110°. Hour 15 → `15 kn G25 from W`, B4, rotation 103°. Y domain 0–30. Horizon label `HRRR ends 05:00`.

---

## 10a. Brand

**App icon — "Wake" (icon B·3).** A white TO-arrow at 103° (a westerly) trailing three short streaks in `bft.2` / `bft.3` / `bft.4`, on a `#0B0E12` tile. One source of truth: `reference/brand_icon.py` (`icon(size, round_, mono)`), which picks the size tier automatically.

| Tier | Sizes | Streaks | Stroke (180 grid) | Arrow half-height | Glyph centre (180 grid) |
|---|---|---|---|---|---|
| full | ≥ 48 pt | B2 / B3 / B4, middle longest | 11 | 46 | (115.2, 101.8) |
| small | 24–47 pt | B2 / B4 | 18 | 50 | (116.8, 102.2) |
| tiny | < 24 pt | B3 only | 26 | 54 | (117, 103.1) |

Everything rotates 103° about the glyph centre; kite path `M0,-s L0.75s,s L0,0.4s L-0.75s,s Z`; streaks are round-capped lines along the arrow's axis behind the tail. The glyph's bounding box sits 1 pt below the tile centre (optical).

Icon Composer layers (iOS 26 / watchOS 26): ground `#0B0E12` → wake (one layer per streak, so tinted mode steps their luminance) → arrow `#FFFFFF`. Glass/specular on the arrow layer only. The ground stays dark in light mode. Watch icon = the same art clipped to a circle. Export the 1024 master from `brand_icon.py` at full tier; Xcode generates the rest, but **ship explicit small/tiny-tier PNGs for 29/40 pt slots and the 16/32 favicons** so the streak count changes as designed.

**Wordmark.** "Wind Watch" in SF Pro Rounded: "Wind" Heavy in `ink.primary`, " Watch" Medium in `ink.secondary`, tracking −3 %. Two words, title case. On the web use the system stack (`-apple-system, system-ui, …`) — no web font. Lockup = icon tile + wordmark, gap ≈ 0.4 × type size.

**Where the name appears — and nowhere else:**

- iPhone main (portrait): 15 pt eyebrow lockup (17 pt tile, tiny tier) above the location name. Not in landscape.
- iPhone About: lockup replaces the "About" title — 30 pt tile + 26 pt wordmark + "1.0".
- Web: a lockup row above the header (28 pt tile + 26 pt wordmark desktop; 24/22 phone) with "HRRR wind · Port Townsend Bay, WA" right-aligned at 12 px `ink.disabled`; `<title>` = "Wind Watch — Port Townsend Bay"; favicon 16/32 tiny tier, apple-touch-icon 180 full tier.
- Footers (iPhone main, web): "Wind Watch · weather data by Open-Meteo.com".
- Watch: settings footer only — 24 pt round icon + "Wind Watch 1.0" over the attribution. The strip and Now pages carry no brand. Inline complication past-horizon text stays "Wind — open app".

**Rules.** The wake is the only coloured part of the brand and is always B2→B4 in order, hard-stepped. Never amber or B5+ in brand marks, never the wake without the arrow, never the arrow at any angle but 103° in the mark (chart arrows rotate freely — that's data). Voice: short, concrete, sailor-plain; no exclamation marks. VoiceOver label for the mark: "Wind Watch".

## 12a. Second model — NBM beyond the HRRR horizon (iPhone + web)

**The rule.** HRRR owns every hour it covers (~45 h). NBM (National Blend of Models, 2.5 km; hourly to 36 h, 3-hourly to day 7) is drawn only after HRRR ends, with a visible switch. NBM values for hours HRRR covers are never shown, blended, overlaid, badged or hinted at anywhere — chart, table, readout, peak chip, complications. (HRRR can say G31 for tomorrow where NBM says G9; showing both undercuts the number being acted on.)

**Fetching.** Two requests, no blended endpoint. Request NBM from `hrrr.horizon + 1` onward only, so near-term NBM is never on the device. Aggregate NBM to 3-hour blocks (max sustained, max gust, vector-mean direction) even where hourly is offered. Payload: `hours[]` stays HRRR; add `extended: {model:"NBM", run:"13Z", fetched, step:3, from:<hrrr.horizon+1>, blocks:[{t,kn,gust,dirFrom}]}`. The server enforces `from`; clients never filter.

**Ranges.** Segmented control in the chart title row, 26 pt, state remembered: `48 h` (default, HRRR only, today's chart unchanged) and `7 d` (HRRR to its horizon, then NBM to 168 h from chart start). No 3 d / 10 d for now.

**The switch, at the seam (= the existing HRRR-edge rule):** label `HRRR` left, `NBM · 3-hourly` right in `#9BB7D4`; NBM region tinted `#4FA3D8` at 4.5 %; NBM bars 70 % opacity (same ramp, 3-h slots); gust line solid on HRRR, **dashed 4/3 at 60 % on NBM**; caps and arrows unchanged. In 7 d the day names move to the bottom axis centred per day; midnight dividers stay; sun dots every day.

**Slot rule.** Under 4 px per hour the whole chart aggregates to 3-hourly (iPhone portrait 7 d: 56 slots at 7.2 pt, arrows every 6 h). Web desktop and iPhone landscape keep HRRR hourly to the seam (arrows every 3 h). Same chart function; one input.

**Readout / tooltip / table.** NBM blocks show a span and a tag: `Sat 12–3pm · NBM`; HRRR hours carry no tag. Peak chip reads across the whole range: `peak G32 · Sat 1pm · NBM`. Table: hourly rows to the seam, then 3-hour rows labelled by span with a small `NBM` tag, preceded by a one-line header `NBM from Fri 5am · 3-hourly`.

**Trust line.** `as of 09:00 · HRRR 15Z + NBM 13Z · ends Tue 9am`. Staleness per model: stale NBM desaturates only its region and ambers only its run label. NBM missing → 7 d stops at the HRRR edge with `NBM unavailable` in the seam label; never pad. HRRR missing but NBM present → show NBM from now, left-edge label `NBM · HRRR unavailable`, trust line amber.

**Landscape 7 d.** 48 pt header: location + full trust line (15/11 pt) left, readout centre (drops the degree figure; `now 3`), range control right. Plot 834 pt. Consider 48 pt side margins when 7 d is active so the Dynamic Island doesn't cover `now`.

**Watch and complications: HRRR only, unchanged.** When HRRR's horizon is nearer than 12 h the strip ends early rather than filling with NBM.

Reference artboards: `Spec-Models`, `Phone-Main-7d`, `Phone-Main-7d-Scrub`, `Phone-Landscape-7d`, `Web-Desktop-7d`. NBM values in them are illustrative; the HRRR portion is the real payload. Chart maths for the mixed view: `reference/mixed_reference.py`.

## 12b. Sky conditions and temperature (iPhone + web)

**Sky band.** A 14 pt strip directly above the plot, sharing its x-scale, one cell per 3 h (NBM region: same 3-h blocks). Cell = `RectangleMark`, 1 pt gap, radius 2: cloud cover < 25 % → `sun` (#FFB340) at 22 %; 25–70 % → `ink.secondary` at 28 %; ≥ 70 % → `ink.secondary` at 60 %. Rain → 1 / 2 / 3 short blue (`bft.2` #4FA3D8) 2 pt ticks hanging from the band's bottom edge for < 0.5 / 0.5–1.5 / > 1.5 mm/h, evenly spaced in the cell. No icons, no text, no legend. In the Old state the band desaturates with the chart. Not on the watch.

**Readout / tooltip text.** While scrubbing, the time label gains `· <sky> · <rain> · <temp>`: sky ∈ {Clear, Partly cloudy, Overcast}, rain ∈ {∅, light rain, rain, heavy rain}, temp as an integer with unit — `Thu 12am · midnight · Overcast · rain · 48°F`. Medium weight, `ink.secondary`. Degrees of direction stay where they were.

**Temperature unit.** Default **°F**. Setting on the iPhone About screen: a `Temperature` card with a two-segment `°F | °C` control (30 pt, `@AppStorage("tempUnit")`, synced to watch via the shared store though the watch shows no temperature today); caption `Wind is always knots.` Web: the same two-segment control in the footer, `localStorage`, default °F. Temperature appears only in the scrub readout, the web tooltip and the hourly table (new `°F` column after Beaufort, hidden under 360 px) — never in the hero, the complications, or the chart.

Reference boards: `Sky-Options`, `Phone-Main-Sky`, `Phone-Main-Sky-Scrub`, `Sun-Options`, `Phone-About`.

## 11. Acceptance checklist

- [ ] Hero shows sustained, gust, arrow, "from X" and a trust line on first paint from cache, with no spinner.
- [ ] Every wind number is an integer in knots; no decimals anywhere, including VoiceOver strings.
- [ ] Bars use exactly the ramp colours in §4.1; no interpolation between steps.
- [ ] Gust line passes through tick-cap centres; caps are bar + 2 wide.
- [ ] Arrows rotate `dirFrom + 180`; labels say "from"; inline snaps to 8 points.
- [ ] Day shading ramps linearly across dawn→rise and set→dusk; sunrise = filled dot, sunset = ring, nothing at dawn/dusk.
- [ ] Sky band above the plot at 3-h cells; scrub readout shows sky · rain · temperature; temperature defaults to °F with a °F/°C setting on About and in the web footer.
- [ ] Chart's last bar is the last forecast hour; dashed edge + label present; no padding.
- [ ] Trust state flips at 90 min and 6 h without a network refresh (timeline entries / timers).
- [ ] Offline with cache shows the reason and the cached time; never a blank.
- [ ] Circular: `8` and `15` render without moving the arrow or gust; ring survives tint; stale ring is dashed.
- [ ] Rectangular never shows the location name; Smart Stack does.
- [ ] Up to 12 locations; Edit button always present; any can be deleted except the last one; at 12 the screen opens in Edit mode and map long-press shows the toast.
- [ ] 7 d range: NBM never drawn before the HRRR horizon; seam labelled; NBM gust line dashed; NBM bars 70 %; readout/table/peak chip tagged `NBM`; trust line names both runs.
- [ ] Rectangular complication: trust text ≥ 11 pt at 41/42 mm with `from W` dropped first; strip y-domain floors at 20 kn and never shrinks within a run.
- [ ] Phone table reflows to two lines at AX sizes; chart clamps at 152 pt.
- [ ] Web page reads correctly in both colour schemes and at 375 px width with a horizontally scrolling table.
- [ ] VoiceOver label for a chart: `"45-hour wind chart: … ends Friday 05:00"`; for hero: `"15 knots, gusting 25, from the west, as of 23:30"`.

## 12. Open decisions (owner: Henry)

1. Keep the six-bar strip on the rectangular, or replace with `→ 25 by 00:00` in the same slot. Design keeps the strip; the slot geometry is identical either way.
2. Ship the Smart Stack widget in 1.0 or hold it.
3. Whether "G" reads as gust to a non-sailor on the phone/web; the watch keeps the letter regardless.
