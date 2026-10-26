# Wind Watch — design handoff, 26 Oct 2026 session

Everything decided in this session, in build order. Each item names the render to match (`reference/renders/`), the artboard source behind it (`reference/artboards/`, every value inline), and the section of the full spec it changes (`DESIGN-HANDOFF-full.md`, which is already updated and wins on any conflict). Items 1–4 change shipped screens; 5–8 add new behaviour. The watch app and complications are untouched except item 1 and the sun markers in item 8.

Runnable references: `chart_reference.py` (48 h chart, now with the sun-marker rule), `mixed_reference.py` (7-day HRRR→NBM chart), `sky_reference.py` (sky band). The HRRR numbers everywhere are the real 21 Oct payload; NBM values and sky data are illustrative.

---

## 1. Rectangular complication: 12-hour strip, legible trust text, 42 mm fallback

Spec §6.3, §7.1 · `Comp-Rectangular.png`

- One text row (25 pt): sustained Rounded Heavy 23 · `G25` Rounded Bold 11 at 90 % · arrow 9 pt + `from W` Semibold 9 · spacer · trust text **Medium 11 pt minimum, never smaller** (`as of 23:30`; amber Semibold when stale/old). No `kn`.
- Below it the strip, full plate width: **next 12 hours**, one bar per hour (slot 14 pt, bar 0.72 slot), gust line + caps 1 pt, 0.5 pt ticks every 3 h. No arrows, labels, gridlines, shading or sun dots on the rectangular (Smart Stack keeps shading/sun).
- **Y domain = max(20 kn, window max gust rounded up to 5), and it only grows within a forecast run** — never shrinks between timeline entries. Resets on a new HRRR run.
- **Row-1 fallback order when it doesn't fit** (`ViewThatFits`): drop `from W` (keep the arrow) → drop the `G` prefix → number to 20 pt. Trust text is never removed or shrunk. On 41/42 mm the first fallback is the normal state (see the 42 mm cards).
- Past horizon: `—` + `No forecast` + `15Z Tue`; the strip slot becomes a dashed box `Open app to refresh`.

## 2. Locations: up to 12, all equal, Edit button, naming sheet

Spec §8.3 · `Phone-Location.png`, `Phone-Location-Full.png`, `Phone-Location-Edit.png`

