// Wind Watch — derivations from the wire payload (DESIGN.md §4.2) to the
// forecast view model (HANDOFF §2) and everything the page computes from it.
// Pure ES module: no DOM, importable by Node for `node --test`.
//
// All times are Dates; all wind values are integers in knots. Local-time
// formatting always goes through Intl with the payload's tz, never the machine
// zone.

import { sunDays } from './sun.js';

export const HOUR_MS = 3_600_000;
export const MINUTE_MS = 60_000;

// --- Tokens ---------------------------------------------------------------

// HANDOFF §4.1. styles.css carries the same hexes as custom properties; the
// test suite asserts the two stay in sync.
export const BEAUFORT_RAMP = {
  calm: { dark: '#5C6B7A', light: '#8A97A6' },
  2: { dark: '#4FA3D8', light: '#2A86C4' },
  3: { dark: '#3FC2A0', light: '#1E9E80' },
  4: { dark: '#8DD44A', light: '#5FA82E' },
  5: { dark: '#F2D13D', light: '#C9A800' },
  6: { dark: '#F59A2B', light: '#E07F12' },
  7: { dark: '#EC5A2A', light: '#D6451A' },
  8: { dark: '#E0245E', light: '#C7154B' },
  9: { dark: '#A32CD1', light: '#8C1FB3' },
  10: { dark: '#F5F5F7', light: '#1B1B1F' },
};

const COMPASS8 = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
const COMPASS8_WORDS = ['north', 'northeast', 'east', 'southeast', 'south', 'southwest', 'west', 'northwest'];

// --- Scalar derivations ---------------------------------------------------

// HANDOFF §2 Beaufort table. B0 (0 kn) and B1 (1–3 kn) share a colour but
// keep their own step numbers for the table chip; 10/11/12 likewise.
export function beaufortStep(kn) {
  if (kn <= 0) return 0;
  if (kn <= 3) return 1;
  if (kn <= 6) return 2;
  if (kn <= 10) return 3;
  if (kn <= 16) return 4;
  if (kn <= 21) return 5;
  if (kn <= 27) return 6;
  if (kn <= 33) return 7;
  if (kn <= 40) return 8;
  if (kn <= 47) return 9;
  if (kn <= 55) return 10;
  if (kn <= 63) return 11;
  return 12;
}

// Colour token name for a step: 'calm', '2' … '9', '10'.
export function beaufortToken(step) {
  if (step <= 1) return 'calm';
  if (step >= 10) return '10';
  return String(step);
}

function norm360(deg) {
  return ((deg % 360) + 360) % 360;
}

function compassIndex(dirFrom) {
  return Math.floor((norm360(dirFrom) + 22.5) / 45) % 8;
}

export function compassLabel(dirFrom) {
  return COMPASS8[compassIndex(dirFrom)];
}

export function compassWord(dirFrom) {
  return COMPASS8_WORDS[compassIndex(dirFrom)];
}

// Arrows point TO: rotate the kite by dirFrom + 180.
export function arrowRotation(dirFrom) {
  return norm360(dirFrom + 180);
}

// Y domain: 0 … max(20, ceil((maxGust + 3) / 10) × 10), over the hours plotted.
export function yDomainMax(hours) {
  let maxGust = 0;
  for (const h of hours) if (h.gust > maxGust) maxGust = h.gust;
  return Math.max(20, Math.ceil((maxGust + 3) / 10) * 10);
}

// "HRRR 15Z" from the run's unix init time.
export function runLabel(latestUnix) {
  const h = new Date(latestUnix * 1000).getUTCHours();
  return `HRRR ${String(h).padStart(2, '0')}Z`;
}

// --- Wire payload → view model (IMPLEMENTATION_PLAN §0) -------------------

export function toForecast(payload, { isDefault = true } = {}) {
  if (!payload || payload.v !== 1) throw new Error('unsupported payload version');
  const n = payload.hours;
  if (!Number.isInteger(n) || n < 1) throw new Error('payload has no hours');
  for (const key of ['kn', 'gust', 'dir']) {
    if (!Array.isArray(payload[key]) || payload[key].length < n) {
      throw new Error(`payload.${key} shorter than hours`);
    }
  }
  const start = new Date(payload.start * 1000);
  // §4.2a: temp / cloud / precip are optional; a missing or short array is
  // treated as absent (no sky band, no temperature text), never an error.
  const opt = (a) => (Array.isArray(a) && a.length >= n ? a : null);
  const temp = opt(payload.temp);
  const cloud = opt(payload.cloud);
  const precip = opt(payload.precip);
  const hours = [];
  for (let i = 0; i < n; i++) {
    hours.push({
      kn: payload.kn[i],
      gust: payload.gust[i],
      dirFrom: payload.dir[i],
      temp: temp ? temp[i] : null,
      cloud: cloud ? cloud[i] : null,
      precip: precip ? precip[i] : null,
    });
  }
  const location = {
    name: payload.loc.name,
    lat: payload.loc.lat,
    lon: payload.loc.lon,
    tz: payload.loc.tz,
    isDefault,
  };
  const extended = toExtended(payload.extended, start);
  const paySun = (payload.sun || []).map((d) => ({
    dawn: new Date(d.dawn * 1000),
    rise: new Date(d.rise * 1000),
    set: new Date(d.set * 1000),
    dusk: new Date(d.dusk * 1000),
  }));
  return {
    location,
    model: payload.model,
    run: runLabel(payload.run.latest),
    runAt: new Date(payload.run.latest * 1000),
    fetched: new Date(payload.fetched * 1000),
    start,
    horizon: new Date(start.getTime() + (n - 1) * HOUR_MS),
    hours,
    extended,
    sun: extended ? fillSunDays(paySun, location, start, extended.end) : paySun,
    summary: payload.summary || '',
    peakGust: { kn: payload.peak.gust, at: new Date(payload.peak.at * 1000) },
  };
}

