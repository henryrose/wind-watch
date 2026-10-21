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
export function trustLine(forecast, state, tz) {
  if (state.kind === 'firstrun') {
    return { text: 'No data yet. Needs cellular or Wi-Fi once.', amber: false, glyph: null };
  }
  const asOf = (withDay) =>
    (withDay ? `${shortDay(forecast.fetched, tz)} ` : '') + formatHHMM(forecast.fetched, tz);
  const ends = `ends ${shortDay(forecast.horizon, tz)} ${formatHHMM(forecast.horizon, tz)}`;
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
        text: `as of ${asOf(old)} · ${forecast.run} · ${ends}`,
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

// "HRRR ends 05:00"; drops "HRRR " when the edge is within 12 slots of now.
export function horizonLabel(forecast, nowIdx) {
  const edge = forecast.hours.length;
  const prefix = nowIdx != null && edge - nowIdx < 12 ? '' : 'HRRR ';
  return `${prefix}ends ${formatHHMM(forecast.horizon, forecast.location.tz)}`;
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
