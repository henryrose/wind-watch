# Wind Watch design package — read this first

This folder is the design source of truth for Wind Watch. Use it in this order.

1. `DESIGN-HANDOFF.md` — the contract. Tokens, type, chart geometry, trust states, per-screen layouts, acceptance checklist. If code and this doc disagree, the doc wins.
2. `reference/renders/*.png` — pixel renders of every designed screen (2× scale). Compare your SwiftUI previews and the web page against these side by side. Watch screens are drawn at 2× pixels for 46 mm (416×496 px = 208×248 pt).
3. `reference/artboards/*.dc.html` — the exact source of each render. Every value you need is an inline style or an SVG attribute: font sizes, colours, paddings, bar x/y/width, stroke widths, rotations. When a render looks different from your build, diff against this, not against memory.
4. `reference/chart_reference.py` — a runnable reference implementation of the chart maths (slot width, bar width, y domain, twilight gradient stops, gust caps, arrow rotation, now marker, horizon edge, hour selection highlight, day bands). Port its `svg()` function; it produced every chart in the renders. `python3 chart_reference.py phonebig` prints the iPhone chart SVG for the reference payload.
5. `reference/charts/*.svg` — the generated chart fragments on their own, handy for the web page.

## Screen → file map

| Screen | Artboard | Render |
|---|---|---|
| System sheet (tokens, type, glyphs, trust line) | `Main.dc.html` | `Main.png` |
| Chart spec | `ChartSpec.dc.html` | `ChartSpec.png` |
| accessoryRectangular ×4 states + Smart Stack | `Comp-Rectangular.dc.html` | `Comp-Rectangular.png` |
| accessoryCircular ×4 + tinted | `Comp-Circular.dc.html` | `Comp-Circular.png` |
| accessoryInline ×4 | `Comp-Inline.dc.html` | `Comp-Inline.png` |
| accessoryCorner | `Comp-Corner.dc.html` | `Comp-Corner.png` |
| Watch Now (fresh) | `Watch-Now.dc.html` | `Watch-Now.png` |
| Watch Now: stale, offline, first run, 42 mm | `Watch-Now-States.dc.html` | `Watch-Now-States.png` |
| Watch 12-h strip / short horizon | `Watch-Strip*.dc.html` | `Watch-Strip*.png` |
| Watch settings | `Watch-Settings.dc.html` | `Watch-Settings.png` |
| iPhone main (fresh) | `Phone-Main.dc.html` | `Phone-Main.png` |
| iPhone main while touching a bar | `Phone-Main-Scrub.dc.html` | `Phone-Main-Scrub.png` |
| iPhone landscape (chart maximised) | `Phone-Landscape.dc.html` | `Phone-Landscape.png` |
| iPhone trust-line states | `Phone-Trust-States.dc.html` | `Phone-Trust-States.png` |
| iPhone table at AX type size | `Phone-Table-LargeType.dc.html` | `Phone-Table-LargeType.png` |
| iPhone location / about | `Phone-Location.dc.html`, `Phone-About.dc.html` | same names |
| Web desktop (hover state) / phone width | `Web-Desktop.dc.html`, `Web-Phone.dc.html` | same names |

## How to work from this

- Build the chart once as a parameterised view that takes `(hours, nowIndex, sun, selection, sizeClass)` and derives everything from slot width, exactly as `chart_reference.py` does. The watch strip, phone portrait, phone landscape and the mini complication strip are the same function with different inputs.
- Put the ramp and ink tokens in an asset catalog using the names in `DESIGN-HANDOFF.md` §4 and never write a hex in a view.
- Do the reference payload (§10) first and compare to `Phone-Main.png` and `Watch-Now.png` before wiring real data. Expected numbers are listed there.
- Then go through the acceptance checklist (§11) one line at a time.

Known cosmetic nits in the renders (don't reproduce them): on `Phone-Main*.png` the "Wed" day label and the "now" label touch — in the app, hide the first day label when it would collide with "now". The two-line "Thu 12am · midnight" in the scrub readout should stay on one line at default type size.