// "NBM 13Z" from the NBM init time.
export function nbmRunLabel(runUnix) {
  const h = new Date(runUnix * 1000).getUTCHours();
  return `NBM ${String(h).padStart(2, '0')}Z`;
}

// §4.2a `extended` → { model, run, runAt, fetched, step, from, fromIdx, end,
// blocks: [{ t, w, start, kn, gust, dirFrom, temp, cloud, precip }] } where t
// is hours since `start`. null when absent or malformed (the page then treats
// NBM as unavailable). The server enforces `from`; the client never filters.
export function toExtended(ext, start) {
  if (!ext || typeof ext !== 'object') return null;
  const nb = ext.blocks;
  const step = Number.isFinite(ext.step) && ext.step > 0 ? ext.step : 3;
  if (!Number.isInteger(nb) || nb < 1 || !Number.isFinite(ext.from)) return null;
  for (const key of ['kn', 'gust', 'dir']) {
    if (!Array.isArray(ext[key]) || ext[key].length < nb) return null;
  }
  const opt = (a) => (Array.isArray(a) && a.length >= nb ? a : null);
  const temp = opt(ext.temp);
  const cloud = opt(ext.cloud);
  const precip = opt(ext.precip);
  const from = new Date(ext.from * 1000);
  const fromIdx = (from.getTime() - start.getTime()) / HOUR_MS;
  const blocks = [];
  for (let b = 0; b < nb; b++) {
    blocks.push({
      t: fromIdx + b * step,
      w: step,
      start: new Date(from.getTime() + b * step * HOUR_MS),
      kn: ext.kn[b],
      gust: ext.gust[b],
      dirFrom: ext.dir[b],
      temp: temp ? temp[b] : null,
      cloud: cloud ? cloud[b] : null,
      precip: precip ? precip[b] : null,
    });
  }
  return {
    model: 'NBM',
    run: Number.isFinite(ext.run) ? nbmRunLabel(ext.run) : 'NBM',
    runAt: Number.isFinite(ext.run) ? new Date(ext.run * 1000) : null,
    fetched: new Date((Number.isFinite(ext.fetched) ? ext.fetched : ext.from) * 1000),
    step,
    from,
    fromIdx,
    end: new Date(from.getTime() + nb * step * HOUR_MS),
    blocks,
  };
}

// The payload's `sun` covers the HRRR days only; the 7-day chart needs a
// marker every day, so missing days are computed here with the same NOAA
// algorithm the Worker uses (lib/sun.js). Payload days always win.
function fillSunDays(paySun, loc, start, end) {
  if (!Number.isFinite(loc.lat) || !Number.isFinite(loc.lon) || !loc.tz) return paySun;
  let computed;
  try {
    const hours = Math.ceil((end.getTime() - start.getTime()) / HOUR_MS);
    computed = sunDays({ lat: loc.lat, lon: loc.lon, tz: loc.tz, start: start.getTime() / 1000, hours });
  } catch {
    return paySun;
  }
  const out = [...paySun];
  for (const d of computed) {
    const rise = d.rise * 1000;
    if (out.some((p) => Math.abs(p.rise.getTime() - rise) < 12 * HOUR_MS)) continue;
    out.push({ dawn: new Date(d.dawn * 1000), rise: new Date(rise), set: new Date(d.set * 1000), dusk: new Date(d.dusk * 1000) });
  }
  return out.sort((a, b) => a.rise.getTime() - b.rise.getTime());
}

// --- Now / hero / trust ---------------------------------------------------

// Fractional hours between start and now. May be negative before start.
export function nowIndex(forecast, now) {
  return (now.getTime() - forecast.start.getTime()) / HOUR_MS;
}

// The plotted range ends one slot past the last hour (the horizon edge).
export function rangeEnd(forecast) {
  return new Date(forecast.horizon.getTime() + HOUR_MS);
}

export function isPastHorizon(forecast, now) {
  return now.getTime() >= rangeEnd(forecast).getTime();
}

// hours[floor(nowIndex)] clamped to 0 for the hero; null past the horizon.
export function hero(forecast, now) {
  if (isPastHorizon(forecast, now)) return null;
  const i = Math.max(0, Math.floor(nowIndex(forecast, now)));
  return { index: i, ...forecast.hours[i] };
}

export const AGE_STALE_MS = 90 * MINUTE_MS;
export const AGE_OLD_MS = 6 * HOUR_MS;

export function ageTier(ageMs) {
  if (ageMs < AGE_STALE_MS) return 'fresh';
  if (ageMs < AGE_OLD_MS) return 'stale';
  return 'old';
}

// HANDOFF §3. Returns { kind, tier, ageMs }.
//   kind ∈ firstrun | horizon | offline | updating | fresh | stale | old
//   tier ∈ fresh | stale | old (null for firstrun) — the age rule, which keeps
//   applying to the numbers even when kind is offline/updating.
export function trustState({ forecast, now, lastCheckOK = true, updating = false }) {
  if (!forecast) return { kind: 'firstrun', tier: null, ageMs: null };
  const ageMs = now.getTime() - forecast.fetched.getTime();
  const tier = ageTier(ageMs);
  if (isPastHorizon(forecast, now)) return { kind: 'horizon', tier, ageMs };
  if (!lastCheckOK) return { kind: 'offline', tier, ageMs };
  if (updating) return { kind: 'updating', tier, ageMs };
  return { kind: tier, tier, ageMs };
}

