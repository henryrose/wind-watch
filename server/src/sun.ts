// Sunrise, sunset and civil twilight from the NOAA solar position algorithm
// (the equations behind NOAA's Solar Calculator spreadsheet, Meeus-derived).
// Pure functions, no I/O, no timezone library: local midnights are found with
// Intl.DateTimeFormat, which the Workers runtime ships with full tz data.

import type { SunDay } from "./types.js";

const DAY = 86400;
const HOUR = 3600;
const RAD = Math.PI / 180;

/** Zenith angle for sunrise/sunset: 90° + 0.833° (refraction + solar semi-diameter). */
const ZENITH_RISE_SET = 90.833;
/** Zenith angle for civil twilight: sun centre 6° below the horizon. */
const ZENITH_CIVIL = 96;

/** Declination and equation of time at a given instant. */
interface SolarParams {
  /** Solar declination, degrees. */
  decl: number;
  /** Equation of time, minutes (apparent − mean solar time). */
  eqTime: number;
}

/**
 * NOAA solar parameters for a unix instant.
 * Julian century from J2000; all angles in degrees until the final trig.
 */
export function solarParams(unix: number): SolarParams {
  const jd = unix / DAY + 2440587.5;
  const t = (jd - 2451545) / 36525;

  const L0 = norm360(280.46646 + t * (36000.76983 + t * 0.0003032)); // geometric mean longitude
  const M = norm360(357.52911 + t * (35999.05029 - 0.0001537 * t)); // geometric mean anomaly
  const e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t); // eccentricity of Earth's orbit

  const C =
    Math.sin(M * RAD) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
    Math.sin(2 * M * RAD) * (0.019993 - 0.000101 * t) +
    Math.sin(3 * M * RAD) * 0.000289; // equation of centre
  const trueLong = L0 + C;
  const omega = 125.04 - 1934.136 * t;
  const lambda = trueLong - 0.00569 - 0.00478 * Math.sin(omega * RAD); // apparent longitude

  const eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60; // mean obliquity
  const eps = eps0 + 0.00256 * Math.cos(omega * RAD); // corrected obliquity

  const decl = Math.asin(Math.sin(eps * RAD) * Math.sin(lambda * RAD)) / RAD;

  const y = Math.tan((eps / 2) * RAD) ** 2;
  const eqTime =
    (4 / RAD) *
    (y * Math.sin(2 * L0 * RAD) -
      2 * e * Math.sin(M * RAD) +
      4 * e * y * Math.sin(M * RAD) * Math.cos(2 * L0 * RAD) -
      0.5 * y * y * Math.sin(4 * L0 * RAD) -
      1.25 * e * e * Math.sin(2 * M * RAD));

  return { decl, eqTime };
}

function norm360(deg: number): number {
  return ((deg % 360) + 360) % 360;
}

/** Normalise an angle to (−180, 180]. */
function norm180(deg: number): number {
  const d = norm360(deg);
  return d > 180 ? d - 360 : d;
}

/** Solar hour angle (degrees, 0 at solar noon, negative in the morning) at a unix instant. */
function hourAngleAt(unix: number, lon: number, p: SolarParams): number {
  const minutesUtc = ((unix % DAY) + DAY) % DAY / 60;
  const trueSolarMinutes = minutesUtc + p.eqTime + 4 * lon;
  return norm180(trueSolarMinutes / 4 - 180);
}

/**
 * Find the unix instant nearest `guess` at which the sun's hour angle equals
 * `targetHA` (degrees). Declination and the equation of time drift slowly, so
 * three fixed-point iterations converge well under a second.
 */
function solveHourAngle(guess: number, lon: number, targetHA: number): number {
  let t = guess;
  for (let i = 0; i < 3; i++) {
    const p = solarParams(t);
    const delta = norm180(targetHA - hourAngleAt(t, lon, p));
    t += delta * 240; // 1° of hour angle = 4 minutes = 240 s
  }
  return t;
}

/**
 * Half-day arc (degrees of hour angle) between solar noon and the moment the
 * sun's centre is at the given zenith angle, evaluated with the declination at
 * `unix`. Clamped for polar conditions: 0 when the sun never gets that high
 * (polar night / no twilight), 180 when it never gets that low (midnight sun).
 */
function halfArc(unix: number, lat: number, zenith: number): number {
  const { decl } = solarParams(unix);
  const cosHA =
    Math.cos(zenith * RAD) / (Math.cos(lat * RAD) * Math.cos(decl * RAD)) -
    Math.tan(lat * RAD) * Math.tan(decl * RAD);
  if (cosHA >= 1) return 0;
  if (cosHA <= -1) return 180;
  return Math.acos(cosHA) / RAD;
}

/**
 * Instant of the event at hour angle `sign · arc` on the day anchored at `noon`.
 * Clamped arcs (0 or 180, see halfArc) are placed exactly on noon or noon ± 12 h
 * rather than solved, so the degenerate days are deterministic.
 */
function eventAt(noon: number, lon: number, arc: number, sign: -1 | 1): number {
  if (arc <= 0) return noon;
  if (arc >= 180) return noon + sign * 12 * HOUR;
  return solveHourAngle(noon + sign * arc * 240, lon, sign * arc);
}

