// Open-Meteo URL building and fetching. The only place upstream URLs exist.

import { USER_AGENT } from "./config.js";
import type { OpenMeteoForecast, OpenMeteoMeta } from "./types.js";

const API = "https://api.open-meteo.com";
export const MODEL = "ncep_hrrr_conus";

/** HRRR run metadata; not rate-limited per Open-Meteo (DESIGN §2.2). */
export const metaURL = `${API}/data/${MODEL}/static/meta.json`;

export interface ForecastURLOptions {
  lat: number;
  lon: number;
  /** "sea" for the default location, "nearest" for custom ones (DESIGN §2.1, §7). */
  cell: "sea" | "nearest";
  /** "GMT" for the default bake, "auto" for custom locations (the response then carries the tz). */
  timezone: "GMT" | "auto";
}

export function forecastURL(opts: ForecastURLOptions): string {
  const q = new URLSearchParams({
    latitude: String(opts.lat),
    longitude: String(opts.lon),
    hourly: "wind_speed_10m,wind_direction_10m,wind_gusts_10m",
    wind_speed_unit: "kn",
    timeformat: "unixtime",
    timezone: opts.timezone,
    forecast_hours: "50",
    models: MODEL,
    cell_selection: opts.cell,
  });
  return `${API}/v1/forecast?${q.toString()}`;
}

export class UpstreamError extends Error {
  constructor(
    message: string,
    readonly status?: number,
  ) {
    super(message);
    this.name = "UpstreamError";
  }
}

/** Fetch JSON with a 10 s timeout and our User-Agent. Throws UpstreamError on non-2xx or bad JSON. */
export async function fetchJSON<T>(url: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("User-Agent", USER_AGENT);
  headers.set("Accept", "application/json");
  let res: Response;
  try {
    res = await fetch(url, { ...init, headers, signal: AbortSignal.timeout(10_000) });
  } catch (e) {
    throw new UpstreamError(`fetch failed: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (!res.ok) {
    throw new UpstreamError(`upstream ${res.status} for ${new URL(url).pathname}`, res.status);
  }
  try {
    return (await res.json()) as T;
  } catch (e) {
    throw new UpstreamError(`bad JSON: ${e instanceof Error ? e.message : String(e)}`);
  }
}

export function fetchMeta(): Promise<OpenMeteoMeta> {
  return fetchJSON<OpenMeteoMeta>(metaURL);
}

export function fetchForecast(opts: ForecastURLOptions): Promise<OpenMeteoForecast> {
  return fetchJSON<OpenMeteoForecast>(forecastURL(opts));
}