// Trust-line content for the header. { text, amber, glyph }
//   glyph ∈ null | 'wifi-slash' | 'ring'
// `compact` (under 600 px) drops the word "forecast" from the ends phrase.
// In 7 d with NBM (`range`, `now` given) the line names both runs and adds
// `segments` so the page can amber the NBM run label on its own.
export function trustLine(forecast, state, tz, { compact = false, range = '48h', now = null } = {}) {
  if (state.kind === 'firstrun') {
    return { text: 'No data yet. Needs cellular or Wi-Fi once.', amber: false, glyph: null };
  }
  const asOf = (withDay) =>
    (withDay ? `${shortDay(forecast.fetched, tz)} ` : '') + formatHHMM(forecast.fetched, tz);
  const ends = `${compact ? '' : 'forecast '}ends ${shortDay(forecast.horizon, tz)} ${hour12At(forecast.horizon, tz)}`;
  const old = state.tier === 'old';
  switch (state.kind) {
    case 'horizon':
      return {
        text: `No forecast · last run ${forecast.run} ${shortDay(forecast.runAt, tz)}`,
        amber: true,
        glyph: null,
      };
    case 'offline':
      return {
        text: `Couldn't reach server · showing data from ${asOf(old)}`,
        amber: true,
        glyph: 'wifi-slash',
      };
    case 'updating':
      return { text: `updating · as of ${asOf(old)}`, amber: state.tier !== 'fresh', glyph: 'ring' };
    default: {
      const amber = state.tier !== 'fresh';
      const head = `as of ${asOf(old)} ${tzAbbrev(forecast.fetched, tz)} · ${forecast.run}`;
      if (range === '7d' && forecast.extended && now) {
        // §12a: both runs named; NBM staleness ambers only its run label.
        const ext = forecast.extended;
        const tierN = nbmTier(forecast, now);
        const nbmLabel = tierN === 'old' && ext.runAt ? `${ext.run} ${shortDay(ext.runAt, tz)}` : ext.run;
        const tail = ` · ${compact ? '' : 'forecast '}ends ${shortDay(ext.end, tz)} ${hour12At(ext.end, tz)}`;
        return {
          text: `${head} + ${nbmLabel}${tail}`,
          amber,
          glyph: null,
          segments: [
            { text: `${head} + `, amber },
            { text: nbmLabel, amber: amber || tierN !== 'fresh' },
            { text: tail, amber },
          ],
          nbmStale: tierN !== 'fresh',
        };
      }
      return { text: `${head} · ${ends}`, amber, glyph: null };
    }
  }
}

// --- Twilight shading (HANDOFF §2) ----------------------------------------

// day(t): 1 between sunrise and sunset, 0 between civil dusk and the next
// civil dawn, linear across dawn→rise and set→dusk.
export function dayFraction(t, sun) {
  const ms = t instanceof Date ? t.getTime() : t;
  for (const d of sun) {
    const dawn = d.dawn.getTime();
    const rise = d.rise.getTime();
    const set = d.set.getTime();
    const dusk = d.dusk.getTime();
    if (ms >= rise && ms <= set) return 1;
    if (ms >= dawn && ms < rise) return (ms - dawn) / (rise - dawn);
    if (ms > set && ms <= dusk) return 1 - (ms - set) / (dusk - set);
  }
  return 0;
}

// Gradient stops as fractions of the plotted range [start, horizon + 1 h]:
// one at 0, one at each dawn/rise/set/dusk strictly inside the range, one at
// 1. Values between stops interpolate linearly, which is exactly the ramp.
export function twilightStops(forecast, endDate = rangeEnd(forecast)) {
  const start = forecast.start.getTime();
  const end = endDate.getTime();
  const span = end - start;
  const stops = [{ offset: 0, value: dayFraction(start, forecast.sun) }];
  const events = [];
  for (const d of forecast.sun) {
    for (const k of ['dawn', 'rise', 'set', 'dusk']) events.push(d[k].getTime());
  }
  events.sort((a, b) => a - b);
  for (const e of events) {
    if (e > start && e < end) stops.push({ offset: (e - start) / span, value: dayFraction(e, forecast.sun) });
  }
  stops.push({ offset: 1, value: dayFraction(end, forecast.sun) });
  return stops;
}

// Sun markers at sunrise (filled) and sunset (ring) only, never dawn/dusk,
// as fractions of the plotted range.
export function sunMarkers(forecast, endDate = rangeEnd(forecast)) {
  const start = forecast.start.getTime();
  const end = endDate.getTime();
  const out = [];
  for (const d of forecast.sun) {
    for (const kind of ['rise', 'set']) {
      const t = d[kind].getTime();
      if (t >= start && t <= end) out.push({ kind, offset: (t - start) / (end - start), at: d[kind] });
    }
  }
  return out;
}

// --- Labels ---------------------------------------------------------------

// --- 12-hour time labels (HANDOFF §6.4a) ----------------------------------

// 0 → "12am", 9 → "9am", 12 → "12pm", 15 → "3pm".
export function hour12(h) {
  const x = ((h % 24) + 24) % 24;
  if (x === 0) return '12am';
  if (x === 12) return '12pm';
  return x < 12 ? `${x}am` : `${x - 12}pm`;
}

export function hour12At(date, tz) {
  return hour12(localHour(date, tz));
}

// Axis tick text: "9am · noon · 3pm · 6pm · 9pm · 12am · 3am · 6am".
export function tickLabel(h) {
  return ((h % 24) + 24) % 24 === 12 ? 'noon' : hour12(h);
}

// Chart edge label: "ends Fri 5am".
export function horizonLabel(forecast) {
  const tz = forecast.location.tz;
  return `ends ${shortDay(forecast.horizon, tz)} ${hour12At(forecast.horizon, tz)}`;
}

