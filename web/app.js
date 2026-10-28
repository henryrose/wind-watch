// Wind Watch — page controller. Everything that depends on "now" or on pixels.
import {
  CHART_STYLES,
  DEFAULT_RANGE,
  DEFAULT_TEMP_UNIT,
  HOUR_MS,
  MINUTE_MS,
  SHADE_DAY_ALPHA,
  SHADE_NIGHT_ALPHA,
  arrowRotation,
  beaufortStep,
  beaufortToken,
  chartAriaLabel,
  chartLayout,
  compassLabel,
  conditionsParts,
  formatHHMM,
  hero as heroFor,
  heroAriaLabel,
  hourAtX,
  localDayNumber,
  nowIndex as nowIndexFor,
  parseRange,
  parseTempUnit,
  peakChipText,
  rangeHint,
  rangePeak,
  rangeTitle,
  selectionGeometry,
  shortDay,
  slotLabel,
  slotTableLabel,
  tableCaption,
  tableRows,
  tempValue,
  toForecast,
  trustLine,
  trustState,
  tzAbbrev,
} from './lib/derive.js';
import { CACHE_KEY, parseRecord, recordAfterCheck, serializeRecord } from './lib/cache.js';
import { STRIP_KEY, compMiniHtml, shouldShowStrip } from './lib/awareness.js';

const CHECK_MS = 10 * MINUTE_MS;
const KITE = 'M0,-0.5 L0.38,0.5 L0,0.2 L-0.38,0.5 Z';
const STATES = new Set(['fresh', 'stale', 'old', 'offline', 'horizon', 'firstrun', 'updating']);
const WIDE_MIN = 900; // desktop chart geometry (HANDOFF §6.5)
const COMPACT_MAX = 599; // phone layout: compact table, no chart head/legend (§9)
const TIP_FLIP_PX = 160; // flip the tooltip within this distance of the chart's right edge (§6.4c)

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const r2 = (n) => Math.round(n * 100) / 100;
const r4 = (n) => Math.round(n * 10000) / 10000;

// --- Options from the query string ----------------------------------------

function readOptions() {
  const q = new URLSearchParams(location.search);
  const state = STATES.has(q.get('state')) ? q.get('state') : null;
  const nowParam = q.get('now');
  let now = null;
  let live = false;
  if (nowParam === 'live') live = true;
  else if (nowParam) {
    const d = new Date(nowParam);
    if (!Number.isNaN(d.getTime())) now = d;
  }
  const scheme = q.get('scheme');
  if (scheme === 'dark' || scheme === 'light') document.documentElement.dataset.scheme = scheme;
  // ?hover=<hour index>: verification aid that applies the hover state on render.
  const hoverParam = q.get('hover');
  const hover = hoverParam !== null && /^\d+$/.test(hoverParam) ? Number(hoverParam) : null;
  // ?range=48h|7d and ?unit=f|c preset the two controls (screenshots); they
  // are not written to localStorage. ?nbm=stale|off and ?sky=off reshape the
  // payload to exercise the stale-NBM / missing-NBM / no-sky paths.
  const range = parseRange(q.get('range'));
  const unit = parseTempUnit(q.get('unit'));
  const nbm = ['stale', 'old', 'off'].includes(q.get('nbm')) ? q.get('nbm') : null;
  const sky = q.get('sky') === 'off' ? 'off' : null;
  return { state, now, live, hover, range, unit, nbm, sky };
}

// --- Preferences: chart range and temperature unit (localStorage) ---------

const RANGE_KEY = 'ww.range';
const UNIT_KEY = 'tempUnit'; // spec §12b names this key
const prefs = { range: DEFAULT_RANGE, unit: DEFAULT_TEMP_UNIT };

function loadPrefs(opts) {
  let range = null;
  let unit = null;
  try {
    range = parseRange(localStorage.getItem(RANGE_KEY));
    unit = parseTempUnit(localStorage.getItem(UNIT_KEY));
  } catch { /* storage blocked */ }
  prefs.range = opts.range || range || DEFAULT_RANGE;
  prefs.unit = opts.unit || unit || DEFAULT_TEMP_UNIT;
}

function savePref(key, value) {
  try { localStorage.setItem(key, value); } catch { /* ignore */ }
}

function syncSegments(group, value) {
  for (const b of group.querySelectorAll('button[data-v]')) {
    const on = b.dataset.v === value;
    b.setAttribute('aria-checked', on ? 'true' : 'false');
    b.tabIndex = on ? 0 : -1;
  }
}

// Two-segment radiogroups: click, or ←/→ inside the group.
function installSegments(group, onPick) {
  group.addEventListener('click', (e) => {
    const b = e.target.closest('button[data-v]');
    if (b) onPick(b.dataset.v);
  });
  group.addEventListener('keydown', (e) => {
    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
    const bs = [...group.querySelectorAll('button[data-v]')];
    const i = bs.findIndex((b) => b.getAttribute('aria-checked') === 'true');
    const next = bs[(i + (e.key === 'ArrowRight' ? 1 : bs.length - 1)) % bs.length];
    e.preventDefault();
    onPick(next.dataset.v);
    next.focus();
  });
}

