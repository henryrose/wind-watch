// Worker entry point: `scheduled` bakes the default location into KV every 10
// minutes (DESIGN §4.5); `fetch` serves it at GET /v1/wind with an ETag
// (§4.4) and bakes custom locations on demand behind the Cache API (§7).

import { CUSTOM_CACHE_ORIGIN, CUSTOM_CACHE_TTL, DEFAULT_LOCATION, KV_KEYS } from "./config.js";
import { fetchForecast, fetchMeta, isOutsideCoverage } from "./openmeteo.js";
import { serializePayload } from "./stableStringify.js";
import { transform } from "./transform.js";
import type { Location, OpenMeteoForecast, OpenMeteoMeta } from "./types.js";
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
  hours: number;
}

/** Transform + serialise + hash. Throws on an empty forecast (transform) so callers keep the last bake. */
async function bake(forecast: OpenMeteoForecast, meta: OpenMeteoMeta, loc: Location, fetched: number): Promise<Bake> {
  const payload = transform(forecast, meta, { loc, fetched });
  const body = serializePayload(payload);
  return { body, etag: await etagFor(body), hours: payload.hours };
}

/** `"sha256-<first 16 hex of SHA-256(body)>"` (DESIGN §4.4). */
export async function etagFor(body: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(body));
  const hex = Array.from(new Uint8Array(digest).slice(0, 8), (b) => b.toString(16).padStart(2, "0")).join("");
  return `"sha256-${hex}"`;
}

/** Cron: refresh the default location only when Open-Meteo has a new run. */
async function runScheduled(env: Env): Promise<void> {
  try {
    const meta = await fetchMeta();
    const availability = String(meta.last_run_availability_time);
    const stored = await env.WIND.get(KV_KEYS.meta);
    if (stored === availability) {
      console.log(`scheduled: unchanged (availability ${availability})`);
      return;
    }

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
    const fetched = Math.floor(Date.now() / 1000);
    const { body, etag, hours } = await bake(forecast, meta, loc, fetched);

    // Three writes, not atomic: a reader may briefly see the new body with the
    // old etag, which only costs it one extra 200 on its next check.
    await env.WIND.put(KV_KEYS.body, body);
    await env.WIND.put(KV_KEYS.etag, etag);
    await env.WIND.put(KV_KEYS.meta, availability);
    console.log(`scheduled: baked ${hours} hours, ${new TextEncoder().encode(body).byteLength} bytes, etag ${etag}`);
  } catch (e) {
    // Last bake survives; the client labels its age.
    console.error(`scheduled: failed, keeping last bake: ${e instanceof Error ? e.message : String(e)}`);
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
    const [meta, forecast] = await Promise.all([
      fetchMeta(),
      fetchForecast({ lat, lon, cell: "nearest", timezone: "auto" }),
    ]);
    const loc: Location = {
      name: "",
      lat: forecast.latitude,
      lon: forecast.longitude,
      tz: forecast.timezone || "UTC",
      cell: "nearest",
    };
    ({ body, etag } = await bake(forecast, meta, loc, Math.floor(Date.now() / 1000)));
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
