// Compile-time constants for the default location (DESIGN §2.1) and KV layout.

import type { Location } from "./types.js";

/** Default location request coordinates; Open-Meteo snaps them to the sea cell. */
export const DEFAULT_LOCATION: Location = {
  name: "Port Townsend Bay",
  lat: 48.09,
  lon: -122.76,
  tz: "America/Los_Angeles",
  cell: "sea",
};

/** KV keys for the default-location bake. */
export const KV_KEYS = {
  body: "default:body",
  etag: "default:etag",
  /** `last_run_availability_time` of the meta.json the bake was made from, as a decimal string. */
  meta: "default:meta",
} as const;

/** Custom-location responses are cached under this synthetic origin (DESIGN §7). */
export const CUSTOM_CACHE_ORIGIN = "https://wind-watch.cache";

/** How long a custom-location bake is served from the Cache API, seconds. */
export const CUSTOM_CACHE_TTL = 600;

export const USER_AGENT = "wind-watch/1 (personal, non-commercial)";
