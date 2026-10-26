// Worker entry point: `scheduled` bakes the default location into KV every 10
// minutes (DESIGN §4.5, §4.2a); `fetch` serves it at GET /v1/wind with an ETag
// (§4.4) and bakes custom locations on demand behind the Cache API (§7).

import { CUSTOM_CACHE_ORIGIN, CUSTOM_CACHE_TTL, DEFAULT_LOCATION, KV_KEYS } from "./config.js";
import { aggregateNbm, enforceExtended, lastHour, nbmWindow, trimExtended } from "./nbm.js";
import { fetchForecast, fetchMeta, fetchNbm, fetchNbmMeta, isOutsideCoverage } from "./openmeteo.js";
import { serializePayload } from "./stableStringify.js";
import { transform } from "./transform.js";
import type { Extended, Location, OpenMeteoMeta, Payload } from "./types.js";
import { CLIENT_HEADER, recordUsage } from "./usage.js";

export interface Env {
  WIND: KVNamespace;
  /** Analytics Engine dataset for request counts; optional so tests and local dev run without it. */
  USAGE?: AnalyticsEngineDataset;
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
  "Access-Control-Allow-Headers": `If-None-Match, ${CLIENT_HEADER}`,
  "Access-Control-Expose-Headers": "ETag",
} as const;

// ---------------------------------------------------------------------------
// Baking

interface Bake {
  body: string;
  etag: string;
}

/** Enforce `extended` + serialise + hash. */
async function bake(payload: Payload): Promise<Bake> {
  const body = serializePayload(enforceExtended(payload));
  return { body, etag: await etagFor(body) };
}

/** `"sha256-<first 16 hex of SHA-256(body)>"` (DESIGN §4.4). */
export async function etagFor(body: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(body));
  const hex = Array.from(new Uint8Array(digest).slice(0, 8), (b) => b.toString(16).padStart(2, "0")).join("");
  return `"sha256-${hex}"`;
}