let controlsInstalled = false;
function installControls(rerender) {
  if (controlsInstalled) return;
  controlsInstalled = true;
  installSegments($('range-ctl'), (v) => {
    if (v === prefs.range) return;
    prefs.range = v;
    savePref(RANGE_KEY, v);
    rerender();
  });
  installSegments($('unit-seg'), (v) => {
    if (v === prefs.unit) return;
    prefs.unit = v;
    savePref(UNIT_KEY, v);
    rerender();
  });
}

// Verification aids: reshape a payload before it becomes a forecast.
function adjustPayload(body, opts) {
  if (!body || (!opts.nbm && !opts.sky)) return body;
  const p = { ...body };
  if (opts.nbm === 'off') p.extended = null;
  else if ((opts.nbm === 'stale' || opts.nbm === 'old') && p.extended) {
    const back = opts.nbm === 'stale' ? 2 * 3600 : 7 * 3600;
    p.extended = { ...p.extended, fetched: p.fetched - back, run: p.extended.run - back };
  }
  if (opts.sky === 'off') {
    delete p.temp;
    delete p.cloud;
    delete p.precip;
    if (p.extended) p.extended = { ...p.extended, temp: undefined, cloud: undefined, precip: undefined };
  }
  return p;
}

// Default clock per forced state so the fixture lands in that state.
function defaultNow(forecast, state) {
  const f = forecast.fetched.getTime();
  switch (state) {
    case 'stale': return new Date(f + 2 * HOUR_MS);
    case 'old': return new Date(f + 7 * HOUR_MS);
    case 'horizon': return new Date(forecast.horizon.getTime() + 2 * HOUR_MS);
    default: return new Date(forecast.start.getTime() + 30 * MINUTE_MS);
  }
}

// --- Data ----------------------------------------------------------------

function apiBase() {
  return ((window.WW_CONFIG && window.WW_CONFIG.apiBase) || '').replace(/\/$/, '');
}

