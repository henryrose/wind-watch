// Open-Meteo HRRR response + meta.json → wire payload (docs/DESIGN.md §4.2).
// Pure function: no I/O, no clock. `fetched` and `loc` come from the caller.

import type { Location, OpenMeteoForecast, OpenMeteoMeta, Payload } from "./types.js";

const HOUR = 3600;
const SIX_HOURS = 6 * HOUR;
/** HRRR's long runs (00/06/12/18Z) go out 48 forecast hours. */
const LONG_RUN_HOURS = 48;

export interface TransformOptions {
  loc: Location;
  /** Unix seconds: when this forecast was pulled from Open-Meteo. */
  fetched: number;
}

export function transform(
  forecast: OpenMeteoForecast,
  meta: OpenMeteoMeta,
  opts: TransformOptions,
): Payload {
  const h = forecast.hourly;
  const start = h.time[0];
  if (start === undefined) throw new Error("transform: forecast has no hours");

  const hours = countNonNullHours(h);
  if (hours === 0) throw new Error("transform: forecast has no non-null hours");

  const kn: number[] = [];
  const gust: number[] = [];
  const dir: number[] = [];
  for (let i = 0; i < hours; i++) {
    // Non-null for i < hours by construction of countNonNullHours.
    kn.push(Math.round(h.wind_speed_10m[i] as number));
    gust.push(Math.round(h.wind_gusts_10m[i] as number));
    dir.push(normaliseDegrees(Math.round(h.wind_direction_10m[i] as number)));
  }

  // Peak gust: the max, first occurrence wins ties. Computed on the rounded
  // values so `peak.gust` always equals some `gust[i]`.
  let peakIndex = 0;
  for (let i = 1; i < hours; i++) {
    if ((gust[i] as number) > (gust[peakIndex] as number)) peakIndex = i;
  }

  const lastHourTime = start + (hours - 1) * HOUR;
  const latest = meta.last_run_initialisation_time;

  return {
    v: 1,
    loc: opts.loc,
    model: "ncep_hrrr_conus",
    fetched: opts.fetched,
    run: { latest, extended: inferExtendedRun(lastHourTime, latest) },
    start,
    hours,
    kn,
    gust,
    dir,
    peak: { gust: gust[peakIndex] as number, at: start + peakIndex * HOUR },
    summary: "",
    sun: [],
  };
}

/**
 * Number of leading hours for which all three wind arrays are non-null.
 * A null in any one array ends the forecast; nothing after the first null is used
 * even if later values happen to be present.
 */
export function countNonNullHours(h: OpenMeteoForecast["hourly"]): number {
  const n = Math.min(h.time.length, h.wind_speed_10m.length, h.wind_gusts_10m.length, h.wind_direction_10m.length);
  for (let i = 0; i < n; i++) {
    if (
      h.wind_speed_10m[i] == null ||
      h.wind_gusts_10m[i] == null ||
      h.wind_direction_10m[i] == null
    ) {
      return i;
    }
  }
  return n;
}

/**
 * Infer the init time of the long run that supplies the tail of the forecast.
 *
 * Open-Meteo splices HRRR runs: the newest run (hourly, usually an 18-h run)
 * covers the near hours, and the newest 48-h run (00/06/12/18Z) covers the
 * rest. The forecast API returns null past the longest available run, so the
 * last non-null hour is forecast hour 48 of that long run, i.e. the long run's
 * init time is `lastHourTime − 48 h`.
 *
 * Observed 2026-10-21 16:50Z (DESIGN §2.3): latest = 15Z, last non-null hour =
 * 12Z two days on, 12Z − 48 h = 12Z the same day as the 15Z run. Fixture of the
 * same day at 18Z: latest = 16Z, last hour = 12Z +2d → extended = 12Z.
 *
 * Returns null when the inference is not trustworthy: the candidate is not a
 * 00/06/12/18Z init, or it is in the future relative to `latest`, or it equals
 * `latest` (then the newest run is itself the long run and nothing was spliced).
 */
export function inferExtendedRun(lastHourTime: number, latest: number): number | null {
  const candidate = lastHourTime - LONG_RUN_HOURS * HOUR;
  if (candidate % SIX_HOURS !== 0) return null;
  if (candidate >= latest) return null;
  return candidate;
}

/** Map any integer degree value onto 0..359 (360 → 0, −10 → 350). */
export function normaliseDegrees(deg: number): number {
  return ((deg % 360) + 360) % 360;
}