function errorText(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

interface ExtendedOptions {
  /** Request point and cell for NBM; the same as the HRRR request's. */
  lat: number;
  lon: number;
  cell: "sea" | "nearest";
  /** NBM meta.json, or null if it couldn't be fetched (then NBM counts as failed). */
  nbmMeta: OpenMeteoMeta | null;
  /** The previous bake's `extended`, for reuse on failure and for `extended.fetched`. */
  previous: Extended | null;
  /** True when the previous `extended` came from the NBM availability in `nbmMeta`. */
  previousIsCurrent: boolean;
  now: number;
}

interface ExtendedResult {
  extended: Extended | null;
  /** False when NBM was needed and couldn't be had; the caller retries on the next cron. */
  ok: boolean;
}

/**
 * NBM for the hours after `payload`'s HRRR horizon (DESIGN §4.2a). Never throws: a
 * failure falls back to the previous `extended` re-cut to the new window, else null.
 * `extended.fetched` is the time this NBM run was first pulled, so it advances only on
 * a new NBM run, not when the same run is re-requested for a shifted window.
 */
async function extendedFor(payload: Payload, o: ExtendedOptions): Promise<ExtendedResult> {
  const window = nbmWindow(payload.start, payload.hours);
  if (window.blocks === 0) return { extended: null, ok: true };
  // Same NBM data, same window: nothing to fetch.
  if (o.previousIsCurrent && o.previous && o.previous.from === window.from && o.previous.blocks === window.blocks) {
    return { extended: o.previous, ok: true };
  }
  try {
    if (!o.nbmMeta) throw new Error("no NBM meta");
    const nbm = await fetchNbm({ lat: o.lat, lon: o.lon, cell: o.cell, first: window.from, last: lastHour(window) });
    const run = o.nbmMeta.last_run_initialisation_time;
    const fetched = o.previous && o.previous.run === run ? o.previous.fetched : o.now;
    const extended = aggregateNbm(nbm, { window, meta: o.nbmMeta, fetched });
    if (!extended) throw new Error("no whole NBM block in the window");
    return { extended, ok: true };
  } catch (e) {
    const kept = trimExtended(o.previous, window);
    console.error(`nbm: failed (${errorText(e)}); ${kept ? `keeping previous, ${kept.blocks} blocks` : "extended is null"}`);
    return { extended: kept, ok: false };
  }
}

/** A stored body this code can build on, or null (absent, unparsable, or baked before §4.2a). */
export function decodeStored(body: string | null): Payload | null {
  if (body === null) return null;
  try {
    const p = JSON.parse(body) as Partial<Payload>;
    if (!Array.isArray(p.kn) || typeof p.hours !== "number" || typeof p.start !== "number") return null;
    if (!Array.isArray(p.temp) || !Array.isArray(p.cloud) || !Array.isArray(p.precip) || p.extended === undefined) return null;
    return p as Payload;
  } catch {
    return null;
  }
}

/**
 * Cron: rebake the default location when either model has a new run (DESIGN §4.2a, §4.5).
 *
 * - New HRRR (its meta availability differs from `default:meta`, or the stored body is
 *   unusable): fetch HRRR, transform, top-level `fetched` = now. Otherwise the stored
 *   payload's HRRR part is reused byte for byte, so `start`, `hours` and `fetched` hold.
 * - NBM is fetched when its availability differs from `default:nbm_meta` or the HRRR
 *   horizon moved. Failure keeps the previous `extended` if it re-cuts onto the new
 *   `from`, else null, and clears `default:nbm_meta` so the next cron retries.
 * - KV is written only where a value changed, so an unchanged bake keeps its ETag.
 */
async function runScheduled(env: Env): Promise<void> {
  try {
    const [meta, nbmMeta] = await Promise.all([
      fetchMeta(),
      fetchNbmMeta().catch((e: unknown) => {
        console.error(`scheduled: NBM meta failed: ${errorText(e)}`);
        return null;
      }),
    ]);
    const availability = String(meta.last_run_availability_time);
    const nbmAvailability = nbmMeta ? String(nbmMeta.last_run_availability_time) : null;
    const [storedBody, storedMeta, storedNbm] = await Promise.all([
      env.WIND.get(KV_KEYS.body),
      env.WIND.get(KV_KEYS.meta),
      env.WIND.get(KV_KEYS.nbmMeta),
    ]);
    const previous = decodeStored(storedBody);
    const hrrrNew = previous === null || storedMeta !== availability;
    const nbmNew = nbmAvailability !== null && storedNbm !== nbmAvailability;
    if (!hrrrNew && !nbmNew) {
      console.log(`scheduled: unchanged (availability ${availability}, NBM ${storedNbm})`);
      return;
    }

    const now = Math.floor(Date.now() / 1000);
    let payload: Payload;
    if (hrrrNew) {
      const forecast = await fetchForecast({
        lat: DEFAULT_LOCATION.lat,
        lon: DEFAULT_LOCATION.lon,
        cell: "sea",
        timezone: "GMT",
      });
      const loc: Location = {
        ...DEFAULT_LOCATION,
        lat: forecast.latitude,
        lon: forecast.longitude,
        cell: "sea",
      };
      payload = transform(forecast, meta, { loc, fetched: now });
    } else {
      payload = { ...(previous as Payload), extended: null };
    }

    const { extended, ok } = await extendedFor(payload, {
      lat: DEFAULT_LOCATION.lat,
      lon: DEFAULT_LOCATION.lon,
      cell: "sea",
      nbmMeta,
      previous: previous?.extended ?? null,
      previousIsCurrent: !nbmNew && storedNbm !== null,
      now,
    });
    payload.extended = extended;
    const { body, etag } = await bake(payload);

    // Not atomic: a reader may briefly see the new body with the old etag, which
    // only costs it one extra 200 on its next check. Metas go last so a failed
    // write is retried by the next cron.
    if (body !== storedBody) {
      await env.WIND.put(KV_KEYS.body, body);
      await env.WIND.put(KV_KEYS.etag, etag);
    }
    if (storedMeta !== availability) await env.WIND.put(KV_KEYS.meta, availability);
    if (ok && nbmAvailability !== null && storedNbm !== nbmAvailability) await env.WIND.put(KV_KEYS.nbmMeta, nbmAvailability);
    if (!ok && storedNbm !== null) await env.WIND.delete(KV_KEYS.nbmMeta);
    const blocks = payload.extended?.blocks ?? 0;
    console.log(
      `scheduled: baked ${payload.hours} hours${hrrrNew ? " (new HRRR)" : ""} + ${blocks} NBM blocks${nbmNew ? " (new NBM)" : ""}, ` +
        `${new TextEncoder().encode(body).byteLength} bytes, etag ${etag}${body === storedBody ? " (unchanged)" : ""}`,
    );
  } catch (e) {
    // Last bake survives; the client labels its age.
    console.error(`scheduled: failed, keeping last bake: ${errorText(e)}`);
  }
}

// ---------------------------------------------------------------------------
// Responses

function jsonError(status: number, code: string, head: boolean): Response {
  return new Response(head ? null : JSON.stringify({ error: code }), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-cache", ...CORS_HEADERS },
  });
}