// Hourly-table disclosure caption (HANDOFF §6.4d): "45 hours · Wed 9am → Fri 5am",
// counted from the now hour; the phone layout shows only "45 hours".
export function tableCaption(forecast, nowIdx, { compact = false, range = '48h' } = {}) {
  const tz = forecast.location.tz;
  if (range === '7d' && forecast.extended) {
    const end = forecast.extended.end;
    const to = `${shortDay(end, tz)} ${hour12At(end, tz)}`;
    if (compact) return `to ${to} · NBM 3-hourly`;
    return `hourly to ${shortDay(forecast.horizon, tz)} ${hour12At(forecast.horizon, tz)}, then 3-hourly to ${to} · NBM rows tagged`;
  }
  const first = Math.min(Math.max(0, Math.floor(nowIdx)), forecast.hours.length);
  const n = forecast.hours.length - first;
  const hours = n === 1 ? '1 hour' : `${n} hours`;
  if (compact || n <= 0) return hours;
  const t = hourAt(forecast, first);
  return `${hours} · ${shortDay(t, tz)} ${hour12At(t, tz)} → ${shortDay(forecast.horizon, tz)} ${hour12At(forecast.horizon, tz)}`;
}

// Hourly-table rows (§12a): HRRR hours, then in 7 d a header row
// "NBM from Fri 6am · 3-hourly" and one row per NBM block.
//   { kind: 'hour', i, slot } | { kind: 'nbm-header', text } | { kind: 'block', slot }
export function tableRows(forecast, range = '48h') {
  const rows = forecast.hours.map((h, i) => ({ kind: 'hour', i, slot: { t: i, w: 1, model: 'HRRR', start: hourAt(forecast, i), ...h } }));
  if (range === '7d' && forecast.extended) {
    const ext = forecast.extended;
    const tz = forecast.location.tz;
    rows.push({ kind: 'nbm-header', text: `NBM from ${shortDay(ext.from, tz)} ${hour12At(ext.from, tz)} · ${ext.step}-hourly` });
    for (const b of ext.blocks) rows.push({ kind: 'block', slot: { ...b, model: 'NBM' } });
  }
  return rows;
}

// Chart card title: "Wed 9am → Fri 5am".
export function chartTitle(forecast) {
  const tz = forecast.location.tz;
  return `${shortDay(forecast.start, tz)} ${hour12At(forecast.start, tz)} → ${shortDay(forecast.horizon, tz)} ${hour12At(forecast.horizon, tz)}`;
}

// Hover / scrub hour label: "Thu 12am · midnight", "Thu 12pm · noon", else "Thu 3pm".
export function scrubLabel(date, tz) {
  const h = localHour(date, tz);
  const base = `${shortDay(date, tz)} ${hour12(h)}`;
  if (h === 0) return `${base} · midnight`;
  if (h === 12) return `${base} · noon`;
  return base;
}

export function hourAt(forecast, i) {
  return new Date(forecast.start.getTime() + i * HOUR_MS);
}

// Peak-gust chip phrase (HANDOFF §8.1). Not pinned down by the docs beyond
// the example set; rules: 05–11 morning, 12–16 afternoon, 17–21 evening,
// 22–01 "around midnight", 02–04 "overnight", prefixed by this/tomorrow/<Day>.
export function relativeTimePhrase(at, now, tz) {
  const atHourFloor = Math.floor(at.getTime() / HOUR_MS);
  const nowHourFloor = Math.floor(now.getTime() / HOUR_MS);
  if (atHourFloor === nowHourFloor) return 'now';
  const h = localHour(at, tz);
  const d = localDayDiff(at, now, tz);
  const past = at.getTime() < now.getTime();

  let band;
  let nightDay = d; // the local day on which the night began
  if (h >= 5 && h < 12) band = 'morning';
  else if (h >= 12 && h < 17) band = 'afternoon';
  else if (h >= 17 && h < 22) band = 'evening';
  else if (h >= 22) band = 'around midnight';
  else if (h < 2) { band = 'around midnight'; nightDay = d - 1; }
  else { band = 'overnight'; nightDay = d - 1; }

  const night = band === 'around midnight' || band === 'overnight';
  if (past) {
    if (night) return nightDay >= -1 && now.getTime() - at.getTime() < 6 * HOUR_MS ? band : 'last night';
    if (d === 0) return `earlier this ${band}`;
    if (d === -1) return `yesterday ${band}`;
    return `${shortDay(at, tz)} ${band}`;
  }
  if (night) {
    if (nightDay <= 0) return band;
    if (nightDay === 1) return 'tomorrow night';
    return `${shortDay(new Date(now.getTime() + nightDay * 24 * HOUR_MS), tz)} night`;
  }
  if (d <= 0) return `this ${band}`;
  if (d === 1) return `tomorrow ${band}`;
  return `${shortDay(at, tz)} ${band}`;
}

export function peakChipText(forecast, now) {
  return `${forecast.peakGust.kn} kn gusts ${relativeTimePhrase(forecast.peakGust.at, now, forecast.location.tz)}`;
}

// HANDOFF §11: "45-hour wind chart: … ends Friday 05:00"
export function chartAriaLabel(forecast, range = '48h') {
  const tz = forecast.location.tz;
  const span = rangeSpan(forecast, range);
  const items = span.nbm ? [...forecast.hours, ...forecast.extended.blocks] : forecast.hours;
  let minKn = Infinity;
  let maxKn = -Infinity;
  let maxGust = 0;
  for (const h of items) {
    if (h.kn < minKn) minKn = h.kn;
    if (h.kn > maxKn) maxKn = h.kn;
    if (h.gust > maxGust) maxGust = h.gust;
  }
  if (span.nbm) {
    const seam = hourAt(forecast, forecast.hours.length - 1);
    return `7-day wind chart: sustained ${minKn} to ${maxKn} knots, gusts to ${maxGust} knots; HRRR hourly to ${longDay(seam, tz)} ${formatHHMM(seam, tz)}, then NBM 3-hourly, ends ${longDay(span.end, tz)} ${formatHHMM(span.end, tz)}`;
  }
  return `${forecast.hours.length}-hour wind chart: sustained ${minKn} to ${maxKn} knots, gusts to ${maxGust} knots, ends ${longDay(forecast.horizon, tz)} ${formatHHMM(forecast.horizon, tz)}`;
}

