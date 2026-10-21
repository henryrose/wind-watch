// Rule-based one-line summary of the forecast (DESIGN §4.2 `summary`).
// Pure: everything is a function of the payload arrays, `start`, `peak` and
// `loc.tz`. ≤ 110 characters, integers only, no model jargon.

import { localDate } from "./sun.js";
import type { Payload } from "./types.js";

const MAX_LEN = 110;
const HOUR = 3600;
const WINDOW = 6;
const BUILD_DELTA = 5;
const EASE_DELTA = 5;
const GUST_MIN = 15;

// ---------------------------------------------------------------------------
// Words

/** Strength word for a rounded sustained wind. */
export function bandWord(kn: number): "calm" | "light" | "moderate" | "fresh" | "strong" | "gale" {
  if (kn < 4) return "calm";
  if (kn <= 10) return "light";
  if (kn <= 16) return "moderate";
  if (kn <= 21) return "fresh";
  if (kn <= 27) return "strong";
  return "gale";
}

const COMPASS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"] as const;

/** 8-point compass label for a FROM direction in degrees. */
export function compass8(deg: number): string {
  const idx = Math.round((((deg % 360) + 360) % 360) / 45) % 8;
  return COMPASS[idx] as string;
}

/** Vector mean of FROM directions (unit vectors, so 350° and 10° average to 0°). */
export function meanDirection(degs: number[]): number {
  let x = 0;
  let y = 0;
  for (const d of degs) {
    x += Math.cos((d * Math.PI) / 180);
    y += Math.sin((d * Math.PI) / 180);
  }
  if (x === 0 && y === 0) return 0;
  const deg = (Math.atan2(y, x) * 180) / Math.PI;
  return (deg + 360) % 360;
}

/** Largest pairwise angular separation (0..180) among the directions. */
export function directionSpread(degs: number[]): number {
  let spread = 0;
  for (let i = 0; i < degs.length; i++) {
    for (let j = i + 1; j < degs.length; j++) {
      const d = Math.abs(((degs[i] as number) - (degs[j] as number) + 540) % 360 - 180);
      spread = Math.max(spread, d);
    }
  }
  return spread;
}

function mean(xs: number[]): number {
  return xs.length === 0 ? 0 : xs.reduce((a, b) => a + b, 0) / xs.length;
}

// ---------------------------------------------------------------------------
// Periods

interface Period {
  /** The phrase itself, e.g. "this afternoon", "overnight", "dawn". */
  text: string;
  /** Whether "by" reads naturally in front of it ("by dawn" yes, "overnight" no). */
  by: boolean;
}

interface DayRef {
  y: number;
  m: number;
  d: number;
}

function dayNumber(d: DayRef): number {
  return Math.round(Date.UTC(d.y, d.m - 1, d.d) / 86400000);
}

const hourFmt = new Map<string, Intl.DateTimeFormat>();
function localHour(unix: number, tz: string): number {
  let f = hourFmt.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", { timeZone: tz, hourCycle: "h23", hour: "numeric" });
    hourFmt.set(tz, f);
  }
  return Number(f.formatToParts(new Date(unix * 1000)).find((p) => p.type === "hour")?.value ?? "0") % 24;
}

const weekdayFmt = new Map<string, Intl.DateTimeFormat>();
function weekdayName(unix: number, tz: string): string {
  let f = weekdayFmt.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", { timeZone: tz, weekday: "long" });
    weekdayFmt.set(tz, f);
  }
  return f.format(new Date(unix * 1000));
}

/**
 * Period phrase for an instant, relative to the forecast's first local day.
 * Bands (local hour): morning 05–11, afternoon 12–16, evening 17–22,
 * "around midnight" 23–00, "overnight" 01–04; 05–06 on the next day is "dawn".
 * Night hours (23–04) belong to the night that began on the previous evening,
 * so 02:00 Thursday is "overnight" relative to a Wednesday forecast.
 */
export function period(unix: number, tz: string, firstDay: DayRef): Period {
  const h = localHour(unix, tz);
  const offset = dayNumber(localDate(unix, tz)) - dayNumber(firstDay);

  if (h >= 23 || h <= 4) {
    const nightOf = h >= 23 ? offset : offset - 1; // which day's night
    if (nightOf <= 0) return { text: h >= 23 || h === 0 ? "around midnight" : "overnight", by: false };
    if (nightOf === 1) return { text: "tomorrow night", by: false };
    // Name the day the night began on: 23:00 is that day; 00:00–04:00 is the day before.
    const nightStart = h >= 23 ? unix : unix - (h + 1) * HOUR;
    return { text: `${weekdayName(nightStart, tz)} night`, by: false };
  }

  if (offset === 1 && h <= 6) return { text: "dawn", by: true };

  const part = h <= 11 ? "morning" : h <= 16 ? "afternoon" : "evening";
  if (offset <= 0) return { text: `this ${part}`, by: true };
  if (offset === 1) return { text: `tomorrow ${part}`, by: true };
  return { text: `${weekdayName(unix, tz)} ${part}`, by: true };
}

function withBy(p: Period): string {
  return p.by ? `by ${p.text}` : p.text;
}

// ---------------------------------------------------------------------------
// Clauses

