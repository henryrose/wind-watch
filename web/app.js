// Wind Watch — page controller. Everything that depends on "now" or on pixels.
import {
  HOUR_MS,
  MINUTE_MS,
  arrowRotation,
  beaufortStep,
  beaufortToken,
  chartAriaLabel,
  compassLabel,
  formatHH,
  formatHHMM,
  hero as heroFor,
  heroAriaLabel,
  horizonLabel,
  localDayNumber,
  nowIndex as nowIndexFor,
  peakChipText,
  shortDate,
  shortDay,
  sunMarkers,
  toForecast,
  trustLine,
  trustState,
  twilightStops,
  tzAbbrev,
  yDomainMax,
} from './lib/derive.js';
import { CACHE_KEY, parseRecord, recordAfterCheck, serializeRecord } from './lib/cache.js';

const CHECK_MS = 10 * MINUTE_MS;
const KITE = 'M0,-0.5 L0.38,0.5 L0,0.2 L-0.38,0.5 Z';
const STATES = new Set(['fresh', 'stale', 'old', 'offline', 'horizon', 'firstrun', 'updating']);

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const r2 = (n) => Math.round(n * 100) / 100;

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
  return { state, now, live };
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
  const headers = {};
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

// --- Chart (HANDOFF §6.1 web column, §6.4) ---------------------------------

const GEO = {
  wide: { W: 1120, H: 280, top: 28, bottom: 22, plotH: 230, arrowEvery: 1, arrowSize: 10, labelEvery: 3 },
  narrow: { W: 358, H: 200, top: 22, bottom: 16, plotH: 162, arrowEvery: 3, arrowSize: 10, labelEvery: 6 },
};