// HANDOFF §11: "15 knots, gusting 25, from the west, as of 23:30"
export function heroAriaLabel(h, asOf, tz) {
  return `${h.kn} knots, gusting ${h.gust}, from the ${compassWord(h.dirFrom)}, as of ${formatHHMM(asOf, tz)}`;
}

// --- Ranges: 48 h (HRRR only) and 7 d (HRRR, then NBM) — spec §12a --------

export const RANGES = ['48h', '7d'];
export const DEFAULT_RANGE = '48h';
export const SLOT_MIN_PX_PER_HOUR = 4; // under this the whole chart goes 3-hourly

export function parseRange(v) {
  return RANGES.includes(v) ? v : null;
}

// Plotted span for a range: { range, total (hours), end (Date), nbm (bool) }.
// 48 h, or 7 d without NBM, stops at the HRRR edge; never padded.
export function rangeSpan(forecast, range) {
  const n = forecast.hours.length;
  if (range === '7d' && forecast.extended) {
    const ext = forecast.extended;
    return { range, total: ext.fromIdx + ext.blocks.length * ext.step, end: ext.end, nbm: true };
  }
  return { range: range === '7d' ? '7d' : '48h', total: n, end: rangeEnd(forecast), nbm: false };
}

// Slot rule (§12a): under 4 px per hour the whole 7-day chart aggregates to
// 3-hour slots; otherwise HRRR stays hourly to the seam.
export function slotMode(widthPx, totalHours) {
  return widthPx / totalHours < SLOT_MIN_PX_PER_HOUR ? '3-hourly' : 'hourly';
}

function vectorMeanDir(dirs) {
  let x = 0;
  let y = 0;
  for (const d of dirs) {
    x += Math.cos((d * Math.PI) / 180);
    y += Math.sin((d * Math.PI) / 180);
  }
  return norm360(Math.round((Math.atan2(y, x) * 180) / Math.PI));
}

const mean = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;

// HRRR hours in 3-hour blocks from index 0 (last may be short): max
// sustained, max gust, vector-mean direction, mean temp/cloud, max precip.
export function hrrrBlocks(forecast, step = 3) {
  const out = [];
  const hs = forecast.hours;
  for (let s = 0; s < hs.length; s += step) {
    const g = hs.slice(s, s + step);
    const has = (k) => g.every((h) => h[k] != null);
    out.push({
      t: s,
      w: g.length,
      model: 'HRRR',
      start: hourAt(forecast, s),
      kn: Math.max(...g.map((h) => h.kn)),
      gust: Math.max(...g.map((h) => h.gust)),
      dirFrom: vectorMeanDir(g.map((h) => h.dirFrom)),
      temp: has('temp') ? mean(g.map((h) => h.temp)) : null,
      cloud: has('cloud') ? mean(g.map((h) => h.cloud)) : null,
      precip: has('precip') ? Math.max(...g.map((h) => h.precip)) : null,
    });
  }
  return out;
}

// The bars of one chart, in order: { t, w, model, start, kn, gust, dirFrom,
// temp, cloud, precip } with t/w in hours since start. 48 h = HRRR hourly.
// 7 d = HRRR hourly (or 3-hourly under the slot rule) to the seam, then the
// NBM blocks.
export function chartSlots(forecast, range, { threeHourly = false } = {}) {
  const hourly = () => forecast.hours.map((h, i) => ({ t: i, w: 1, model: 'HRRR', start: hourAt(forecast, i), ...h }));
  if (range !== '7d') return hourly();
  const hrrr = threeHourly ? hrrrBlocks(forecast) : hourly();
  const nbm = forecast.extended ? forecast.extended.blocks.map((b) => ({ ...b, model: 'NBM' })) : [];
  return [...hrrr, ...nbm];
}

// --- Sky band and readout text (spec §12b, sky_reference.py) ----------------

// cloud % → 'clear' (< 25) | 'partly' (25–70) | 'overcast' (≥ 70)
export function skyTone(cloud) {
  if (cloud == null || !Number.isFinite(cloud)) return null;
  if (cloud < 25) return 'clear';
  if (cloud < 70) return 'partly';
  return 'overcast';
}

const SKY_WORDS = { clear: 'Clear', partly: 'Partly cloudy', overcast: 'Overcast' };
export function skyWord(cloud) {
  const t = skyTone(cloud);
  return t ? SKY_WORDS[t] : null;
}

// mm/h → rain ticks 0 / 1 (< 0.5) / 2 (0.5–1.5) / 3 (≥ 1.5)
export function rainTicks(mm) {
  if (mm == null || !(mm > 0)) return 0;
  if (mm < 0.5) return 1;
  if (mm < 1.5) return 2;
  return 3;
}

export function rainWord(mm) {
  return [null, 'light rain', 'rain', 'heavy rain'][rainTicks(mm)];
}

export const TEMP_UNITS = ['F', 'C'];
export const DEFAULT_TEMP_UNIT = 'F';
export function parseTempUnit(v) {
  const u = typeof v === 'string' ? v.toUpperCase() : '';
  return TEMP_UNITS.includes(u) ? u : null;
}

// °C (payload) → integer in the chosen unit; avoids "-0".
export function tempValue(celsius, unit = 'F') {
  if (celsius == null || !Number.isFinite(celsius)) return null;
  const v = Math.round(unit === 'C' ? celsius : (celsius * 9) / 5 + 32);
  return v === 0 ? 0 : v;
}

