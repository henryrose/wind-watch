# What changed since the first design package

Read this first if you already built from an earlier package. Each item names the doc section and the render to check against. Everything not listed here is unchanged.

## Round 2 — layout refinements

- **Fixed-height readout on iPhone** (§6.4d, `Phone-Main.png`, `Phone-Main-Scrub.png`). The row above the chart is a 96 pt card in both the "now" and the scrubbing state, with identical structure. Scrubbing only adds a white ring. Nothing above the chart may change height while a finger is down.
- **Chart is edge to edge** (§6.4d). Portrait plot = full screen width; landscape = screen width − 40.
- **Hourly table is collapsible, collapsed by default** (§6.4d) on iPhone (52 pt disclosure row, state in `@AppStorage`) and web (`<details>`, state in `localStorage`).
- **Watch launches on the 12-hour strip** (§6.4d, `Watch-Strip.png`). Page order: strip → Now detail → Settings. The strip header carries a compact hero (`3 kn · G 4 · ▸ from W`).

## Round 3 — brand

- **App icon "Wake"** (§10a, `Brand-Icon-Final.png`): white arrow + B2/B3/B4 streaks on `#0B0E12`, with three size tiers (3 / 2 / 1 streaks). Use `reference/brand_icon.py` and the files in `reference/icon/`. Ship the explicit small/tiny PNGs for 29/40 pt and the favicons — don't let Xcode downscale the 1024.
- **Wordmark + where the name appears** (§10a): iPhone main eyebrow, About title, web header row + `<title>` + favicon, footers, watch Settings footer only.

## Round 4 — complication and locations

- **Rectangular complication shows 12 hours** (§6.3, §7.1, `Comp-Rectangular.png`). Numbers on one row (`15 · G25 · ▸ from W · as of 23:30`, no `kn`), full-width 12-bar strip below. Smart Stack uses the same 12-hour strip with 3-hourly labels.
- **Locations: up to 12, all equal** (§8.3, `Phone-Location.png`, `Phone-Location-Full.png`). Port Townsend Bay is seeded as row 1 but can be deleted, renamed and reordered like any other. Row 1 is the fallback. The last remaining location can't be deleted. Swipe left to delete at any time. At 12 of 12, every row shows a minus button with a two-tap confirm, a "List full" banner appears, and map long-press is disabled. Watch Settings: the same list, Crown-scrolled.

## Round 5 — critique fixes

- **Rectangular complication** (§6.3, §7.1, `Comp-Rectangular.png`): trust text is 11 pt minimum; on 41/42 mm `from W` drops to the bare arrow (`ViewThatFits` order in §7.1); strip y-domain floors at 20 kn and never shrinks within a run; the rectangular strip has no night shading or sun dot (Smart Stack keeps them). 42 mm cards are on the canvas.
- **Locations** (§8.3, `Phone-Location*.png`): permanent Edit button (standard `EditButton`) instead of state-dependent delete UI; swipe still works; selected location drives everything and list order means nothing; full list opens in Edit mode with the map still live and a toast on long-press.
- **Scrub readout** (§6.4d, `Phone-Main-Scrub.png`): degrees are back, small and secondary, next to `from W`.