export interface SummaryParts {
  /** Opening clause, e.g. "Light W this morning" or "Calm through tomorrow". */
  now: string;
  /** ", building to 15 kn W by this afternoon" (without the comma) or null. */
  building: string | null;
  /** "gusts to 25 overnight" or null; period omitted when it equals the building period. */
  gusts: string | null;
  /** "Easing by dawn" or null. */
  easing: string | null;
}

/** Means of consecutive non-overlapping 6-hour windows starting at hour 0 (last may be shorter). */
function windowMeans(kn: number[]): { startIdx: number; mean: number; max: number; maxIdx: number }[] {
  const out = [];
  for (let s = 0; s < kn.length; s += WINDOW) {
    const slice = kn.slice(s, s + WINDOW);
    let maxIdx = s;
    for (let i = s; i < Math.min(s + WINDOW, kn.length); i++) {
      if ((kn[i] as number) > (kn[maxIdx] as number)) maxIdx = i;
    }
    out.push({ startIdx: s, mean: mean(slice), max: kn[maxIdx] as number, maxIdx });
  }
  return out;
}

export function summaryParts(p: Payload): SummaryParts {
  const { kn, gust, dir, start, hours } = p;
  const tz = p.loc.tz;
  const firstDay = localDate(start, tz);
  const at = (i: number) => start + i * HOUR;
  const per = (i: number) => period(at(i), tz, firstDay);

  if (hours === 0 || kn.length === 0) {
    return { now: "No forecast", building: null, gusts: null, easing: null };
  }

  // Now: first three hours.
  const nowKn = kn.slice(0, 3);
  const nowDir = dir.slice(0, 3);
  const nowMean = mean(nowKn);
  const nowBand = bandWord(Math.round(nowMean));
  const variable = nowMean < 7 && directionSpread(nowDir) > 90;

  // Whole-forecast calm: one clause, nothing to build or ease.
  const allCalm = Math.max(...kn) < 4;

  let now: string;
  if (allCalm) {
    const endP = period(at(hours - 1), tz, firstDay);
    const endOffset = dayNumber(localDate(at(hours - 1), tz)) - dayNumber(firstDay);
    const through =
      endOffset <= 0 ? "today" : endOffset === 1 || endP.text === "tomorrow night" ? "tomorrow" : weekdayName(at(hours - 1), tz);
    now = `Calm through ${through}`;
  } else if (variable) {
    now = `Light and variable ${per(0).text}`;
  } else if (nowBand === "calm") {
    now = `Calm ${per(0).text}`;
  } else {
    now = `${capitalise(nowBand)} ${compass8(meanDirection(nowDir))} ${per(0).text}`;
  }

  // Building: first 6-hour window whose mean exceeds now by ≥ 5 kn.
  const windows = windowMeans(kn);
  let building: string | null = null;
  let buildPeriod: string | null = null;
  if (!allCalm) {
    const w = windows.find((x) => x.mean - nowMean >= BUILD_DELTA);
    if (w) {
      const bp = per(w.maxIdx);
      buildPeriod = bp.text;
      building = `building to ${w.max} kn ${compass8(dir[w.maxIdx] as number)} ${withBy(bp)}`;
    }
  }

  // Gusts.
  let gusts: string | null = null;
  if (p.peak.gust >= GUST_MIN && gust.length > 0) {
    const gp = period(p.peak.at, tz, firstDay);
    gusts = gp.text === buildPeriod ? `gusts to ${p.peak.gust}` : `gusts to ${p.peak.gust} ${gp.text}`;
  }

  // Easing: last 6-hour mean ≥ 5 kn below the strongest window's mean.
  let easing: string | null = null;
  if (!allCalm && windows.length > 1) {
    const peakWin = windows.reduce((a, b) => (b.mean > a.mean ? b : a));
    const lastMean = mean(kn.slice(Math.max(0, hours - WINDOW)));
    if (peakWin.mean - lastMean >= EASE_DELTA) {
      for (let i = peakWin.startIdx + WINDOW; i < hours; i++) {
        if (peakWin.mean - mean(kn.slice(i, i + WINDOW)) >= EASE_DELTA) {
          easing = `Easing ${withBy(per(i))}`;
          break;
        }
      }
    }
  }

  return { now, building, gusts, easing };
}

function capitalise(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

/**
 * Compose the parts into one or two sentences. If `maxLen` is exceeded, drop
 * clauses from the end (easing → gusts → building) until it fits; clauses are
 * whole, so the text is never cut mid-word.
 */
export function composeSummary(parts: SummaryParts, maxLen = MAX_LEN): string {
  const attempts: SummaryParts[] = [
    parts,
    { ...parts, easing: null },
    { ...parts, easing: null, gusts: null },
    { ...parts, easing: null, gusts: null, building: null },
  ];
  let text = "";
  for (const a of attempts) {
    text = render(a);
    if (text.length <= maxLen) return text;
  }
  return text;
}

function render(parts: SummaryParts): string {
  let first = parts.now;
  if (parts.building) first += `, ${parts.building}`;
  if (parts.gusts) {
    first += parts.building ? `, ${parts.gusts}` : `. ${capitalise(parts.gusts)}`;
  }
  let text = `${capitalise(first)}.`;
  if (parts.easing) text += ` ${parts.easing}.`;
  return text;
}

/** The wire `summary` string for a payload. */
export function summary(p: Payload): string {
  return composeSummary(summaryParts(p));
}
