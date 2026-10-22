// Wind Watch — derivations from the wire payload (DESIGN.md §4.2) to the
// forecast view model (HANDOFF §2) and everything the page computes from it.
// Pure ES module: no DOM, importable by Node for `node --test`.
//
// All times are Dates; all wind values are integers in knots. Local-time
// formatting always goes through Intl with the payload's tz, never the machine
// zone.

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
  const hours = [];
  for (let i = 0; i < n; i++) {
    hours.push({ kn: payload.kn[i], gust: payload.gust[i], dirFrom: payload.dir[i] });
  }
  return {
    location: {
      name: payload.loc.name,
      lat: payload.loc.lat,
      lon: payload.loc.lon,
      tz: payload.loc.tz,
      isDefault,
    },
    model: payload.model,
    run: runLabel(payload.run.latest),
    runAt: new Date(payload.run.latest * 1000),
    fetched: new Date(payload.fetched * 1000),
    start,
    horizon: new Date(start.getTime() + (n - 1) * HOUR_MS),
    hours,
    sun: (payload.sun || []).map((d) => ({
      dawn: new Date(d.dawn * 1000),
      rise: new Date(d.rise * 1000),
      set: new Date(d.set * 1000),
      dusk: new Date(d.dusk * 1000),
    })),
    summary: payload.summary || '',
    peakGust: { kn: payload.peak.gust, at: new Date(payload.peak.at * 1000) },
  };
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
export function trustLine(forecast, state, tz, { compact = false } = {}) {
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
    default:
      return {
        text: `as of ${asOf(old)} ${tzAbbrev(forecast.fetched, tz)} · ${forecast.run} · ${ends}`,
        amber: state.tier !== 'fresh',
        glyph: null,
      };
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
export function twilightStops(forecast) {
  const start = forecast.start.getTime();
  const end = rangeEnd(forecast).getTime();
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

// Sun dots at sunrise and sunset only, as fractions of the plotted range.
export function sunMarkers(forecast) {
  const start = forecast.start.getTime();
  const end = rangeEnd(forecast).getTime();
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
export function chartAriaLabel(forecast) {
  const tz = forecast.location.tz;
  let minKn = Infinity;
  let maxKn = -Infinity;
  let maxGust = 0;
  for (const h of forecast.hours) {
    if (h.kn < minKn) minKn = h.kn;
    if (h.kn > maxKn) maxKn = h.kn;
    if (h.gust > maxGust) maxGust = h.gust;
  }
  return `${forecast.hours.length}-hour wind chart: sustained ${minKn} to ${maxKn} knots, gusts to ${maxGust} knots, ends ${longDay(forecast.horizon, tz)} ${formatHHMM(forecast.horizon, tz)}`;
}

// HANDOFF §11: "15 knots, gusting 25, from the west, as of 23:30"
export function heroAriaLabel(h, asOf, tz) {
  return `${h.kn} knots, gusting ${h.gust}, from the ${compassWord(h.dirFrom)}, as of ${formatHHMM(asOf, tz)}`;
}

// --- Chart layout (port of docs/design/reference/chart_reference.py::svg) --
//
// Everything is derived from slot = W / n in viewBox units; the page scales
// the SVG to 100 % width. Styles are the two web breakpoints (HANDOFF §6.5,
// §6.4a): desktop ≥ 900 px, phone below.

export const CHART_STYLES = {
  desktop: { W: 1120, H: 300, top: 40, bot: 22, arrowEvery: 1, tickEvery: 3, labelEvery: 3, font: 12, arrowSize: 10, dayBand: true },
  phone: { W: 358, H: 200, top: 22, bot: 16, arrowEvery: 3, tickEvery: 6, labelEvery: 6, font: 11, arrowSize: 9, dayBand: false },
};

// Dark: white 7 % × day; light: black 8 % × (1 − day) (HANDOFF §6.1).
export const SHADE_DAY_ALPHA = 0.07;
export const SHADE_NIGHT_ALPHA = 0.08;

// Layout model for one chart. nowIdx is fractional hours since start (null
// hides the now marker). Returns only numbers and labels; the page turns it
// into SVG and the tests compare it with reference/charts/webhover.svg.
export function chartLayout(forecast, style, { nowIdx = null } = {}) {
  const { W, H, top, bot, font, arrowSize } = style;
  const tz = forecast.location.tz;
  const hours = forecast.hours;
  const n = hours.length;
  const plotH = H - top - bot;
  const plotBottom = top + plotH;
  const slot = W / n;
  const bw = Math.max(3, Math.round(slot * 0.72 * 100) / 100);
  const capW = bw + 2;
  const yMax = yDomainMax(hours);
  const X = (i) => i * slot;
  const Y = (v) => top + plotH - (v / yMax) * plotH;

  const grid = [];
  for (let v = 10; v < yMax; v += 10) grid.push({ v, y: Y(v), labelX: W - 2, labelY: Y(v) - 3 });

  const sun = sunMarkers(forecast).map((s) => ({ kind: s.kind, x: s.offset * W, y: top - 1, at: s.at }));

  // Bars sit on the baseline; 0 kn is a 1 px stub.
  const bars = hours.map((h, i) => {
    const y = h.kn > 0 ? Y(h.kn) : plotBottom - 1;
    const step = beaufortStep(h.kn);
    return { i, x: X(i) + (slot - bw) / 2, y, w: bw, h: plotBottom - y, step, token: beaufortToken(step) };
  });

  const gust = hours.map((h, i) => ({ i, x: X(i) + slot / 2, y: Y(h.gust) }));

  const arrows = [];
  for (let i = 0; i < n; i += style.arrowEvery) {
    arrows.push({ i, x: X(i) + slot / 2, y: plotBottom + bot / 2, rot: arrowRotation(hours[i].dirFrom) });
  }

  // Ticks and labels are hour-of-day based: 3-h cadence at hours divisible
  // by 3, 6-h cadence at 03/09/15/21 (both anchored on 9am).
  const onCadence = (hod, every) => hod % every === 3 % every;
  const ticks = [];
  const labels = [];
  const days = [];
  for (let i = 0; i < n; i++) {
    const t = hourAt(forecast, i);
    const hod = localHour(t, tz);
    const cx = X(i) + slot / 2;
    if (onCadence(hod, style.tickEvery)) ticks.push({ i, x: cx, y1: plotBottom, y2: plotBottom + 3 });
    if (onCadence(hod, style.labelEvery)) labels.push({ i, x: cx, y: H + 10, text: tickLabel(hod) });
    if (style.dayBand && (i === 0 || hod === 0)) {
      days.push({
        i,
        x: X(i),
        name: shortDay(t, tz),
        labelX: X(i) + 5,
        labelY: top - 22,
        divider: i > 0 ? { x: X(i), y1: top - 18, y2: plotBottom } : null,
        hidden: false,
      });
    }
  }

  let now = null;
  if (nowIdx != null && nowIdx >= 0 && nowIdx <= n) {
    const x = X(nowIdx);
    now = { x, y1: top - 6, y2: plotBottom, labelX: x + 4, labelY: top - 8, text: 'now' };
    // README nit: hide the first day's name when "now" would sit under it.
    if (days.length && days[0].i === 0 && now.labelX < days[0].labelX + font * 2.6) days[0].hidden = true;
  }

  const ex = X(n);
  const edge = { x: ex, y1: top - 6, y2: plotBottom, labelX: ex - 4, labelY: top - 8, text: horizonLabel(forecast) };

  return {
    W, H, top, bot, plotH, plotBottom, n, slot, bw, capW, yMax, font, arrowSize,
    stops: twilightStops(forecast),
    grid, sun, bars, gust, arrows, ticks, labels, days, now, edge,
  };
}

// Hover / scrub highlight for hour i (HANDOFF §6.4c): a 1.5 px outline on the
// bar (radius 2.5, outset 1.5) and a full-height rule through the slot centre
// from top − 6 to the bottom of the arrow row.
export function selectionGeometry(layout, i) {
  const b = layout.bars[i];
  if (!b) return null;
  const cx = i * layout.slot + layout.slot / 2;
  return {
    i,
    cx,
    rule: { x: cx, y1: layout.top - 6, y2: layout.plotBottom + layout.bot },
    outline: { x: b.x - 1.5, y: b.y - 1.5, w: b.w + 3, h: b.h + 1.5, rx: 2.5 },
  };
}

// hour = floor(x / slot) for an x in viewBox units; null outside the plot.
export function hourAtX(layout, x) {
  const i = Math.floor(x / layout.slot);
  return i >= 0 && i < layout.n ? i : null;
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