export function formatTemp(celsius, unit = 'F') {
  const v = tempValue(celsius, unit);
  return v == null ? null : `${v}°${unit}`;
}

// Readout / tooltip tail: ['Overcast', 'rain', '48°F'] — any missing field is
// simply left out.
export function conditionsParts(slot, unit = 'F') {
  return [skyWord(slot.cloud), rainWord(slot.precip), formatTemp(slot.temp, unit)].filter(Boolean);
}

// One sky cell per 3 h: HRRR hours grouped from index 0 (cloud mean, precip
// max, last cell may be short), then (7 d) the NBM blocks as they are.
// Empty when the payload has no cloud cover.
export function skyCells(forecast, range) {
  if (forecast.hours[0].cloud == null) return [];
  const cells = hrrrBlocks(forecast).map((b) => ({ t: b.t, w: b.w, model: 'HRRR', cloud: b.cloud, precip: b.precip }));
  if (range === '7d' && forecast.extended && forecast.extended.blocks[0].cloud != null) {
    for (const b of forecast.extended.blocks) cells.push({ t: b.t, w: b.w, model: 'NBM', cloud: b.cloud, precip: b.precip });
  }
  return cells.map((c) => ({ ...c, tone: skyTone(c.cloud), ticks: rainTicks(c.precip) }));
}

// --- Slot labels (§12a text) ----------------------------------------------

// "12–3pm", "9am–12pm", "9pm–12am", "12–3am".
export function spanText(h0, h1) {
  const a = hour12(h0);
  const b = hour12(h1);
  if (a.slice(-2) === b.slice(-2)) return `${a.slice(0, -2)}–${b}`;
  return `${a}–${b}`;
}

// Tooltip / readout label for a slot: HRRR hour → "Thu 12am · midnight";
// a block → "Sat 12–3pm" (the model tag is added by the caller: ' · NBM').
export function slotLabel(slot, tz) {
  if (slot.w === 1) return scrubLabel(slot.start, tz);
  const h0 = localHour(slot.start, tz);
  return `${shortDay(slot.start, tz)} ${spanText(h0, h0 + slot.w)}`;
}

// Table hour cell for a block (24-hour like the hourly rows): "Fri 06–09".
export function slotTableLabel(slot, tz, { compact = false } = {}) {
  const h0 = localHour(slot.start, tz);
  const pad = (h) => String(((h % 24) + 24) % 24).padStart(2, '0');
  const span = `${pad(h0)}–${pad(h0 + slot.w)}`;
  return compact ? span : `${shortDay(slot.start, tz)} ${span}`;
}

// "ends Tue 9am" for the 7-day edge: the end of the last NBM block.
export function endLabel(forecast, range) {
  const span = rangeSpan(forecast, range);
  if (!span.nbm) return horizonLabel(forecast);
  const tz = forecast.location.tz;
  return `ends ${shortDay(span.end, tz)} ${hour12At(span.end, tz)}`;
}

// Chart card title: "Wed 9am → Fri 5am" (48 h) / "Wed 9am → Tue 9am" (7 d).
export function rangeTitle(forecast, range) {
  if (!rangeSpan(forecast, range).nbm) return chartTitle(forecast);
  const tz = forecast.location.tz;
  const end = forecast.extended.end;
  return `${shortDay(forecast.start, tz)} ${hour12At(forecast.start, tz)} → ${shortDay(end, tz)} ${hour12At(end, tz)}`;
}

// Chart-head hint beside the title in 7 d.
export function rangeHint(forecast, range, { mode = 'hourly' } = {}) {
  const tz = forecast.location.tz;
  const edge = `${shortDay(forecast.horizon, tz)} ${hour12At(forecast.horizon, tz)}`;
  if (range !== '7d') return 'hover or touch a bar for that hour';
  if (!forecast.extended) return `HRRR to ${edge} · NBM unavailable`;
  return `HRRR ${mode === 'hourly' ? 'hourly ' : ''}to ${edge} · NBM 3-hourly beyond · hover for a block`;
}

// Peak chip across the 7-day range (§12a): "peak G32 · Sat 1pm · NBM".
// Scans HRRR from the now hour, then every NBM block; the first maximum wins.
// A block's time is its middle hour. null when nothing is left to scan.
export function rangePeak(forecast, nowIdx) {
  const tz = forecast.location.tz;
  let best = null;
  const first = Math.max(0, Math.floor(nowIdx));
  for (let i = first; i < forecast.hours.length; i++) {
    const g = forecast.hours[i].gust;
    if (!best || g > best.gust) best = { gust: g, at: hourAt(forecast, i), model: 'HRRR' };
  }
  for (const b of forecast.extended ? forecast.extended.blocks : []) {
    if (!best || b.gust > best.gust) best = { gust: b.gust, at: new Date(b.start.getTime() + Math.floor(b.w / 2) * HOUR_MS), model: 'NBM' };
  }
  if (!best) return null;
  return { ...best, text: `peak G${best.gust} · ${shortDay(best.at, tz)} ${hour12At(best.at, tz)}${best.model === 'NBM' ? ' · NBM' : ''}` };
}

// NBM staleness on its own clock (extended.fetched), same 90 min / 6 h tiers.
export function nbmTier(forecast, now) {
  if (!forecast.extended) return null;
  return ageTier(now.getTime() - forecast.extended.fetched.getTime());
}

// --- Chart layout (port of docs/design/reference/chart_reference.py::svg,
//     and of handoff-2026-10-26/reference/mixed_reference.py for 7 d) ------
//
// Everything is derived from the per-hour width (W / plotted hours) in
// viewBox units; the page scales the SVG to 100 % width. Styles are the two
// web breakpoints (HANDOFF §6.5, §6.4a): desktop ≥ 900 px, phone below.