// Fixture mode: the reference payload, relative to this page.
async function loadFixture() {
  const url = new URL('../fixtures/payload-reference.json', location.href).href;
  const res = await fetch(url, { cache: 'no-cache' });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

// Live mode: one conditional GET. Resolves to an outcome for recordAfterCheck;
// never throws.
async function checkLive(base, etag) {
  // X-WW-Client lets the Worker count requests per surface (server/src/usage.ts).
  const headers = { 'X-WW-Client': 'web/1' };
  if (etag) headers['If-None-Match'] = etag;
  try {
    const res = await fetch(`${base}/v1/wind`, { cache: 'no-store', headers });
    const now = Date.now();
    if (res.status === 304) return { status: 304, now };
    if (res.status === 200) {
      const body = await res.json();
      return { status: 200, etag: res.headers.get('ETag') || '', body, now };
    }
    let code = null;
    try { code = (await res.json()).error || null; } catch { /* no JSON body */ }
    return { status: res.status, code, now };
  } catch (err) {
    return { status: 'error', now: Date.now(), error: err };
  }
}

// localStorage is optional (private mode, blocked storage): every access is guarded.
function readCache() {
  try { return parseRecord(localStorage.getItem(CACHE_KEY)); } catch { return null; }
}
function writeCache(record) {
  try { localStorage.setItem(CACHE_KEY, serializeRecord(record)); } catch { /* ignore */ }
}

// --- Glyphs ----------------------------------------------------------------

function arrowSvg(dirFrom, size, cls = 'arrow') {
  const rot = arrowRotation(dirFrom);
  return `<svg class="${cls}" viewBox="-0.6 -0.6 1.2 1.2" width="${size}" height="${size}" aria-hidden="true"><path d="${KITE}" transform="rotate(${rot})"/></svg>`;
}

const WIFI_SLASH = `<svg class="glyph" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke-width="2" stroke-linecap="round">
  <path d="M2.5 9.5a14 14 0 0 1 19 0"/><path d="M6 13.5a9 9 0 0 1 12 0"/><circle cx="12" cy="18" r="1.6" stroke="none"/><line x1="3" y1="3" x2="21" y2="21"/></svg>`;

// --- Chart (chart_reference.py::svg via derive.chartLayout) -----------------

function buildChart(forecast, L, { nbmStale = false } = {}) {
  const tz = forecast.location.tz;
  const out = [];
  const { W, H, top, plotH, plotBottom, font } = L;
  const nbmCls = (m) => (m === 'NBM' ? ' nbm' : '');

  // Shading: one rect per scheme with a horizontal gradient from the twilight
  // stops; CSS shows the white-by-day one in dark and the black-by-night one
  // in light.
  const gradient = (id, color, alphaOf) =>
    `<linearGradient id="${id}" x1="0" y1="0" x2="1" y2="0">${L.stops
      .map((s) => `<stop offset="${r4(s.offset)}" stop-color="${color}" stop-opacity="${r4(alphaOf(s.value))}"/>`)
      .join('')}</linearGradient>`;
  out.push(`<defs>${gradient('ww-shade-day', '#FFFFFF', (v) => SHADE_DAY_ALPHA * v)}${gradient('ww-shade-night', '#000000', (v) => SHADE_NIGHT_ALPHA * (1 - v))}</defs>`);
  out.push(`<rect class="shade shade-day" x="0" y="${top}" width="${W}" height="${plotH}" fill="url(#ww-shade-day)"/>`);
  out.push(`<rect class="shade shade-night" x="0" y="${top}" width="${W}" height="${plotH}" fill="url(#ww-shade-night)"/>`);

  // NBM region tint (7 d), under everything else.
  if (L.seam) {
    const r = L.seam.region;
    out.push(`<rect class="nbm-tint nbm" x="${r2(r.x)}" y="${r.y}" width="${r2(r.w)}" height="${r2(r.h)}"/>`);
  }

  // Gridlines every 10 kn below ymax; labels right-aligned inside the plot.
  for (const g of L.grid) {
    out.push(`<line class="grid" x1="0" x2="${W}" y1="${r2(g.y)}" y2="${r2(g.y)}"/>`);
    out.push(`<text class="grid-label" x="${g.labelX}" y="${r2(g.labelY)}" text-anchor="end" font-size="${font - 1}">${g.v}</text>`);
  }

  // Sun markers on the plot's top edge: sunrise filled r 3, sunset ring r 2.25.
  for (const s of L.sun) {
    const title = `<title>${s.kind === 'rise' ? 'sunrise' : 'sunset'} ${formatHHMM(s.at, tz)}</title>`;
    out.push(s.kind === 'rise'
      ? `<circle class="sun sun-rise" cx="${r2(s.x)}" cy="${s.y}" r="3">${title}</circle>`
      : `<circle class="sun sun-set" cx="${r2(s.x)}" cy="${s.y}" r="2.25">${title}</circle>`);
  }

  // Bars (sustained), Beaufort-stepped fill; 10+ gets the inset stroke; NBM 70 %.
  for (const b of L.bars) {
    out.push(`<rect class="bar bft-${b.token}${nbmCls(b.model)}" data-i="${b.i}" x="${r2(b.x)}" y="${r2(b.y)}" width="${r2(b.w)}" height="${r2(b.h)}" rx="1.5"/>`);
    if (b.step >= 10) {
      out.push(`<rect class="bar-inset${nbmCls(b.model)}" x="${r2(b.x + 1)}" y="${r2(b.y + 1)}" width="${r2(b.w - 2)}" height="${r2(Math.max(0, b.h - 2))}" rx="1"/>`);
    }
  }

  // Hover / keyboard selection layer (filled by setSelection).
  out.push('<g class="sel"></g>');

  // Gust polyline through cap centres (solid on HRRR, dashed 4/3 at 60 % on
  // NBM, not joined across the seam), then caps (bar + 2 wide).
  const line = (pts, cls) => (pts.length ? `<polyline class="${cls}" points="${pts.map((g) => `${r2(g.x)},${r2(g.y)}`).join(' ')}"/>` : '');
  out.push(line(L.gust.filter((g) => g.model !== 'NBM'), 'gust-line'));
  out.push(line(L.gust.filter((g) => g.model === 'NBM'), 'gust-line gust-nbm nbm'));
  for (const g of L.gust) {
    out.push(`<line class="gust-cap${nbmCls(g.model)}" x1="${r2(g.x - g.capW / 2)}" x2="${r2(g.x + g.capW / 2)}" y1="${r2(g.y)}" y2="${r2(g.y)}"/>`);
  }

  // Arrows in the bottom inset, pointing TO.
  for (const a of L.arrows) {
    out.push(`<path class="arrow${nbmCls(a.model)}" d="${KITE}" transform="translate(${r2(a.x)} ${r2(a.y)}) rotate(${a.rot}) scale(${L.arrowSize})"/>`);
  }

  // Time ticks and 12-hour labels below the arrow row (48 h).
  for (const t of L.ticks) {
    out.push(`<line class="tick" x1="${r2(t.x)}" x2="${r2(t.x)}" y1="${r2(t.y1)}" y2="${r2(t.y2)}"/>`);
  }
  for (const l of L.labels) {
    out.push(`<text class="tick-label" x="${r2(l.x)}" y="${l.y}" text-anchor="middle" font-size="${font}">${l.text}</text>`);
  }

  // Days: 48 h names in the band above the plot; 7 d names centred per day on
  // the bottom axis. Dotted divider at each midnight.
  for (const d of L.days) {
    if (d.divider) out.push(`<line class="day-divider" x1="${r2(d.divider.x)}" x2="${r2(d.divider.x)}" y1="${d.divider.y1}" y2="${r2(d.divider.y2)}"/>`);
    if (d.hidden) continue;
    out.push(d.bottom
      ? `<text class="day-label day-label-bottom" x="${r2(d.labelX)}" y="${d.labelY}" text-anchor="middle" font-size="${font}">${d.name}</text>`
      : `<text class="day-label" x="${r2(d.labelX)}" y="${d.labelY}" font-size="${font}">${d.name}</text>`);
  }

  // Model seam (7 d): the HRRR-edge rule, `HRRR` left, `NBM · 3-hourly` right.
  if (L.seam) {
    const s = L.seam;
    out.push(`<line class="edge-rule" x1="${r2(s.x)}" x2="${r2(s.x)}" y1="${s.y1}" y2="${r2(s.y2)}"/>`);
    out.push(`<text class="edge-label" x="${r2(s.left.x)}" y="${s.labelY}" text-anchor="end" font-size="${font}">${s.left.text}</text>`);
    out.push(`<text class="seam-label nbm" x="${r2(s.right.x)}" y="${s.labelY}" font-size="${font}">${esc(s.right.text)}</text>`);
  }

  // Now marker (only when inside the plotted range).
  if (L.now) {
    out.push(`<line class="now-rule" x1="${r2(L.now.x)}" x2="${r2(L.now.x)}" y1="${L.now.y1}" y2="${r2(L.now.y2)}"/>`);
    out.push(`<text class="now-label" x="${r2(L.now.labelX)}" y="${L.now.labelY}" font-size="${font}">${L.now.text}</text>`);
  }

  // Edge: the chart ends where the forecast ends.
  out.push(`<line class="edge-rule" x1="${r2(L.edge.x)}" x2="${r2(L.edge.x)}" y1="${L.edge.y1}" y2="${r2(L.edge.y2)}"/>`);
  out.push(`<text class="edge-label" x="${r2(L.edge.labelX)}" y="${L.edge.labelY}" text-anchor="end" font-size="${font}">${esc(L.edge.text)}</text>`);

  // Sky band (§12b): 14 high above everything, same x-scale, 3-h cells, rain
  // ticks hanging from its bottom edge. The chart below shifts down by skyH.
  let sky = '';
  if (L.sky.length) {
    const cells = L.sky.map((c) =>
      `<rect class="sky-cell sky-${c.tone}${nbmCls(c.model)}" x="${r2(c.x)}" y="${c.y}" width="${r2(c.w)}" height="${c.h}" rx="2"/>` +
      c.ticks.map((t) => `<line class="sky-rain${nbmCls(c.model)}" x1="${r2(t.x)}" x2="${r2(t.x)}" y1="${t.y1}" y2="${t.y2}"/>`).join(''));
    sky = `<g class="sky" aria-hidden="true">${cells.join('')}</g>`;
  }
  const body = L.skyH ? `${sky}<g transform="translate(0 ${L.skyH})">${out.join('')}</g>` : out.join('');
  const cls = `chart range-${L.range}${nbmStale ? ' nbm-stale' : ''}`;
  return `<svg class="${cls}" viewBox="0 0 ${W} ${H + L.skyH}" role="img" tabindex="0" aria-label="${esc(chartAriaLabel(forecast, L.range))}">${body}</svg>`;
}

function buildLegend(range, forecast) {
  const ramp = [['calm', '0–1'], ['2', '2'], ['3', '3'], ['4', '4'], ['5', '5'], ['6', '6'], ['7', '7'], ['8', '8+']];
  const nbm = range === '7d' && forecast && forecast.extended
    ? `<span class="legend-item legend-nbm"><span class="nbm-swatch"></span>NBM region · 3-hourly blocks, dashed gust line</span>`
    : '';
  return `${ramp
    .map(([t, l]) => `<span class="legend-item"><span class="swatch bft-${t}"></span>${l}</span>`)
    .join('')}
    <span class="legend-item legend-gust"><svg viewBox="0 0 22 12" aria-hidden="true"><polyline points="1,10 11,4 21,7" fill="none" stroke="currentColor" stroke-opacity="0.75" stroke-width="1.5"/><line x1="7" x2="15" y1="4" y2="4" stroke="currentColor" stroke-width="1.5"/></svg>gust</span>
    <span class="legend-item">${arrowSvg(283, 12)}blowing to</span>
    <span class="legend-item"><span class="sundot"></span><span class="sunring"></span>sunrise / sunset</span>${nbm}`;
}

// --- Hover / touch / keyboard (HANDOFF §6.4c) -------------------------------

const chartState = { forecast: null, layout: null, sel: null, wide: true, touchSticky: false };

// Tooltip (§6.4c, §12a, §12b): "Thu 12am · midnight · Overcast · rain · 48°F"
// for an HRRR hour, "Sat 12–3pm · NBM · …" for a block.
function tooltipHtml(forecast, slot) {
  const step = beaufortStep(slot.kn);
  const tz = forecast.location.tz;
  const tag = slot.model === 'NBM' ? ' <span class="tip-tag">· NBM</span>' : '';
  const cond = conditionsParts(slot, prefs.unit);
  const condHtml = cond.length ? `<span class="tip-cond">· ${esc(cond.join(' · '))}</span>` : '';
  return `
    <div class="tip-when"><span class="tip-bar" aria-hidden="true"></span>${esc(slotLabel(slot, tz))}${tag}${condHtml}</div>
    <div class="tip-kn"><span class="n num">${slot.kn}</span><span class="u">kn</span></div>
    <div class="tip-gust num"><span class="g">G</span>${slot.gust}</div>
    <div class="tip-dir">${arrowSvg(slot.dirFrom, 16)}<span>from ${compassLabel(slot.dirFrom)} · ${slot.dirFrom}°</span></div>
    <span class="chip bft-${beaufortToken(step)}">${step}</span>`;
}

function placeTooltip(tip, svg, cx) {
  const rect = svg.getBoundingClientRect();
  const cxPx = cx * (rect.width / chartState.layout.W);
  if (!chartState.wide) {
    // Narrow widths: dock to the top of the chart card, centred.
    tip.style.top = '0';
    tip.style.left = '50%';
    tip.style.transform = 'translateX(-50%)';
    return;
  }
  const scale = rect.width / chartState.layout.W;
  tip.style.top = `${r2(44 + chartState.layout.skyH * scale)}px`; // 4 px below the day band (and sky band)
  tip.style.left = `${r2(cxPx)}px`;
  if (rect.width - cxPx < TIP_FLIP_PX) tip.style.transform = 'translateX(calc(-100% - 10px))'; // flip left of the rule
  else if (cxPx < TIP_FLIP_PX) tip.style.transform = 'translateX(10px)'; // keep it inside the card at the left edge
  else tip.style.transform = 'translateX(-50%)';
}

function setSelection(i) {
  const svg = $('chart-host').querySelector('svg');
  const tip = $('chart-tip');
  if (!svg || !chartState.layout) return;
  const prev = svg.querySelector('.bar.selected');
  if (prev) prev.classList.remove('selected');
  const selG = svg.querySelector('.sel');
  if (i == null) {
    chartState.sel = null;
    svg.classList.remove('selecting');
    selG.innerHTML = '';
    tip.classList.add('hidden');
    tip.innerHTML = '';
    return;
  }
  const g = selectionGeometry(chartState.layout, i);
  if (!g) return;
  chartState.sel = i;
  svg.classList.add('selecting');
  const bar = svg.querySelector(`.bar[data-i="${i}"]`);
  if (bar) bar.classList.add('selected');
  selG.innerHTML =
    `<line class="sel-rule" x1="${r2(g.rule.x)}" x2="${r2(g.rule.x)}" y1="${g.rule.y1}" y2="${r2(g.rule.y2)}"/>` +
    `<rect class="sel-outline" x="${r2(g.outline.x)}" y="${r2(g.outline.y)}" width="${r2(g.outline.w)}" height="${r2(g.outline.h)}" rx="${g.outline.rx}"/>`;
  tip.innerHTML = tooltipHtml(chartState.forecast, chartState.layout.slots[i]);
  tip.classList.remove('hidden');
  placeTooltip(tip, svg, g.cx);
}

function hourFromEvent(e, svg) {
  const rect = svg.getBoundingClientRect();
  const x = (e.clientX - rect.left) * (chartState.layout.W / rect.width);
  return hourAtX(chartState.layout, x);
}

let interactionInstalled = false;
function installChartInteraction() {
  if (interactionInstalled) return;
  interactionInstalled = true;
  const host = $('chart-host');
  const svgOf = (e) => e.target.closest && e.target.closest('svg.chart');

  host.addEventListener('pointermove', (e) => {
    const svg = svgOf(e);
    if (!svg || !chartState.layout) return;
    const i = hourFromEvent(e, svg);
    if (e.pointerType === 'touch') chartState.touchSticky = true;
    if (i !== chartState.sel) setSelection(i);
  });
  host.addEventListener('pointerdown', (e) => {
    const svg = svgOf(e);
    if (!svg || !chartState.layout) return;
    chartState.touchSticky = e.pointerType === 'touch';
    setSelection(hourFromEvent(e, svg));
  });
  host.addEventListener('pointerleave', (e) => {
    // A touch selection stays until the next tap outside the chart.
    if (chartState.touchSticky && e.pointerType === 'touch') return;
    setSelection(null);
  });
  document.addEventListener('pointerdown', (e) => {
    if (chartState.sel != null && chartState.touchSticky && !host.contains(e.target)) {
      chartState.touchSticky = false;
      setSelection(null);
    }
  });
  host.addEventListener('keydown', (e) => {
    if (!svgOf(e) || !chartState.layout) return;
    const n = chartState.layout.n;
    if (e.key === 'Escape') {
      setSelection(null);
      e.preventDefault();
      return;
    }
    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
    e.preventDefault();
    const dir = e.key === 'ArrowRight' ? 1 : -1;
    let i;
    if (chartState.sel == null) {
      const nowI = chartState.layout.now ? hourAtX(chartState.layout, chartState.layout.now.x) : 0;
      i = Math.min(n - 1, Math.max(0, nowI ?? 0));
    } else {
      i = Math.min(n - 1, Math.max(0, chartState.sel + dir));
    }
    setSelection(i);
  });
  host.addEventListener('focusout', () => setSelection(null));
}

// --- Table ----------------------------------------------------------------

// HANDOFF §6.4d: the table is a <details>, closed by default; open/closed is
// remembered per browser. `?table=1|0` presets it for screenshots.
const TABLE_KEY = 'ww.hourlyTableExpanded';
let tableDisclosureInstalled = false;
function installTableDisclosure() {
  const d = $('table-card');
  if (tableDisclosureInstalled) return;
  tableDisclosureInstalled = true;
  const forced = new URLSearchParams(location.search).get('table');
  let open = false;
  if (forced != null) open = forced === '1';
  else { try { open = localStorage.getItem(TABLE_KEY) === '1'; } catch { /* storage blocked */ } }
  d.open = open;
  d.addEventListener('toggle', () => {
    try { localStorage.setItem(TABLE_KEY, d.open ? '1' : '0'); } catch { /* ignore */ }
  });
}


function buildTable(forecast, nowIdx, compact, range) {
  const tz = forecast.location.tz;
  const nowRow = Math.floor(nowIdx);
  const chipMin = compact ? 24 : 26;
  const hasTemp = forecast.hours[0].temp != null;
  const unitHead = `°${prefs.unit}`;
  const tempHead = hasTemp ? `<th scope="col" class="r temp">${unitHead}</th>` : '';
  const headCells = (dayName) => (compact
    ? `<th scope="col">${esc(dayName)}</th><th scope="col" class="r">kn</th><th scope="col" class="r">gust</th><th scope="col">from</th><th scope="col" class="r">B</th>`
    : `<th scope="col">Hour (${esc(tzAbbrev(forecast.start, tz))})</th><th scope="col" class="r">Sustained kn</th><th scope="col" class="r">Gust kn</th><th scope="col">From</th><th scope="col" class="r">Beaufort</th>`) + tempHead;
  const cols = 5 + (hasTemp ? 1 : 0);
  const row = (slot, hourHtml, cls) => {
    const step = beaufortStep(slot.kn);
    const from = compact ? compassLabel(slot.dirFrom) : `from ${compassLabel(slot.dirFrom)} · ${slot.dirFrom}°`;
    const t = hasTemp ? `<td class="temp num r">${slot.temp != null ? tempValue(slot.temp, prefs.unit) : ''}</td>` : '';
    return `<tr${cls ? ` class="${cls}"` : ''}>
      <td class="hour num">${hourHtml}</td>
      <td class="kn r">${slot.kn}</td>
      <td class="gust num r">${slot.gust}</td>
      <td class="dir"><span>${arrowSvg(slot.dirFrom, 14)}${from}</span></td>
      <td class="bft r"><span class="chip bft-${beaufortToken(step)}" style="min-width:${chipMin}px">${step}</span></td>${t}
    </tr>`;
  };
  const rows = [];
  let lastDay = null;
  for (const r of tableRows(forecast, range)) {
    if (r.kind === 'nbm-header') {
      rows.push(`<tr class="nbm-row"><th scope="rowgroup" colspan="${cols}">${esc(r.text)}</th></tr>`);
      continue;
    }
    const t = r.slot.start;
    const day = localDayNumber(t, tz);
    if (lastDay === null) lastDay = day;
    else if (compact && day !== lastDay) {
      lastDay = day;
      rows.push(`<tr class="day-row">${headCells(shortDay(t, tz))}</tr>`);
    }
    if (r.kind === 'hour') {
      const hour = compact ? formatHHMM(t, tz) : `${shortDay(t, tz)} ${formatHHMM(t, tz)}`;
      rows.push(row(r.slot, hour, r.i === nowRow ? 'now' : ''));
    } else {
      rows.push(row(r.slot, `${slotTableLabel(r.slot, tz, { compact })} <span class="tag-nbm">NBM</span>`, 'nbm'));
    }
  }
  return `<table class="${compact ? 'compact' : ''}"><caption class="visually-hidden">Hourly wind forecast, knots</caption><thead><tr>${headCells(shortDay(forecast.start, tz))}</tr></thead><tbody>${rows.join('')}</tbody></table>`;
}

// --- Hero ------------------------------------------------------------------

function buildHero(forecast, now, range) {
  const h = heroFor(forecast, now);
  if (!h) {
    return {
      html: `<div class="hero-main"><span class="hero-kn num dash">—</span><span class="hero-unit">kn</span></div>`,
      label: 'No forecast',
    };
  }
  const step = beaufortStep(h.kn);
  // 7 d: the chip reads across the whole range (§12a), "peak G32 · Sat 1pm · NBM".
  const peak7 = range === '7d' && forecast.extended ? rangePeak(forecast, nowIndexFor(forecast, now)) : null;
  const peakStep = beaufortStep(peak7 ? peak7.gust : forecast.peakGust.kn);
  const peakText = peak7 ? peak7.text : peakChipText(forecast, now);
  return {
    html: `
      <div class="hero-main"><span class="hero-kn num">${h.kn}</span><span class="hero-unit">kn</span></div>
      <div class="hero-side">
        <div class="hero-gust num"><span class="g">G</span>${h.gust}</div>
        <div class="hero-dir">${arrowSvg(h.dirFrom, 18)}<span>from ${compassLabel(h.dirFrom)}</span></div>
      </div>
      <div class="hero-right">
        <span class="chip-peak"><span class="dot bft-${beaufortToken(peakStep)}"></span>${esc(peakText)}</span>
        <span class="pill bft-${beaufortToken(step)}" aria-hidden="true"></span>
      </div>`,
    label: heroAriaLabel(h, forecast.fetched, forecast.location.tz),
  };
}

// --- App awareness (docs/design/web-app-awareness/HANDOFF.md) -------------

// The footer card's complication drawing, from the same forecast and clock as
// the chart. Desktop 172×64; phone fills the card width at 76 high.
const comp = { forecast: null, now: null, width: 0 };
function drawComp() {
  const host = $('comp-host');
  const compact = window.innerWidth <= COMPACT_MAX;
  const W = compact ? Math.floor(host.clientWidth) : 172;
  if (W <= 0) return;
  comp.width = W;
  host.innerHTML = compMiniHtml(comp.forecast, comp.now, compact ? { W, H: 76 } : { W: 172, H: 64 });
}
function renderComp(forecast, now) {
  comp.forecast = forecast;
  comp.now = now;
  drawComp();
}

// §4: three events (+ strip dismiss). gtag is absent when blocked; never throw.
function track(name) {
  try {
    if (typeof window.gtag === 'function') window.gtag('event', name, { transport_type: 'beacon' });
  } catch { /* analytics is best-effort */ }
}

let awarenessInstalled = false;
function installAwareness() {
  if (awarenessInstalled) return;
  awarenessInstalled = true;

  document.addEventListener('click', (e) => {
    const a = e.target.closest('[data-event]');
    if (a) track(a.dataset.event);
  });

  // Redraw the phone-width drawing when the card width changes.
  if ('ResizeObserver' in window) {
    new ResizeObserver(() => {
      const host = $('comp-host');
      if (window.innerWidth <= COMPACT_MAX && Math.floor(host.clientWidth) !== comp.width) drawComp();
    }).observe($('comp-host'));
  }

  // §1.4 strip: iOS non-Safari only, 30 days after a dismissal. Decided once per load.
  let dismissedAt = null;
  try { dismissedAt = localStorage.getItem(STRIP_KEY); } catch { /* private mode */ }
  const show = shouldShowStrip({ ua: navigator.userAgent, maxTouchPoints: navigator.maxTouchPoints || 0, dismissedAt });
  if (!show && new URLSearchParams(location.search).get('strip') !== '1') return;
  const strip = $('app-strip');
  strip.classList.remove('hidden');
  $('app-strip-close').addEventListener('click', () => {
    try { localStorage.setItem(STRIP_KEY, String(Date.now())); } catch { /* still hide it */ }
    track('app_strip_dismiss');
    const gap = parseFloat(getComputedStyle($('page')).rowGap) || 0;
    strip.style.height = `${strip.offsetHeight}px`;
    void strip.offsetHeight; // commit the start height before animating
    strip.style.height = '0px';
    strip.style.marginBottom = `${-gap}px`;
    strip.style.opacity = '0';
    const done = () => strip.remove();
    strip.addEventListener('transitionend', (ev) => { if (ev.propertyName === 'height') done(); });
    setTimeout(done, 400);
  }, { once: true });
}

// --- Render --------------------------------------------------------------

const layoutKey = () => `${window.innerWidth >= WIDE_MIN ? 'wide' : 'narrow'}/${window.innerWidth <= COMPACT_MAX ? 'compact' : 'full'}`;
let lastLayoutKey = null;

function render(ctx, opts) {
  const { forecast, now, state } = ctx;
  const page = $('page');
  page.className = `page state-${state.kind}`;
  document.title = forecast ? `Wind Watch — ${forecast.location.name}` : 'Wind Watch';
  lastLayoutKey = layoutKey();

  if (state.kind === 'firstrun') {
    $('location').textContent = 'Wind Watch';
    $('trust').className = 'trust';
    $('trust').textContent = '';
    $('hero').innerHTML = `<div class="hero-main"><span class="hero-kn num dash">—</span><span class="hero-unit">kn</span></div>`;
    $('hero').setAttribute('aria-label', 'No data yet');
    $('summary').textContent = ctx.reason === 'no_data'
      ? 'No data yet. The server has not baked a forecast yet.'
      : 'No data yet. Needs cellular or Wi-Fi once.';
    $('chart-card').classList.add('hidden');
    $('table-card').classList.add('hidden');
    $('unit-ctl').classList.add('hidden');
    $('footer-right').innerHTML = `<span class="trying"><span class="ring" aria-hidden="true"></span>trying…</span>`;
    chartState.layout = null;
    renderComp(null, now);
    return;
  }

  const tz = forecast.location.tz;
  const nowIdx = nowIndexFor(forecast, now);
  const wide = window.innerWidth >= WIDE_MIN;
  const compact = window.innerWidth <= COMPACT_MAX;
  $('location').textContent = forecast.location.name;

  const range = prefs.range;
  const tl = trustLine(forecast, state, tz, { compact, range, now });
  const trust = $('trust');
  trust.className = `trust${tl.amber ? ' amber' : ''}`;
  const tlText = tl.segments
    ? tl.segments.map((g) => `<span class="${g.amber ? 'seg-amber' : ''}">${esc(g.text)}</span>`).join('')
    : esc(tl.text);
  trust.innerHTML = `${tl.glyph === 'wifi-slash' ? WIFI_SLASH : ''}${tl.glyph === 'ring' ? '<span class="ring" aria-hidden="true"></span>' : ''}<span>${tlText}</span>`;

  const hero = buildHero(forecast, now, range);
  $('hero').innerHTML = hero.html;
  $('hero').setAttribute('aria-label', hero.label);

  $('summary').textContent = forecast.summary;

  const layout = chartLayout(forecast, wide ? CHART_STYLES.desktop : CHART_STYLES.phone, { nowIdx, range });
  chartState.forecast = forecast;
  chartState.layout = layout;
  chartState.wide = wide;
  chartState.sel = null;
  $('chart-card').classList.remove('hidden');
  $('chart-title').textContent = rangeTitle(forecast, range);
  $('chart-hint').textContent = rangeHint(forecast, range, { mode: layout.mode });
  $('chart-head').classList.toggle('range-7d', range === '7d');
  syncSegments($('range-ctl'), range);
  const nbmStale = Boolean(tl.nbmStale);
  $('chart-host').innerHTML = buildChart(forecast, layout, { nbmStale });
  $('chart-tip').classList.add('hidden');
  $('legend').innerHTML = buildLegend(range, forecast);
  installChartInteraction();
  if (opts.hover != null) setSelection(opts.hover);

  $('table-card').classList.remove('hidden');
  $('table-caption').textContent = tableCaption(forecast, nowIdx, { compact, range });
  $('table-wrap').innerHTML = buildTable(forecast, nowIdx, compact, range);
  installTableDisclosure();

  // °F | °C lives in the footer; shown only when the payload carries temperature.
  $('unit-ctl').classList.toggle('hidden', forecast.hours[0].temp == null);
  syncSegments($('unit-seg'), prefs.unit);

  $('attribution').innerHTML = `Wind Watch · weather data by <a href="https://open-meteo.com/" rel="noopener">Open-Meteo.com</a> · HRRR 3 km · times in ${esc(tzAbbrev(forecast.start, tz))}`;
  $('footer-right').textContent = '';
  renderComp(forecast, now);
}

// --- Boot ------------------------------------------------------------------

// Shared: pick the clock, compute the trust state, render. `?state=` forces a
// state for verification in either mode; `?now=` pins the clock.
function makeCompute(ctx, opts, { liveClock }) {
  const clock = () => {
    if (opts.now) return opts.now;
    if (opts.live || (liveClock && !opts.state)) return new Date();
    return ctx.forecast ? defaultNow(ctx.forecast, opts.state) : new Date();
  };
  return () => {
    ctx.now = clock();
    ctx.state = trustState({
      forecast: ctx.forecast,
      now: ctx.now,
      lastCheckOK: opts.state === 'offline' ? false : ctx.lastCheckOK,
      updating: opts.state === 'updating' || ctx.updating,
    });
    if (ctx.forecast && opts.state === 'fresh' && !opts.now && !opts.live) {
      ctx.state = { ...ctx.state, kind: 'fresh', tier: 'fresh' };
    }
    render(ctx, opts);
  };
}

function watchResize(compute) {
  let raf = 0;
  window.addEventListener('resize', () => {
    if (layoutKey() === lastLayoutKey) return;
    cancelAnimationFrame(raf);
    raf = requestAnimationFrame(compute);
  });
}

// Fixture mode (apiBase === ""): load the reference payload once, clock pinned
// to start + 30 min unless ?now= says otherwise.
async function bootFixture(opts) {
  const ctx = { forecast: null, now: new Date(), state: null, lastCheckOK: true, updating: false, reason: null };
  if (opts.state !== 'firstrun') {
    try {
      ctx.forecast = toForecast(adjustPayload(await loadFixture(), opts));
    } catch (err) {
      console.error('Wind Watch: could not load fixture', err);
    }
  }
  const compute = makeCompute(ctx, opts, { liveClock: false });
  installControls(compute);
  compute();
  if (opts.live) setInterval(compute, MINUTE_MS);
  watchResize(compute);
}

// Live mode: first paint from the localStorage cache (updating ring, never a
// spinner over numbers), then a conditional GET; re-check every 10 min while
// visible; re-render the trust line every minute on the live clock.
async function bootLive(opts, base) {
  const ctx = { forecast: null, now: new Date(), state: null, lastCheckOK: true, updating: false, reason: null };
  let record = opts.state === 'firstrun' ? null : readCache();
  let inFlight = false;

  const adopt = (rec) => {
    try {
      ctx.forecast = toForecast(adjustPayload(rec.body, opts));
      ctx.lastCheckOK = rec.lastCheckOK;
      return true;
    } catch (err) {
      console.error('Wind Watch: cached payload unusable', err);
      return false;
    }
  };

  const compute = makeCompute(ctx, opts, { liveClock: true });
  installControls(compute);

  if (record && adopt(record)) {
    ctx.updating = true;
    compute();
  }

  const check = async () => {
    if (inFlight) return;
    inFlight = true;
    if (ctx.forecast && !ctx.updating) {
      ctx.updating = true;
      compute();
    }
    const outcome = await checkLive(base, record ? record.etag : null);
    const next = recordAfterCheck(record, outcome);
    if (next) {
      const changed = outcome.status === 200;
      record = next;
      writeCache(record);
      if (changed || !ctx.forecast) adopt(record);
      else ctx.lastCheckOK = record.lastCheckOK;
    } else {
      ctx.forecast = null;
      ctx.lastCheckOK = false;
      ctx.reason = outcome.code === 'no_data' ? 'no_data' : 'network';
      if (outcome.status !== 503) console.error('Wind Watch: check failed', outcome.status, outcome.error || outcome.code || '');
    }
    ctx.updating = false;
    inFlight = false;
    compute();
  };

  await check();

  setInterval(compute, MINUTE_MS);
  setInterval(() => {
    if (document.visibilityState === 'visible') check();
  }, CHECK_MS);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'visible') return;
    const since = record ? Date.now() - record.lastChecked : Infinity;
    if (since >= CHECK_MS || !ctx.forecast) check();
  });
  watchResize(compute);
}

function main() {
  const opts = readOptions();
  loadPrefs(opts);
  installAwareness();
  // ?fixture=1 forces fixture mode (the reference payload) whatever config.js says.
  const base = new URLSearchParams(location.search).get('fixture') === '1' ? '' : apiBase();
  return base ? bootLive(opts, base) : bootFixture(opts);
}

main();