/**
 * Sun events for one local civil day.
 *
 * @param lat degrees north
 * @param lon degrees east (west negative)
 * @param utcMidnightOfLocalDay unix seconds of the instant local midnight begins that day
 * @returns unix seconds, rounded to the second
 *
 * Events are anchored on that day's solar noon (the instant nearest local noon
 * at which the hour angle is 0), so the result is unambiguous for any time
 * zone, including ones far from the meridian of their longitude.
 *
 * Polar edge cases return a best effort rather than nulls or NaN:
 * - polar night (sun never reaches −0.833°): rise = set = solar noon;
 * - midnight sun (sun never goes below −0.833°): rise = noon − 12 h, set = noon + 12 h;
 * - no civil twilight (sun never reaches −6°): dawn = rise and dusk = set, i.e.
 *   twilight collapses onto the rise/set points;
 * - permanent twilight (never below −6°): dawn = noon − 12 h, dusk = noon + 12 h.
 * So `dawn ≤ rise ≤ set ≤ dusk` always holds; strict inequality holds away from the poles.
 */
export function sunEvents(
  lat: number,
  lon: number,
  utcMidnightOfLocalDay: number,
): SunDay {
  const noon = solveHourAngle(utcMidnightOfLocalDay + 12 * HOUR, lon, 0);

  const arcRiseSet = halfArc(noon, lat, ZENITH_RISE_SET);
  const rise = eventAt(noon, lon, arcRiseSet, -1);
  const set = eventAt(noon, lon, arcRiseSet, +1);

  const arcCivil = Math.max(halfArc(noon, lat, ZENITH_CIVIL), arcRiseSet);
  const dawn = eventAt(noon, lon, arcCivil, -1);
  const dusk = eventAt(noon, lon, arcCivil, +1);

  // The second solve pass re-evaluates declination at the event itself, which
  // can nudge an event a few seconds across its twin under clamping; keep the
  // documented ordering exact.
  const r = Math.round(rise);
  const s = Math.max(Math.round(set), r);
  return {
    dawn: Math.min(Math.round(dawn), r),
    rise: r,
    set: s,
    dusk: Math.max(Math.round(dusk), s),
  };
}

// ---------------------------------------------------------------------------
// Local civil days via Intl

interface LocalDate {
  y: number;
  m: number; // 1..12
  d: number; // 1..31
}

const dtfCache = new Map<string, Intl.DateTimeFormat>();

function formatter(tz: string): Intl.DateTimeFormat {
  let f = dtfCache.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", {
      timeZone: tz,
      hourCycle: "h23",
      year: "numeric",
      month: "numeric",
      day: "numeric",
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
    });
    dtfCache.set(tz, f);
  }
  return f;
}

/** Wall-clock components of a unix instant in `tz`. */
function localParts(unix: number, tz: string): LocalDate & { hh: number; mm: number; ss: number } {
  const parts = formatter(tz).formatToParts(new Date(unix * 1000));
  const get = (type: string): number => {
    const p = parts.find((x) => x.type === type);
    if (!p) throw new Error(`sun: Intl gave no ${type} for tz ${tz}`);
    return Number(p.value);
  };
  return { y: get("year"), m: get("month"), d: get("day"), hh: get("hour") % 24, mm: get("minute"), ss: get("second") };
}

/** Local calendar date of a unix instant in `tz`. */
export function localDate(unix: number, tz: string): LocalDate {
  const { y, m, d } = localParts(unix, tz);
  return { y, m, d };
}

/** Offset of `tz` from UTC, in seconds, at a unix instant (east positive). */
function utcOffsetAt(unix: number, tz: string): number {
  const p = localParts(unix, tz);
  const asIfUtc = Date.UTC(p.y, p.m - 1, p.d, p.hh, p.mm, p.ss) / 1000;
  return asIfUtc - unix;
}

/**
 * Unix instant at which local midnight of the given calendar date begins in `tz`.
 * Two passes handle a DST change between the guess and the answer. If midnight
 * itself does not exist (a DST gap at 00:00, as in some zones), the result is
 * the instant the clocks skip to, which is still the start of that civil day.
 */
export function localMidnight(date: LocalDate, tz: string): number {
  const naive = Date.UTC(date.y, date.m - 1, date.d, 0, 0, 0) / 1000;
  let t = naive - utcOffsetAt(naive, tz);
  t = naive - utcOffsetAt(t, tz);
  return t;
}

function addDays(date: LocalDate, n: number): LocalDate {
  const d = new Date(Date.UTC(date.y, date.m - 1, date.d + n));
  return { y: d.getUTCFullYear(), m: d.getUTCMonth() + 1, d: d.getUTCDate() };
}

function sameDate(a: LocalDate, b: LocalDate): boolean {
  return a.y === b.y && a.m === b.m && a.d === b.d;
}

export interface SunDaysInput {
  lat: number;
  lon: number;
  /** IANA time zone the civil days are counted in. */
  tz: string;
  /** Unix seconds of hour index 0. */
  start: number;
  /** Number of forecast hours. */
  hours: number;
}

/**
 * One SunDay per local civil day (in `tz`) touched by the forecast range,
 * in order. The range is `[start, start + (hours − 1)·3600]`, i.e. from the
 * first hour's timestamp to the last hour's timestamp inclusive; the last
 * hour's trailing 59 minutes do not pull in an extra day.
 */
export function sunDays(input: SunDaysInput): SunDay[] {
  const { lat, lon, tz, start, hours } = input;
  if (hours <= 0) return [];
  const lastHour = start + (hours - 1) * HOUR;
  const first = localDate(start, tz);
  const last = localDate(lastHour, tz);

  const out: SunDay[] = [];
  let date = first;
  for (let guard = 0; guard < 10; guard++) {
    out.push(sunEvents(lat, lon, localMidnight(date, tz)));
    if (sameDate(date, last)) break;
    date = addDays(date, 1);
  }
  return out;
}