export const CHART_STYLES = {
  desktop: { W: 1120, H: 300, top: 40, bot: 22, arrowEvery: 1, tickEvery: 3, labelEvery: 3, font: 12, arrowSize: 10, dayBand: true },
  phone: { W: 358, H: 200, top: 22, bot: 16, arrowEvery: 3, tickEvery: 6, labelEvery: 6, font: 11, arrowSize: 9, dayBand: false },
};

// Dark: white 7 % × day; light: black 8 % × (1 − day) (HANDOFF §6.1).
export const SHADE_DAY_ALPHA = 0.07;
export const SHADE_NIGHT_ALPHA = 0.08;

// Sky band: 14 high, plus a 2 gap, above everything else in the SVG.
export const SKY_BAND_H = 14;
export const SKY_BAND_GAP = 2;

// Rough text width for edge-clipping decisions (system UI digits/letters).
const textHalfWidth = (text, font) => text.length * font * 0.3;

// Layout model for one chart. nowIdx is fractional hours since start (null
// hides the now marker). Returns only numbers and labels; the page turns it
// into SVG and the tests compare it with the reference SVGs.
export function chartLayout(forecast, style, { nowIdx = null, range = '48h' } = {}) {
  const { W, H, top, bot, font, arrowSize } = style;
  const tz = forecast.location.tz;
  const span = rangeSpan(forecast, range);
  const seven = span.range === '7d';
  const total = span.total;
  const mode = seven ? slotMode(W, total) : 'hourly';
  const slots = chartSlots(forecast, span.range, { threeHourly: mode === '3-hourly' });
  const n = slots.length;
  const hrrrN = forecast.hours.length;
  const plotH = H - top - bot;
  const plotBottom = top + plotH;
  const slot = W / total; // width of one hour
  const yMax = yDomainMax(slots);
  const X = (t) => t * slot;
  const Y = (v) => top + plotH - (v / yMax) * plotH;
  const barW = (w) => Math.max(3, Math.round(w * slot * 0.72 * 100) / 100);
  const bw = barW(1);
  const capW = bw + 2;

  const grid = [];
  for (let v = 10; v < yMax; v += 10) grid.push({ v, y: Y(v), labelX: W - 2, labelY: Y(v) - 3 });

  // Sunrise filled, sunset ring (§5); nothing at dawn/dusk.
  const sun = sunMarkers(forecast, span.end).map((s) => ({ kind: s.kind, x: s.offset * W, y: top - 1, at: s.at }));

  // Bars sit on the baseline; 0 kn is a 1 px stub.
  const bars = slots.map((s, i) => {
    const w = barW(s.w);
    const y = s.kn > 0 ? Y(s.kn) : plotBottom - 1;
    const step = beaufortStep(s.kn);
    return { i, t: s.t, model: s.model, x: X(s.t) + (s.w * slot - w) / 2, y, w, h: plotBottom - y, step, token: beaufortToken(step) };
  });

  const gust = slots.map((s, i) => ({ i, model: s.model, x: X(s.t) + (s.w * slot) / 2, y: Y(s.gust), capW: barW(s.w) + 2 }));

  // Arrows: 48 h per style; 7 d every 3 h (hourly) or 6 h (3-hourly), on
  // slot starts that fall on the cadence.
  const arrows = [];
  const every = seven ? (mode === '3-hourly' ? 6 : 3) : style.arrowEvery;
  slots.forEach((s, i) => {
    if (s.t % every !== 0) return;
    arrows.push({ i, model: s.model, x: X(s.t) + (s.w * slot) / 2, y: plotBottom + bot / 2, rot: arrowRotation(s.dirFrom) });
  });

  // 48 h: ticks and 12-hour labels on hour-of-day cadence (3 h at hours
  // divisible by 3, 6 h at 03/09/15/21, both anchored on 9am); a label that
  // would be clipped by the plot edge is dropped (item 3). Day band above the
  // plot: name at each midnight; the first day's name only when `now` is not
  // at the plot start (the readout already names the day).
  // 7 d: no hour labels; day names centred per day on the bottom axis and a
  // dotted divider at every midnight.
  const onCadence = (hod, every_) => hod % every_ === 3 % every_;
  const ticks = [];
  const labels = [];
  const days = [];
  const nowAtStart = nowIdx != null && nowIdx >= 0 && nowIdx < 1;
  if (!seven) {
    for (let i = 0; i < hrrrN; i++) {
      const t = hourAt(forecast, i);
      const hod = localHour(t, tz);
      const cx = X(i) + slot / 2;
      if (onCadence(hod, style.tickEvery)) ticks.push({ i, x: cx, y1: plotBottom, y2: plotBottom + 3 });
      if (onCadence(hod, style.labelEvery)) {
        const text = tickLabel(hod);
        const half = textHalfWidth(text, font);
        if (cx - half >= 0 && cx + half <= W) labels.push({ i, x: cx, y: H + 10, text });
      }
      if (style.dayBand && (i === 0 || hod === 0)) {
        days.push({
          i,
          x: X(i),
          name: shortDay(t, tz),
          labelX: X(i) + (i > 0 ? 5 : 4),
          labelY: top - 22,
          anchor: 'start',
          divider: i > 0 ? { x: X(i), y1: top - 18, y2: plotBottom } : null,
          hidden: i === 0 && nowAtStart,
        });
      }
    }
  } else {
    // Midnights inside the range, found hour by hour (DST-safe).
    const bounds = [0];
    for (let h = 1; h < total; h++) if (localHour(hourAt(forecast, h), tz) === 0) bounds.push(h);
    bounds.push(total);
    for (let k = 0; k < bounds.length - 1; k++) {
      const h0 = bounds[k];
      const h1 = bounds[k + 1];
      const x0 = X(h0);
      const cx = X((h0 + h1) / 2);
      const name = shortDay(hourAt(forecast, h0), tz);
      const fits = (h1 - h0) * slot >= textHalfWidth(name, font) * 2 + 6;
      days.push({
        i: h0,
        x: x0,
        name,
        labelX: cx,
        labelY: H + 10,
        anchor: 'middle',
        bottom: true,
        divider: h0 > 0 ? { x: x0, y1: top - 18, y2: plotBottom } : null,
        hidden: !fits,
      });
    }
  }

  let now = null;
  if (nowIdx != null && nowIdx >= 0 && nowIdx <= total) {
    const x = X(nowIdx);
    now = { x, y1: top - 6, y2: plotBottom, labelX: x + 4, labelY: top - 8, text: 'now' };
  }

  const ex = X(total);
  let edgeText = horizonLabel(forecast);
  if (seven) edgeText = span.nbm ? endLabel(forecast, '7d') : `${horizonLabel(forecast)} · NBM unavailable`;
  const edge = { x: ex, y1: top - 6, y2: plotBottom, labelX: ex - 4, labelY: top - 8, text: edgeText };

  // The model seam (= the HRRR edge) and the NBM region, 7 d with NBM only.
  let seam = null;
  if (span.nbm) {
    const sx = X(forecast.extended.fromIdx);
    seam = {
      x: sx,
      y1: top - 6,
      y2: plotBottom,
      labelY: top - 8,
      left: { x: sx - 4, text: 'HRRR' },
      right: { x: sx + 4, text: 'NBM · 3-hourly' },
      region: { x: sx, y: top, w: ex - sx, h: plotH },
    };
  }

  // Sky band cells (sky_reference.py::band_svg), y relative to the band.
  const sky = skyCells(forecast, span.range).map((c) => {
    const x = X(c.t);
    const w = c.w * slot;
    const tickXs = [];
    for (let j = 0; j < c.ticks; j++) tickXs.push(x + (w * (j + 1)) / (c.ticks + 1));
    return { t: c.t, model: c.model, tone: c.tone, x: x + 0.5, y: 2, w: Math.max(0, w - 1), h: SKY_BAND_H - 4, ticks: tickXs.map((tx) => ({ x: tx, y1: SKY_BAND_H - 6, y2: SKY_BAND_H - 1 })) };
  });
  const skyH = sky.length ? SKY_BAND_H + SKY_BAND_GAP : 0;

  return {
    W, H, top, bot, plotH, plotBottom, n, slot, bw, capW, yMax, font, arrowSize,
    range: span.range, mode, total, end: span.end, slots,
    stops: twilightStops(forecast, span.end),
    grid, sun, bars, gust, arrows, ticks, labels, days, now, edge, seam, sky, skyH,
  };
}