function buildChart(forecast, now, nowIdx, wide) {
  const g = wide ? GEO.wide : GEO.narrow;
  const tz = forecast.location.tz;
  const hours = forecast.hours;
  const n = hours.length;
  const slot = g.W / n;
  const bw = Math.max(3, 0.72 * slot);
  const plotTop = g.top;
  const plotBottom = g.top + g.plotH;
  const yMax = yDomainMax(hours);
  const y = (v) => plotBottom - (v / yMax) * g.plotH;
  const xAt = (i) => i * slot; // hour boundary i (fractional ok)
  const cx = (i) => (i + 0.5) * slot; // bar centre
  const out = [];

  // Shading: one rect, horizontal gradient from the twilight stops.
  const stops = twilightStops(forecast);
  const gradient = (id, valueOf) =>
    `<linearGradient id="${id}" x1="0" y1="0" x2="1" y2="0">${stops
      .map((s) => `<stop offset="${r2(s.offset * 100)}%" stop-color="${id.endsWith('day') ? '#fff' : '#000'}" stop-opacity="${r2(valueOf(s.value))}"/>`)
      .join('')}</linearGradient>`;
  out.push(`<defs>${gradient('ww-shade-day', (v) => v)}${gradient('ww-shade-night', (v) => 1 - v)}</defs>`);
  out.push(`<rect class="shade-day" x="0" y="${plotTop}" width="${g.W}" height="${g.plotH}"/>`);
  out.push(`<rect class="shade-night" x="0" y="${plotTop}" width="${g.W}" height="${g.plotH}"/>`);

  // Gridlines every 10 kn, baseline included; labels right-aligned in the card gutter.
  for (let v = 0; v <= yMax; v += 10) {
    out.push(`<line class="grid" x1="0" x2="${g.W}" y1="${r2(y(v))}" y2="${r2(y(v))}"/>`);
    if (v > 0) out.push(`<text class="grid-label" x="-6" y="${r2(y(v) + 4)}" text-anchor="end">${v}</text>`);
  }

  // Bars (sustained), Beaufort-stepped fill, 1 px stub at 0 kn.
  for (let i = 0; i < n; i++) {
    const h = hours[i];
    const top = h.kn > 0 ? y(h.kn) : plotBottom - 1;
    const x = r2(cx(i) - bw / 2);
    const step = beaufortStep(h.kn);
    const token = beaufortToken(step);
    out.push(`<rect class="bar bft-${token}" x="${x}" y="${r2(top)}" width="${r2(bw)}" height="${r2(plotBottom - top)}" rx="1.5"/>`);
    if (step >= 10) {
      out.push(`<rect class="bar-inset" x="${r2(x + 1)}" y="${r2(top + 1)}" width="${r2(bw - 2)}" height="${r2(Math.max(0, plotBottom - top - 2))}" rx="1"/>`);
    }
  }

  // Gust polyline through cap centres, then caps (bar + 2 wide).
  out.push(`<polyline class="gust-line" points="${hours.map((h, i) => `${r2(cx(i))},${r2(y(h.gust))}`).join(' ')}"/>`);
  for (let i = 0; i < n; i++) {
    const gy = r2(y(hours[i].gust));
    out.push(`<line class="gust-cap" x1="${r2(cx(i) - bw / 2 - 1)}" x2="${r2(cx(i) + bw / 2 + 1)}" y1="${gy}" y2="${gy}"/>`);
  }

  // Time ticks every 3 h at hour boundaries; labels sit inside the plot bottom
  // (the bottom inset is the arrow row). Day name at 00:00.
  for (let i = 0; i < n; i++) {
    const t = new Date(forecast.start.getTime() + i * HOUR_MS);
    const hh = formatHH(t, tz);
    if (Number(hh) % 3 !== 0) continue;
    const x = r2(xAt(i));
    out.push(`<line class="tick" x1="${x}" x2="${x}" y1="${plotBottom - 3}" y2="${plotBottom}"/>`);
    if (Number(hh) % g.labelEvery !== 0) continue;
    const day = hh === '00' ? `<tspan class="day">${shortDay(t, tz)} </tspan>` : '';
    out.push(`<text class="tick-label" x="${r2(x + 4)}" y="${plotBottom - 6}">${day}${hh}</text>`);
  }

  // Arrows in the bottom inset, pointing TO.
  const ay = r2(plotBottom + g.bottom / 2);
  for (let i = 0; i < n; i += g.arrowEvery) {
    out.push(`<path class="arrow" d="${KITE}" transform="translate(${r2(cx(i))} ${ay}) rotate(${arrowRotation(hours[i].dirFrom)}) scale(${g.arrowSize})"/>`);
  }

  // Sun dots at sunrise/sunset on the plot's top edge.
  for (const s of sunMarkers(forecast)) {
    out.push(`<circle class="sun" cx="${r2(s.offset * g.W)}" cy="${plotTop - 1}" r="3"><title>${s.kind === 'rise' ? 'sunrise' : 'sunset'} ${formatHHMM(s.at, tz)}</title></circle>`);
  }

  // Now marker (only when inside the plotted range).
  if (nowIdx >= 0 && nowIdx <= n) {
    const x = r2(xAt(nowIdx));
    out.push(`<line class="now-rule" x1="${x}" x2="${x}" y1="${plotTop - 6}" y2="${plotBottom}"/>`);
    out.push(`<text class="now-label" x="${r2(x + 4)}" y="${plotTop - 8}">now</text>`);
  }

  // Horizon edge: the chart ends where the forecast ends.
  const ex = g.W;
  out.push(`<line class="edge-rule" x1="${ex}" x2="${ex}" y1="${plotTop - 6}" y2="${plotBottom}"/>`);
  out.push(`<text class="edge-label" x="${ex - 4}" y="${plotTop - 8}" text-anchor="end">${esc(horizonLabel(forecast, nowIdx))}</text>`);

  return `<svg class="chart ${wide ? 'wide' : 'narrow'}" viewBox="0 0 ${g.W} ${g.H}" role="img" aria-label="${esc(chartAriaLabel(forecast))}">${out.join('')}</svg>`;
}

function buildLegend() {
  const ramp = [['calm', '0–1'], ['2', '2'], ['3', '3'], ['4', '4'], ['5', '5'], ['6', '6'], ['7', '7'], ['8', '8'], ['9', '9'], ['10', '10+']];
  return `
    <span class="legend-item"><span class="legend-ramp">${ramp
      .map(([t, l]) => `<span class="step"><span class="swatch bft-${t}"></span>${l}</span>`)
      .join('')}</span><span>Beaufort, sustained</span></span>
    <span class="legend-item"><svg viewBox="0 0 22 14" aria-hidden="true"><line x1="2" y1="11" x2="20" y2="3" stroke="currentColor" stroke-width="1.5" opacity="0.75"/><line x1="6" y1="7" x2="16" y2="7" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>gust</span>
    <span class="legend-item">${arrowSvg(270, 14)}blowing to</span>
    <span class="legend-item"><span class="sundot"></span>sunrise · sunset</span>`;
}

// --- Table ----------------------------------------------------------------