- One list, **up to 12 locations, all equal**. Port Townsend Bay is seeded on first install as row 1 but is an ordinary row: renamable, reorderable, deletable. **The selected location drives every surface; list order means nothing.** The last remaining location cannot be deleted.
- Row: selection ring/check · name Semibold 16 · coords 12 secondary · trailing **ⓘ** (22 pt glyph, 44 pt hit area) that opens the detail sheet. Tap row = select. Swipe left = delete. **`Edit` in the nav bar, always present** (standard `EditButton`): minus buttons + drag handles. Counter top-right (`5 of 12`).
- **Full (12 of 12):** the screen opens in Edit mode (button reads `Done`), banner `List full (12). Delete one to add a new pin.`, two-tap delete (minus → row `Delete` pill with 10 % red tint). Map stays live; long-press shows a centred toast `List full — delete a location first`.
- **Naming sheet** (opened by map long-press, a search pick, or ⓘ): NAME field pre-filled with the reverse-geocoded suggestion, focused with the text selected for a new location; helper `Suggested from the map. Change it to what you call this spot; your name is never overwritten.`; map thumbnail with the pin and the 3 km HRRR cell; POSITION / FORECAST POINT tiles; suggestion chips (the geocoder's other nearby names, ≤ 4); `Save` / `Done`; `Delete Location` for existing ones (hidden for the last). **Rules:** `name` is user-owned, stored verbatim, never re-geocoded; renaming never moves the pin; 1–40 chars, trimmed; duplicate → ` 2` suffix suggested, not blocked; geocoder called once, at pin time (field order: areasOfInterest → inlandWater/ocean → locality → subLocality → administrativeArea; 4 s timeout → empty field, placeholder `Name this spot`).
- Watch Settings: the same list in the same order, Crown-scrolled (not drawn; no new UI beyond a list).

## 3. iPhone main: readout fix-ups

Spec §6.4d · `Phone-Main.png`, `Phone-Main-Scrub.png`

- Readout right column: `peak G25 · 12am` (now) / `now 3 kn` (scrubbing) over the Beaufort chip (number only, no word). Degrees appear only in the scrub state (`from W` + `283°` Medium 13 secondary) and the table.
- First day label suppressed when `now` sits at the plot start; first tick label dropped at the plot edge.
- "Wind Watch" eyebrow lockup is on every portrait main board, 48 h and 7 d. Landscape has none (rule).

## 4. Second model: NBM after the HRRR horizon, visible switch, 48 h / 7 d

Spec §12a · `Spec-Models.png`, `Phone-Main-7d.png`, `Phone-Main-7d-Scrub.png`, `Phone-Landscape-7d.png`, `Web-Desktop-7d.png`

- **The rule.** HRRR owns every hour it covers (~45 h). NBM (2.5 km; hourly to 36 h, 3-hourly to day 7) is drawn only after HRRR ends. Near-term NBM is never shown, blended, overlaid, badged or hinted at — chart, table, readout, peak chip, complications. (HRRR G31 vs NBM G9 for the same hour must never share a screen.)
- **Fetching.** Two requests; no blended endpoint. Request NBM from `hrrr.horizon + 1` onward only. Aggregate NBM to 3-h blocks (max sustained, max gust, vector-mean direction). Payload: `hours[]` stays HRRR; add `extended: {model:"NBM", run, fetched, step:3, from, blocks:[{t,kn,gust,dirFrom}]}`; the server enforces `from`.
- **Ranges.** Two-segment control in the chart title row (26 pt; 28 on web), state remembered: `48 h` **(default, HRRR only, unchanged)** · `7 d` (HRRR to its horizon, then NBM to 168 h). No 3 d / 10 d now.
- **The switch, at the seam (the existing HRRR-edge dashed rule):** labels `HRRR` left / `NBM · 3-hourly` right (#9BB7D4); NBM region tinted #4FA3D8 at 4.5 %; NBM bars 70 % opacity, same ramp; **gust line solid on HRRR, dashed 4/3 at 60 % on NBM**; caps and arrows unchanged. No smoothing at the join — a jump is information. Day names move to the bottom axis in 7 d; midnight dividers; sun markers every day.
- **Slot rule.** < 4 px per hour → the whole chart is 3-hourly (iPhone portrait 7 d: 56 slots, arrows every 6 h). Web desktop and iPhone landscape keep HRRR hourly to the seam (arrows every 3 h).
- **Text.** Readout/tooltip for an NBM block: `Sat 12–3pm · NBM` (span + tag; HRRR hours carry no tag). Peak chip across the range: `peak G32 · Sat 1pm · NBM`. Table: hourly rows to the seam, then 3-h rows with an `NBM` tag under a header `NBM from Fri 5am · 3-hourly`.
- **Trust line.** `as of 09:00 · HRRR 15Z + NBM 13Z · ends Tue 9am`; staleness per model (stale NBM desaturates only its region, ambers only its run). NBM missing → 7 d stops at the HRRR edge, seam label `NBM unavailable`. HRRR missing → NBM from now, left label `NBM · HRRR unavailable`, trust line amber.
- **Landscape 7 d.** 48 pt header: location + full trust line (15/11 pt) left, readout centre (no degrees; `now 3`), range control right; plot 834 pt; no hint text. Consider 48 pt side margins in 7 d so the Dynamic Island doesn't cover `now`.
- **Watch and complications: HRRR only.** Strip ends early when HRRR's horizon is < 12 h; never filled with NBM.

## 5. Sky conditions: the sky band

Spec §12b · `Sky-Options.png`, `Phone-Main-Sky.png`, `Phone-Main-Sky-Scrub.png`

- A **14 pt band directly above the plot**, sharing its x-scale, one cell per 3 h (NBM region too). Cell = rect, 1 pt gap, radius 2. Cloud cover < 25 % → #FFB340 at 22 %; 25–70 % → #9AA4B1 at 28 %; ≥ 70 % → #9AA4B1 at 60 %. Rain → 1 / 2 / 3 blue (#4FA3D8) 2 pt ticks hanging from the band's bottom edge for < 0.5 / 0.5–1.5 / > 1.5 mm/h. No icons, no text, no legend. Desaturates with the chart in the Old state. Not on the watch.
- Decided against: a glyph row (breaks the no-icon rule, reads weather-first) and readout-only (not glanceable). The band is the glance; the readout text below is the detail.

## 6. Temperature: in the readout, °F by default, °F/°C setting

Spec §12b · `Phone-Main-Sky-Scrub.png`, `Phone-About.png`, `Web-Desktop.png`

- While scrubbing, the time label gains `· <sky> · <rain> · <temp>` — `Thu 12am · midnight · Overcast · rain · 48°F` (sky ∈ Clear / Partly cloudy / Overcast; rain ∈ ∅ / light rain / rain / heavy rain; temp integer + unit). Medium, `ink.secondary`. Same text in the web tooltip.
- **Default °F.** Setting: iPhone About gets a `Temperature` card with a `°F | °C` two-segment control (30 pt, `@AppStorage("tempUnit")`, shared store), caption `Wind is always knots.` Web: the same control in the footer, `localStorage`.
- Temperature appears only in the scrub readout, the web tooltip and the hourly table (new `°F` column after Beaufort, hidden under 360 px). Never in the hero, complications or chart. The watch shows no temperature, so no watch setting.

## 7. Sunrise vs sunset markers

Spec §5 (glyphs) · `Sun-Options.png`, `Main.png`, any chart render

- **Sunrise = filled circle** r 3 pt (5 px watch) in `sun`; **sunset = ring** r 2.25 pt (4.25 px watch), 1.5 pt stroke, no fill, same colour. "On after it rises, off after it sets." Applied to every chart: 48 h, 7 d, landscape, web, watch strip, Smart Stack. Swift Charts: filled `PointMark` symbol vs `Circle().stroke(lineWidth: 1.5)`. Nothing is drawn at civil dawn/dusk.

## 8. Things decided *not* to change

- 48 h stays the default range.
- Watch strip stays 12 h HRRR; no NBM, no sky band, no temperature on the wrist.
- No icons anywhere for weather; no 10-day range yet; no smoothing at the model seam.

---

## Acceptance (today's items only)

- [ ] Rectangular: 12 hourly bars full width; trust text ≥ 11 pt on 41/42 mm with `from W` dropped first; y-domain floors at 20 and never shrinks within a run.
- [ ] Locations: 12 max, all deletable except the last; permanent Edit; full list opens in Edit mode; map long-press toasts when full; ⓘ opens the sheet; names stored verbatim, never re-geocoded; rename never moves the pin.
- [ ] 7 d: NBM never drawn before the HRRR horizon; seam labelled; NBM gust line dashed; NBM bars 70 %; `NBM` tags in readout, chip, table; trust line names both runs; HRRR hourly kept in landscape/web, 3-hourly in portrait.
- [ ] Sky band: 3-h cells above the plot with the three cloud tones and 1–3 rain ticks; readout shows sky · rain · temperature while scrubbing.
- [ ] Temperature defaults to °F; About and web footer toggles work; unit never appears in hero/complications/chart.
- [ ] Sunrise filled / sunset ring on every chart including the watch strip and Smart Stack.
- [ ] `Wind Watch` eyebrow present on every portrait main board (48 h and 7 d), absent in landscape.

## Suggested prompt for Claude Code

> Read `docs/design/handoff-2026-10-26/HANDOFF.md`. These are the changes from the 26 Oct design session, in build order; `DESIGN-HANDOFF-full.md` beside it is the complete spec and wins on conflicts. Before changing anything, open each item's render in `reference/renders/` and list the differences from the current build. Then implement 1→7, porting `mixed_reference.py` for the 7-day chart and `sky_reference.py` for the band. Finish with the acceptance list at the end of HANDOFF.md.
