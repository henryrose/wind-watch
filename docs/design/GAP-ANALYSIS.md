# Design package vs. build — gap analysis (2026-10-21)

Every row of `README.md`'s screen table, render opened and compared with the build's
screenshots in `docs/screenshots/`. "Doc" = `DESIGN-HANDOFF.md` (wins over renders).
Written before any code changed; the fix list at the bottom is the work order.

## System sheet (`Main.png`)

- Tokens, ramp hexes, ink colours: match (`Tokens.swift`, `Beaufort.swift`, `styles.css`).
- Type sizes on the sheet (hero 96, gust 40, summary 17, trust 15, hero arrow 28) differ
  from the doc §4.3 (84/27/13/12/18). Doc wins; the build already uses the doc values.
- Glyphs: kite arrow, tick cap, sun dot, now marker, horizon edge all present.

## Chart spec (`ChartSpec.png`, `chart_reference.py`)

Build uses Swift Charts (`WindChart.swift`); the reference is slot-width geometry. Gaps:

1. Y gridline labels sit in a left axis gutter; reference draws them right-aligned inside
   the plot at `W − 2`, 45 % ink, and never labels the top (`range(10, ymax, 10)`).
2. Phone tick labels are 24-h (`09 15 21 03`) every 6 h; doc §6.4a wants 12-hour
   (`9am · 3pm · 9pm · 3am`), 3-h with `noon`/`12am` on landscape and web.
3. No day band (day name at the left edge and at each midnight, dotted 1 pt divider
   dash 2/3 at 28 % dropping through the plot). Top inset must grow to 38 (portrait) / 40 (web).
4. Edge label is `HRRR ends 05:00`; doc §6.4a wants `ends Fri 5am` on phone/web
   (watch keeps `ends 05:00`).
5. Arrows are drawn in a separate band *below* the tick labels; reference puts arrows in the
   bottom inset (`plotBottom + bot/2`) with tick labels below the arrows at `H + 10`.
6. No hour selection (scrub) anywhere: dimmed bars 0.45, white outline + full-height rule.
7. Watch short-horizon ticks are index-anchored by Swift Charts (`22 01 04 07`); reference
   labels `00 03`.
8. Mini strip is a second renderer (`MiniStrip.swift`); README wants one chart function.
9. Twilight stops, bar ratio 0.72, cap = bar + 2, gust 75 % / caps 100 %, sun dots,
   now marker, dashed edge, y-domain rule: already match.

## Complications (`Comp-*.png` vs `d4-*`)

- Rectangular: layout, fonts, trust colours match. Past-horizon dash is a 26×5 capsule
  where the render draws a wider dash; `last run 15Z Wed` matches the rule.
- Circular: ring, fixed 22×17 frame, dashed stale ring, tinted row: match.
- Inline: match.
- Corner: render shows eight stepped ramp segments with a white dot and an amber *dashed*
  arc when stale; build uses a `Gauge(.accessoryLinear)` gradient and a solid amber tint.
  WidgetKit draws the corner `widgetLabel` gauge itself, so stepped segments and dashing
  are not reproducible there (recorded in `progress.md`). Not changed.

## Watch Now (`Watch-Now.png`, `Watch-Now-States.png` vs `d3-watch-now-*`)

1. Hero numeral renders smaller than 84 pt (a 70 pt frame plus `minimumScaleFactor`).
2. Summary is clamped to 2 lines with a mid-sentence ellipsis; render shows the full
   sentence on 46 mm (doc: 2 lines, 3 on 46 mm if room). Room exists.
3. First run: render splits `No data yet.` (15 Semibold, primary) from `Needs cellular or
   Wi-Fi once. It will keep the last forecast after that.` (13 body); build shows one
   paragraph and a pill-shaped dash.
4. Offline wording: render `Couldn't reach server. Showing data from Tue 23:30.`; doc §3
   `Couldn't reach server · showing data from 13:05`. Doc wins; build already matches.
5. Stale / updating / location / direction row / trust line: match.

## Watch strip (`Watch-Strip*.png` vs `d3-watch-strip-*`)

1. Y labels in a left gutter (see chart gap 1); reference has none at the left.
2. Tick labels: render `12 15 18` only; build `09 12 15 18` (kept, every 3 h rule).
3. Short horizon: build labels `22 01 04 07`; render `00 03`. Build's edge label and empty
   tail are right.
4. Header sits under the system clock on the real page (render has 22 pt top padding);
   page-indicator dots are drawn by `verticalPage` on the right, render puts two dots in
   the footer. The system indicator stays.

## Watch settings (`Watch-Settings.png` vs `d3-watch-settings-fresh.png`)

1. Render: two-line labels (name 14 Semibold / `default` · `set on iPhone` 10 secondary),
   blue filled check (`bft.2`) for the selected row; build: single line
   `Port Townsend Bay · default`, amber check.
2. Button plates 14 % / 8 % white, radius 12, 44 min: match.

## iPhone main (`Phone-Main.png` vs `d2-iphone-fresh-dark.png`)

1. Order: render is header → readout → chart card → summary → table; build puts the
   summary above the chart (doc §8.1 order; §6.4 "chart is the centrepiece" and the render
   move it). Render order adopted.
2. Header: title Bold 22 (render / §6.4) not 28; gear is a 44 pt circle in `card`;
   trust line ends `ends Fri 5am` not `ends Fri 05:00`.
3. Readout: hero 60 (§6.4) not 72; `G` 16 / gust 24; direction 16; peak chip 12 with a
   9 pt dot; row aligned to the bottom.
4. Chart card is full-bleed (`margin 0 −16`, radius 0, padding 12/16/10) with a title row
   `Wed 9am → Fri 5am` and a hint `touch a bar for that hour`; build has an inset card with
   radius 14 and no title row.
