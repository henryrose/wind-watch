// NBM after the HRRR horizon (docs/DESIGN.md §4.2a): the request window, the
// 3-hour block aggregation, and the rules for reusing a previous bake's
// `extended` when NBM can't be fetched. Pure functions: no I/O, no clock.

import type { Extended, OpenMeteoForecast, OpenMeteoMeta, Payload } from "./types.js";
import { clamp, fillNearest, normaliseDegrees, round1 } from "./transform.js";

const HOUR = 3600;
export const STEP_HOURS = 3;
const STEP = STEP_HOURS * HOUR;
/** The 7-day range is measured from the chart start (`start`), not from the HRRR horizon. */
export const RANGE_HOURS = 168;

export interface NbmWindow {
  /** `start + hours*3600`: the first hour HRRR doesn't cover. */
  from: number;
  /** Whole 3-hour blocks from `from` that end at or before `start + 168 h`. */
  blocks: number;
}

export function nbmWindow(start: number, hours: number): NbmWindow {
  const from = start + hours * HOUR;
  const end = start + RANGE_HOURS * HOUR;
  return { from, blocks: Math.max(0, Math.floor((end - from) / STEP)) };
}

/** Unix seconds of the last hour the window needs (inclusive), for `end_hour`. */
export function lastHour(w: NbmWindow): number {
  return w.from + w.blocks * STEP - HOUR;
}

export interface AggregateOptions {
  window: NbmWindow;
  meta: OpenMeteoMeta;
  fetched: number;
}

/**
 * Hourly NBM → `extended`. Hours are looked up by timestamp, so block 0 starts at
 * `window.from` whatever the response's first hour is. A block needs all three of
 * its hours with non-null wind; the first block that doesn't have them ends the
 * series (like `countNonNullHours`, nothing after a gap is used). Temperature,
 * cloud and precipitation holes take the nearest neighbour, as for HRRR.
 *
 * Rounding: kn and gust are the max of the raw values, rounded afterwards. Since
 * rounding is monotonic this equals the max of the rounded hours, so a block's
 * number always matches what an hourly view of the same data would peak at.
 * Direction is the mean of the hours' unit vectors (unweighted by speed), so 350°
 * and 10° average to 0°, not 180°.
 *
 * Null when no whole block is available or a sky/temperature series is absent:
 * the caller treats that as an NBM failure.
 */
export function aggregateNbm(f: OpenMeteoForecast, opts: AggregateOptions): Extended | null {
  const { from, blocks: wanted } = opts.window;
  const h = f.hourly;
  const n = h.time.length;
  const temp = fillNearest(h.temperature_2m, n);
  const cloud = fillNearest(h.cloud_cover, n);
  const precip = fillNearest(h.precipitation, n);
  if (!temp || !cloud || !precip) return null;

  const index = new Map<number, number>();
  h.time.forEach((t, i) => index.set(t, i));

  const out: Extended = {
    model: "ncep_nbm_conus",
    run: opts.meta.last_run_initialisation_time,
    fetched: opts.fetched,
    step: STEP_HOURS,
    from,
    blocks: 0,
    kn: [],
    gust: [],
    dir: [],
    temp: [],
    cloud: [],
    precip: [],
  };

  for (let b = 0; b < wanted; b++) {
    const idx: number[] = [];
    for (let k = 0; k < STEP_HOURS; k++) {
      const i = index.get(from + b * STEP + k * HOUR);
      if (i === undefined || h.wind_speed_10m[i] == null || h.wind_gusts_10m[i] == null || h.wind_direction_10m[i] == null) break;
      idx.push(i);
    }
    if (idx.length < STEP_HOURS) break;

    const speeds = idx.map((i) => h.wind_speed_10m[i] as number);
    out.kn.push(Math.round(Math.max(...speeds)));
    out.gust.push(Math.round(Math.max(...idx.map((i) => h.wind_gusts_10m[i] as number))));
    out.dir.push(vectorMeanDegrees(idx.map((i) => h.wind_direction_10m[i] as number), speeds));
    out.temp.push(round1(mean(idx.map((i) => temp[i] as number))));
    out.cloud.push(clamp(Math.round(mean(idx.map((i) => cloud[i] as number))), 0, 100));
    out.precip.push(round1(Math.max(0, ...idx.map((i) => precip[i] as number))));
    out.blocks++;
  }
  return out.blocks > 0 ? out : null;
}

/**
 * Unweighted vector mean of compass directions, rounded and normalised to 0..359.
 * When the vectors cancel (e.g. exactly 90° and 270°) there is no mean; the
 * direction of the strongest hour stands in.
 */
export function vectorMeanDegrees(degrees: readonly number[], speeds: readonly number[] = []): number {
  let x = 0;
  let y = 0;
  for (const d of degrees) {
    const r = (d * Math.PI) / 180;
    x += Math.sin(r);
    y += Math.cos(r);
  }
  if (Math.hypot(x, y) < 1e-6 * degrees.length) {
    let best = 0;
    for (let i = 1; i < degrees.length; i++) if ((speeds[i] ?? 0) > (speeds[best] ?? 0)) best = i;
    return normaliseDegrees(Math.round(degrees[best] ?? 0));
  }
  return normaliseDegrees(Math.round((Math.atan2(x, y) * 180) / Math.PI));
}

function mean(xs: readonly number[]): number {
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}

/**
 * A previous bake's `extended`, re-cut for a new window, or null if it can't be.
 * It survives only if its blocks line up with the new `from` exactly: same `from`,
 * or an earlier `from` a whole number of blocks back (leading blocks dropped).
 * Blocks past the new window's end are dropped too. `run` and `fetched` are kept:
 * this is still that NBM run, pulled when it was.
 */
export function trimExtended(prev: Extended | null | undefined, w: NbmWindow): Extended | null {
  if (!prev || prev.blocks <= 0) return null;
  const shift = w.from - prev.from;
  if (shift < 0 || shift % STEP !== 0) return null;
  const skip = shift / STEP;
  const keep = Math.min(prev.blocks - skip, w.blocks);
  if (keep <= 0) return null;
  const cut = (xs: number[]) => xs.slice(skip, skip + keep);
  return {
    model: prev.model,
    run: prev.run,
    fetched: prev.fetched,
    step: prev.step,
    from: w.from,
    blocks: keep,
    kn: cut(prev.kn),
    gust: cut(prev.gust),
    dir: cut(prev.dir),
    temp: cut(prev.temp),
    cloud: cut(prev.cloud),
    precip: cut(prev.precip),
  };
}

/**
 * The server-side guarantee behind "clients never filter": `extended`, if present,
 * starts exactly at the HRRR horizon, is whole 3-hour blocks ending by start + 168 h,
 * and every array has `blocks` entries. Anything else becomes null. Applied to every
 * payload just before serialisation.
 */
export function enforceExtended(p: Payload): Payload {
  const e = p.extended;
  if (e === null) return p;
  const w = nbmWindow(p.start, p.hours);
  const lengthsOK = [e.kn, e.gust, e.dir, e.temp, e.cloud, e.precip].every((a) => a.length === e.blocks);
  if (e.step === STEP_HOURS && e.from === w.from && e.blocks > 0 && e.blocks <= w.blocks && lengthsOK) return p;
  console.error(`extended rejected: from ${e.from} (want ${w.from}), ${e.blocks} blocks (max ${w.blocks})`);
  return { ...p, extended: null };
}
