# Wind Watch — web → iOS app awareness, design handoff

*28 Oct 2026.* The iOS app (iPhone + Apple Watch) is on the App Store. This change makes web visitors aware of it without touching how the web page works. Scope: the web app only, plus one card on the text2sail outing page. Nothing changes in the iOS app.

**Principle:** say it once, say it where it's true, and show the thing the web can't do (a complication on the watch face). Never "download our app"; the pitch is always the same three facts — the 12-hour strip as a complication, the now readout a glance away, up to 12 saved spots. The web stays a first-class surface and the fallback that always works. Nothing is added above the chart on desktop, nothing blocks the chart anywhere, nothing asks twice.

**References in `reference/`**

| File | What it is |
|---|---|
| `renders/App-Options.png` | The six treatments with verdicts and the recommended set. |
| `renders/Web-Phone-App-Safari.png` | Phone width in Safari: Smart App Banner (Apple's) + header link + footer card. |
| `renders/Web-Phone-App-Other.png` | Phone width in Chrome / in-app browsers: our strip + header link + footer card. |
| `renders/Web-Desktop-App.png` | Desktop: header link + footer card with complication drawing and QR. |
| `artboards/*.dc.html` | Sources behind the renders, every value inline. |
| `snippets.html` | The components as plain HTML, ready to lift: header link, footer card (desktop + phone), strip. |
| `app_awareness_reference.py` | Generator: `comp_mini()` (the complication drawing), `qr_svg()`, `promo_card()`, `own_strip()`, `header_link()`. |
| `brand3.py` | The app icon (`icon(size)`), already in the web codebase from the brand handoff. |

Live canvas: https://claude.ai/artifact/8v6ZfX1Qtzq3tZQybJ4x8d, row "Web → iOS app".

---

## 1. What to build

Four things ship; one is gated. Build in this order.

### 1.1 Safari Smart App Banner — build first

One tag in `<head>` on every web page:

```html
<meta name="apple-itunes-app" content="app-id=APP_ID, app-argument=https://windwatch.app/<current path>">
```

Safari on iOS draws it itself in system light/dark, shows **View** for new users and **Open** when the app is installed, and remembers a dismissal. We design nothing. `app-argument` is the page's own URL so the app opens on the same location (and the same outing on `/o/<id>`); the app must handle it as a universal link (§3). Only Safari on iOS shows it; that is why 1.4 exists.

### 1.2 Header link

Text link `iPhone & Watch app →`, 12 pt, Semibold, link colour `#9BB7D4` (hover white), no icon, no badge. On phone widths (< 600 px) it **replaces** the `HRRR wind · Port Townsend Bay, WA` tagline right of the lockup; on desktop it sits beside the tagline, 16 px gap, same row. Target: the App Store page, or — on iOS with the app installed — the app, via the universal link to the current page. Always present, never dismissed.

### 1.3 Persistent card above the footer

A `<section aria-label="Wind Watch for iPhone and Apple Watch">` between the hourly table and the footer, on every page including `/o/<id>`. Surface `card` #171C23, radius 10. It is part of the page like the data credit: **never dismissed, no close control.**

Desktop (≥ 600 px) — one row, padding 20/24, gap 24, wraps on narrow widths:
- App icon 48 pt (from `brand3.icon(48)`), `role="img"`.
- Text column (flex 1 1 260 px): title `Wind Watch for iPhone and Apple Watch` 17/22 Bold; body 14/19 `ink.secondary`: *The same forecast, on your wrist: the next 12 hours as a watch-face complication, the now readout a glance away, up to 12 saved spots. Free.*; then `windwatch.app/ios` 13 pt secondary (a plain redirect to the App Store page — the URL exists so it can be typed from a laptop).
- Right group, gap 22: the **complication drawing** 172×64 (§2) with caption `on the watch face` 11 pt `disabled`; and a **QR** 96×96 (§2) with caption `scan on your iPhone`.

Phone (< 600 px) — stacked, padding 16, gap 12:
- Row: icon 40 + title 16/21 Bold.
- Body 13/18 secondary (same text).
- Complication drawing full width (326×76 at 390 px; width = content width, height 76), caption `the rectangular complication, 12 hours`.
- Centred store button: white pill, 15 pt Bold ink `#0B0E12`, padding 10/18, download glyph 15 pt, label `Get it on the App Store`, links to the App Store page. No Apple badge artwork — the pill is ours.
- No QR on phone (you are already on the phone).

### 1.4 Our own strip — gated to non-Safari iOS

For iOS browsers that never draw the Smart Banner: Chrome, Firefox, Edge, and in-app browsers (Messages, Slack, Mail — where text2sail links open). One row directly **under the header row, above the H1**, full content width:
- `card` surface, radius 10, inset 1 px `hairline` #2A2F36, padding 10/10/10/12, gap 10.
- Icon 28 · text 14/18: **Also on iPhone and Apple Watch** Semibold + ` — the 12-hour strip as a complication.` Medium `ink.secondary` · `Get it` pill (14 pt Bold, white on #2A2F36, padding 6/12, App Store link) · ✕ button 32×32, `ink.secondary`, `aria-label="Dismiss for 30 days"`.
- **Show rule:** iOS user agent **and not** Safari (Smart Banner territory) **and** `localStorage.appStripDismissed` absent or older than 30 days. Never on desktop, never on Android (there is no Android app — say nothing there), never together with the Smart Banner. On ✕: store the timestamp, remove the row without reflowing the chart (animate height to 0, 200 ms).
- Shown at most once per page load; no re-show on navigation within the session.

### 1.5 Outing page card (`/o/<id>`) — with text2sail

On the outing page from the text2sail handoff, directly under the chart card and above the table: the same card as 1.3 phone layout but with outing copy: title **Keep this one on your wrist.**, body *The Saturday forecast as a complication, updating until you cast off.* (day name from the outing), store button. The universal link into the app carries the outing's lat/lon/name so the app selects (or offers to save) that location and the complication shows that forecast. The footer card (1.3) is **not** repeated on this page — one card, the better one.

### 1.6 Not building

Interstitials, "Open in app" takeovers, install modals, repeat prompts, banners above the chart on desktop, anything on Android. If a visitor dismissed the strip, the footer card and header link are the only reminders they ever get.

## 2. Components

**Complication drawing** (`comp_mini(W, H)`): a drawing of the rectangular complication, not a screenshot — black rounded plate (radius 10), text row (`3` Rounded Heavy 20, `G4` Rounded Bold 10 at 90 %, arrow + `from W` 9 pt, `as of 09:00` 10 pt secondary right-aligned), then 12 hourly bars (slot = W/12, bar 0.72 slot, ramp colour by Beaufort, 1 pt gust line with caps). Render it from the **live payload's next 12 hours** so the drawing matches the chart above it — static data would be a lie the page otherwise never tells. If the payload is old/offline, draw it in the Old treatment (saturate .35, opacity .7) like the chart.

**QR** (`qr_svg(96)`): encodes `https://windwatch.app/ios`, error level M, 2-module quiet zone, white plate radius 6, modules `#0B0E12`. Generate once at build time as inline SVG; it never changes. `role="img"`, `aria-label="QR code: https://windwatch.app/ios"`.

**Store button / links:** all app links point at one place, the App Store product page; `windwatch.app/ios` is a 302 to it. Universal links (§3) take precedence when the app is installed.

**Smart App Banner mock** in the renders is Apple's UI drawn for the picture; do not build it.

## 3. Universal links

Serve `/.well-known/apple-app-site-association` for `windwatch.app` covering `/`, `/l/*` (locations) and `/o/*` (outings). The iOS app handles: `/` → main; `/o/<id>` → fetch the outing, select or offer to save its location, open main with the outing day in view (48 h if inside the horizon, else 7 d). With this in place the header link, the strip's `Get it`, the Smart Banner's **Open** and the outing card all land in the app when it is installed, in the App Store when it is not.

## 4. Measurement

Three client events, nothing else: `app_link_header`, `app_card_footer`, `app_card_outing` (plus `app_strip_dismiss`). The Smart Banner is Apple's and reports nothing. Expect most installs from the outing card.

## 5. Open decisions

1. QR on desktop, or is the typed URL enough? (Drawn with the QR; drop it if it reads as clutter.)
2. Strip dismissal: 30 days, or forever?
3. Does the outing card also go to the organiser's view, or only to invitees?

## 6. Acceptance

- [ ] `apple-itunes-app` meta on every page with the page's own URL as `app-argument`; Safari iOS shows the banner, dismissal sticks.
- [ ] Header link present at all widths: replaces the tagline < 600 px, beside it ≥ 600 px; goes to the app when installed.
- [ ] Footer card on every page (except `/o/<id>`, which has the outing card instead); never dismissable; complication drawing uses the live next-12-hours and follows the chart's Old treatment; desktop shows QR + URL, phone shows the store button and no QR.
- [ ] Strip appears only on iOS non-Safari, only once per 30 days after dismissal, never alongside the Smart Banner, never on desktop or Android; dismissing doesn't shift the chart.
- [ ] Outing page: "Keep this one on your wrist" card under the chart, day name from the outing, deep link opens that location in the app.
- [ ] Universal links resolve for `/`, `/l/*`, `/o/*`.
- [ ] The chart, table and readout are pixel-identical to before on all widths; nothing new above the chart on desktop.
- [ ] All four events fire.

## Suggested prompt for Claude Code

> Read `docs/design/web-app-awareness/HANDOFF.md`. Implement §1.1–1.5 in the web app in that order, lifting markup from `reference/snippets.html` and porting `comp_mini` and `qr_svg` from `reference/app_awareness_reference.py`; the complication drawing must use the live payload. Add the AASA file and the app-side universal-link handling in §3. Compare against the three `reference/renders/Web-*.png` at 390 px and 1280 px before finishing, then walk §6.