// Hover / scrub highlight for slot i (HANDOFF §6.4c): a 1.5 px outline on the
// bar (radius 2.5, outset 1.5) and a full-height rule through the slot centre
// from top − 6 to the bottom of the arrow row.
export function selectionGeometry(layout, i) {
  const b = layout.bars[i];
  if (!b) return null;
  const cx = b.x + b.w / 2;
  return {
    i,
    cx,
    rule: { x: cx, y1: layout.top - 6, y2: layout.plotBottom + layout.bot },
    outline: { x: b.x - 1.5, y: b.y - 1.5, w: b.w + 3, h: b.h + 1.5, rx: 2.5 },
  };
}

// Slot index under x (viewBox units); null outside the plot. For hourly
// slots this is floor(x / slot).
export function hourAtX(layout, x) {
  if (!(x >= 0) || x >= layout.total * layout.slot) return null;
  const h = x / layout.slot;
  const ss = layout.slots;
  for (let i = 0; i < ss.length; i++) if (h >= ss[i].t && h < ss[i].t + ss[i].w) return i;
  return null;
}

// --- Time formatting (Intl with the payload tz) ---------------------------

const fmtCache = new Map();
function fmt(tz, opts) {
  const key = tz + JSON.stringify(opts);
  let f = fmtCache.get(key);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', { timeZone: tz, ...opts });
    fmtCache.set(key, f);
  }
  return f;
}

function part(parts, type) {
  const p = parts.find((x) => x.type === type);
  return p ? p.value : '';
}

export function formatHHMM(date, tz) {
  const p = fmt(tz, { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(date);
  return `${part(p, 'hour')}:${part(p, 'minute')}`;
}

export function formatHH(date, tz) {
  return part(fmt(tz, { hour: '2-digit', hourCycle: 'h23' }).formatToParts(date), 'hour');
}

export function shortDay(date, tz) {
  return fmt(tz, { weekday: 'short' }).format(date);
}

export function longDay(date, tz) {
  return fmt(tz, { weekday: 'long' }).format(date);
}

export function shortDate(date, tz) {
  return fmt(tz, { day: 'numeric', month: 'short' }).format(date);
}

export function tzAbbrev(date, tz) {
  return part(fmt(tz, { timeZoneName: 'short' }).formatToParts(date), 'timeZoneName');
}

export function localHour(date, tz) {
  return Number(part(fmt(tz, { hour: 'numeric', hourCycle: 'h23' }).formatToParts(date), 'hour'));
}

// Local calendar day as a UTC day number, for day-difference arithmetic.
export function localDayNumber(date, tz) {
  const p = fmt(tz, { year: 'numeric', month: 'numeric', day: 'numeric' }).formatToParts(date);
  return Date.UTC(Number(part(p, 'year')), Number(part(p, 'month')) - 1, Number(part(p, 'day'))) / (24 * HOUR_MS);
}

export function localDayDiff(a, b, tz) {
  return localDayNumber(a, tz) - localDayNumber(b, tz);
}