5. Table: `from` column shows `W` not `from W`; header `B` not `Bft`; kn/gust right-aligned;
   row rules in `card` colour, header rule `hairline`; 8 pt inner padding.
6. All chart gaps above.

## iPhone scrub (`Phone-Main-Scrub.png`) — not implemented

- Touch/drag on the plot selects an hour; readout row swaps to that hour with a `card`
  plate, 1.5 pt white inset stroke, label `Thu 12am · midnight` with a 2×14 white bar,
  `from W · 283°`, chip `4 Beaufort`, `now 3 kn` anchor; hint `release to return to now`;
  light haptic per hour change; snap back on release.

## iPhone landscape (`Phone-Landscape.png`) — not implemented

- `verticalSizeClass == .compact`: one 48 pt header line (location 17 Bold + trust 12),
  readout right; chart card fills the rest (756 wide inside 59 pt safe areas), arrows every
  hour, labels every 3 h, hint bottom-right.

## iPhone trust states (`Phone-Trust-States.png` vs `d2-iphone-{stale,old,offline}`)

- Amber Semibold line, `wifi.slash`, `ink.old` numbers, desaturated pill: match.
- Render's Old row says `ended Thu 05:00`; doc has no such rule. Not adopted.
- Header type size change (22) applies here too.

## iPhone table at AX (`Phone-Table-LargeType.png` vs `d2-iphone-fresh-ax-dark.png`)

1. Line 2 should be `9 kn` (Heavy) · `G 18` (body Semibold) · spacer · arrow + `W` right-aligned;
   build runs them together left-aligned with `G 4 ▸W`.
2. Chip scales (min 44, radius 10) in the render; build keeps the 24 pt chip.
3. Chart clamps at 152 pt with no day band: build already clamps at 152.
4. Trust line drops `ends …` at AX sizes in the render.

## iPhone location (`Phone-Location.png` vs `d2-iphone-location-dark.png`)

1. Back chevron and `Location` title on one line; build stacks a circular chevron button
   above the title.
2. Default check is blue (`bft.2`), legend dots blue/amber; build uses amber.
3. Coordinates shown with three decimals; build shows two.
4. Caption `One custom location. Pick the default above at any time with one tap; it never
   moves.`; custom card contains name, ring button, search field, map, legend; closing
   caption `The custom point is snapped to the nearest HRRR grid cell (3 km) when saved;
   the name is yours.` Build splits these into separate cards and different copy.

## iPhone about (`Phone-About.png` vs `d2-iphone-about-dark.png`)

1. Uppercase 13 Semibold secondary section labels (`THE MODEL`, `BEAUFORT COLOURS ·
   SUSTAINED WIND, KNOTS`); build uses title-case 20 pt headings.
2. Model copy is the render's three sentences (18 h / 48 h runs, horizon 40–47 h, run label
   explanation); build has different copy.
3. Legend rows: step · full-width 18 pt swatch bar (radius 5) · range right-aligned
   (`< 4`, `4–6`, … `48+`); build shows chip + short swatch + `≤ 3 kn`.
4. Attribution card: link-coloured `Open-Meteo.com`, second line `Sunrise and twilight
   computed on device. Wind Watch 1.0 · built for one bay.`

## Web desktop (`Web-Desktop.png` vs `web-fresh-dark-1180.png`)

1. Chart title `Wed 9am → Fri 5am` + hint `hover or touch a bar for that hour`; build
   `Hourly forecast` + `45 h · gusts to 25 kn`.
2. Chart: reference `webhover` geometry (1120×300, top 40, bottom 22, arrows hourly,
   3-h 12-hour labels, day band, grid labels inside right, `ends Fri 5am`); build has a
   left axis, 24-h labels inside the plot, no day band, `HRRR ends 05:00`.
3. Hover/touch tooltip card and keyboard stepping (§6.4c): not implemented.
4. Legend: swatches `0–1 … 7, 8+` + gust glyph + `blowing to` + `sunrise / sunset`; build
   lists all ten steps with numbers under each swatch.
5. Table: single `thead` (`Hour (PDT) · Sustained kn · Gust kn · From · Beaufort`), hour
   as `Wed 09:00`, kn/gust right-aligned, `from W · 290°`; build uses per-day header rows,
   `G 4`, `from W` without degrees, `Bft`.
6. Trust line `as of 09:00 PDT · HRRR 15Z · forecast ends Fri 5am`.
7. Footer `Weather data by Open-Meteo.com · HRRR 3 km · times in PDT` on the left.

## Web phone (`Web-Phone.png` vs `web-fresh-dark-375.png`)

1. Chart card has no title row; padding 10/0/12; geometry 358×200 (top 22 / bottom 16),
   arrows every 3 h, labels every 6 h. The render still shows 24-h labels and
   `HRRR ends 05:00` (pre-review); doc §6.4a wins → 12-hour and `ends Fri 5am`.
2. Table header `Wed · kn · gust · from · B`, rows `09:00 · 3 · 4 · ▸ W · chip`, no
   per-day header rows, no `G` prefix.
3. Hero row: peak chip only, no pill (build shows both; pill kept per doc §9 "wraps").

## Fix order

1. Chart: port `chart_reference.py::svg()` to one `WindChart` (Canvas) driven by a pure
   `ChartGeometry`; styles phonePortrait / phoneLandscape / phoneClamped / watchStrip /
   mini; selection; tests against `reference/charts/phonebig.svg` numbers.
2. iPhone main + scrub + landscape, then table / AX, location, about.
3. Watch Now, strip, settings; rectangular dash.
4. Web chart (same port in JS), hover, legend, table, header, footer.
5. Acceptance checklist §11, line by line, in `progress.md`.