/** True if the request's If-None-Match covers `etag` (weak prefixes and lists allowed). */
export function etagMatches(ifNoneMatch: string | null, etag: string): boolean {
  if (!ifNoneMatch) return false;
  const strip = (s: string) => s.trim().replace(/^W\//i, "");
  const want = strip(etag);
  return ifNoneMatch.split(",").some((v) => {
    const t = strip(v);
    return t === "*" || t === want;
  });
}

function payloadResponse(body: string, etag: string, request: Request): Response {
  const headers = {
    "Content-Type": "application/json; charset=utf-8",
    ETag: etag,
    "Cache-Control": "no-cache",
    ...CORS_HEADERS,
  };
  if (etagMatches(request.headers.get("If-None-Match"), etag)) {
    return new Response(null, { status: 304, headers });
  }
  return new Response(request.method === "HEAD" ? null : body, { status: 200, headers });
}

// ---------------------------------------------------------------------------
// Default location: KV read

async function serveDefault(request: Request, env: Env): Promise<Response> {
  const [body, etag] = await Promise.all([env.WIND.get(KV_KEYS.body), env.WIND.get(KV_KEYS.etag)]);
  if (body === null || etag === null) return jsonError(503, "no_data", request.method === "HEAD");
  return payloadResponse(body, etag, request);
}

// ---------------------------------------------------------------------------
// Custom location: on-demand bake behind the Cache API

function parseCoordinate(raw: string | null, limit: number): number | null {
  if (raw === null || raw.trim() === "") return null;
  const n = Number(raw);
  if (!Number.isFinite(n) || Math.abs(n) > limit) return null;
  return Math.round(n * 100) / 100;
}

async function serveCustom(request: Request, ctx: ExecutionContext, rawLat: string | null, rawLon: string | null): Promise<Response> {
  const head = request.method === "HEAD";
  const lat = parseCoordinate(rawLat, 90);
  const lon = parseCoordinate(rawLon, 180);
  if (lat === null || lon === null) return jsonError(400, "bad_location", head);

  const cacheKey = new Request(`${CUSTOM_CACHE_ORIGIN}/v1/wind?lat=${lat}&lon=${lon}`, { method: "GET" });
  const cache = caches.default;

  const cached = await cache.match(cacheKey);
  if (cached) {
    const etag = cached.headers.get("ETag") ?? (await etagFor(await cached.clone().text()));
    return payloadResponse(await cached.text(), etag, request);
  }

  let body: string;
  let etag: string;
  try {
    const [meta, nbmMeta, forecast] = await Promise.all([
      fetchMeta(),
      fetchNbmMeta().catch(() => null),
      fetchForecast({ lat, lon, cell: "nearest", timezone: "auto" }),
    ]);
    const loc: Location = {
      name: "",
      lat: forecast.latitude,
      lon: forecast.longitude,
      tz: forecast.timezone || "UTC",
      cell: "nearest",
    };
    const now = Math.floor(Date.now() / 1000);
    const payload = transform(forecast, meta, { loc, fetched: now });
    // NBM failure (including a point outside its grid) → extended null, never an error.
    payload.extended = (
      await extendedFor(payload, { lat, lon, cell: "nearest", nbmMeta, previous: null, previousIsCurrent: false, now })
    ).extended;
    ({ body, etag } = await bake(payload));
  } catch (e) {
    console.error(`custom ${lat},${lon}: ${e instanceof Error ? e.message : String(e)}`);
    // Outside the HRRR grid (or all-null at its edge): a definite answer the client shows as such,
    // not a transient failure to retry.
    if (isOutsideCoverage(e) || (e instanceof Error && e.message.startsWith("transform: forecast has no"))) {
      return jsonError(422, "outside_coverage", head);
    }
    return jsonError(502, "upstream", head);
  }

  // Cache a copy for 10 minutes; the client-facing response stays no-cache.
  const forCache = new Response(body, {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ETag: etag,
      "Cache-Control": `max-age=${CUSTOM_CACHE_TTL}`,
    },
  });
  ctx.waitUntil(cache.put(cacheKey, forCache));

  return payloadResponse(body, etag, request);
}

// ---------------------------------------------------------------------------

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: { ...CORS_HEADERS, "Access-Control-Max-Age": "86400" } });
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      return jsonError(404, "not_found", request.method === "HEAD");
    }
    if (url.pathname !== "/v1/wind") return jsonError(404, "not_found", request.method === "HEAD");

    const lat = url.searchParams.get("lat");
    const lon = url.searchParams.get("lon");
    const custom = !(lat === null && lon === null);
    const res = custom ? await serveCustom(request, ctx, lat, lon) : await serveDefault(request, env);
    recordUsage(env.USAGE, request, custom, res.status);
    return res;
  },

  async scheduled(_controller: ScheduledController, env: Env, _ctx: ExecutionContext): Promise<void> {
    await runScheduled(env);
  },
} satisfies ExportedHandler<Env>;