function buildTable(forecast, nowIdx) {
  const tz = forecast.location.tz;
  const rows = [];
  let lastDay = null;
  const nowRow = Math.floor(nowIdx);
  forecast.hours.forEach((h, i) => {
    const t = new Date(forecast.start.getTime() + i * HOUR_MS);
    const day = localDayNumber(t, tz);
    if (day !== lastDay) {
      lastDay = day;
      rows.push(`<tr class="day-row"><th scope="col">${shortDay(t, tz)} <span class="visually-hidden">(</span>${shortDate(t, tz)}<span class="visually-hidden">)</span></th><th scope="col">kn</th><th scope="col">gust</th><th scope="col">from</th><th scope="col">Bft</th></tr>`);
    }
    const step = beaufortStep(h.kn);
    rows.push(`<tr${i === nowRow ? ' class="now"' : ''}>
      <td class="hour num">${formatHHMM(t, tz)}</td>
      <td class="kn">${h.kn}</td>
      <td class="gust num">G ${h.gust}</td>
      <td class="dir">${arrowSvg(h.dirFrom, 14)}<span>from ${compassLabel(h.dirFrom)}</span></td>
      <td class="bft"><span class="chip bft-${beaufortToken(step)}">${step}</span></td>
    </tr>`);
  });
  return `<table><caption class="visually-hidden">Hourly wind forecast, knots</caption><tbody>${rows.join('')}</tbody></table>`;
}

// --- Hero ------------------------------------------------------------------

function buildHero(forecast, now, state) {
  const h = heroFor(forecast, now);
  if (!h) {
    return {
      html: `<div class="hero-main"><span class="hero-kn num dash">—</span><span class="hero-unit">kn</span></div>`,
      label: 'No forecast',
    };
  }
  const step = beaufortStep(h.kn);
  const peakStep = beaufortStep(forecast.peakGust.kn);
  return {
    html: `
      <div class="hero-main"><span class="hero-kn num">${h.kn}</span><span class="hero-unit">kn</span></div>
      <div class="hero-side">
        <div class="hero-gust num"><span class="g">G</span>${h.gust}</div>
        <div class="hero-dir">${arrowSvg(h.dirFrom, 18)}<span>from ${compassLabel(h.dirFrom)}</span></div>
      </div>
      <div class="hero-right">
        <span class="chip-peak"><span class="dot bft-${beaufortToken(peakStep)}"></span>${esc(peakChipText(forecast, now))}</span>
        <span class="pill bft-${beaufortToken(step)}" aria-hidden="true"></span>
      </div>`,
    label: heroAriaLabel(h, forecast.fetched, forecast.location.tz),
  };
}

// --- Render --------------------------------------------------------------

let lastWide = null;

function render(ctx) {
  const { forecast, now, state } = ctx;
  const page = $('page');
  page.className = `page state-${state.kind}`;
  document.title = forecast ? `${forecast.location.name} · Wind Watch` : 'Wind Watch';

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
    $('table-wrap').classList.add('hidden');
    $('footer-right').innerHTML = `<span class="trying"><span class="ring" aria-hidden="true"></span>trying…</span>`;
    return;
  }

  const tz = forecast.location.tz;
  const nowIdx = nowIndexFor(forecast, now);
  $('location').textContent = forecast.location.name;

  const tl = trustLine(forecast, state, tz);
  const trust = $('trust');
  trust.className = `trust${tl.amber ? ' amber' : ''}`;
  trust.innerHTML = `${tl.glyph === 'wifi-slash' ? WIFI_SLASH : ''}${tl.glyph === 'ring' ? '<span class="ring" aria-hidden="true"></span>' : ''}<span>${esc(tl.text)}</span>`;

  const hero = buildHero(forecast, now, state);
  $('hero').innerHTML = hero.html;
  $('hero').setAttribute('aria-label', hero.label);

  $('summary').textContent = forecast.summary;

  const wide = window.innerWidth >= 900;
  $('chart-card').classList.remove('hidden');
  $('chart-sub').textContent = `${forecast.hours.length} h · gusts to ${forecast.peakGust.kn} kn`;
  $('chart-host').innerHTML = buildChart(forecast, now, nowIdx, wide);
  lastWide = wide;
  if (!$('legend').innerHTML) $('legend').innerHTML = buildLegend();

  $('table-wrap').classList.remove('hidden');
  $('table-wrap').innerHTML = buildTable(forecast, nowIdx);

  $('footer-right').textContent = `times in ${tzAbbrev(forecast.start, tz)}`;
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
    render(ctx);
  };
}

function watchResize(compute) {
  let raf = 0;
  window.addEventListener('resize', () => {
    const wide = window.innerWidth >= 900;
    if (wide === lastWide) return;
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
      ctx.forecast = toForecast(await loadFixture());
    } catch (err) {
      console.error('Wind Watch: could not load fixture', err);
    }
  }
  const compute = makeCompute(ctx, opts, { liveClock: false });
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
      ctx.forecast = toForecast(rec.body);
      ctx.lastCheckOK = rec.lastCheckOK;
      return true;
    } catch (err) {
      console.error('Wind Watch: cached payload unusable', err);
      return false;
    }
  };

  const compute = makeCompute(ctx, opts, { liveClock: true });

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
  const base = apiBase();
  return base ? bootLive(opts, base) : bootFixture(opts);
}

main();
