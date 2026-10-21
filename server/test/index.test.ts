import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { SELF, createExecutionContext, createScheduledController, env, waitOnExecutionContext } from "cloudflare:test";
import worker, { etagFor, etagMatches } from "../src/index.js";
import { KV_KEYS, USER_AGENT } from "../src/config.js";
import { forecastURL, metaURL } from "../src/openmeteo.js";
import forecastFixture from "../../fixtures/openmeteo-forecast-2026-10-21.json";
import metaFixture from "../../fixtures/openmeteo-meta-2026-10-21.json";
import type { Payload } from "../src/types.js";

const META_PATH = new URL(metaURL).pathname;

// ---------------------------------------------------------------------------
// Upstream mocking
//
// `cloudflare:test` no longer exports `fetchMock` (removed in pool-workers
// 0.23 / vitest-plugin 1.x). The `main` worker runs in the same isolate as the
// tests, so stubbing the global `fetch` is enough to intercept the Worker's
// outbound Open-Meteo calls, and `vi.stubGlobal` restores it afterwards.

interface Counters {
  meta: number;
  forecast: number;
  /** Every upstream request seen, in order. */
  requests: Request[];
}

interface MockOptions {
  metaStatus?: number;
  forecastStatus?: number;
  forecastBody?: unknown;
  meta?: unknown;
}

function mockUpstream(opts: MockOptions = {}): Counters {
  const counters: Counters = { meta: 0, forecast: 0, requests: [] };
  const json = (status: number, data: unknown) =>
    new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
  vi.stubGlobal("fetch", async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const req = new Request(input, init);
    counters.requests.push(req);
    const url = new URL(req.url);
    if (url.hostname !== "api.open-meteo.com") throw new Error(`unexpected outbound fetch: ${req.url}`);
    if (url.pathname === META_PATH) {
      counters.meta++;
      return json(opts.metaStatus ?? 200, opts.meta ?? metaFixture);
    }
    if (url.pathname === "/v1/forecast") {
      counters.forecast++;
      return json(opts.forecastStatus ?? 200, opts.forecastBody ?? forecastFixture);
    }
    throw new Error(`unexpected Open-Meteo path: ${url.pathname}`);
  });
  return counters;
}

async function runScheduled(): Promise<void> {
  const ctrl = createScheduledController({ cron: "*/10 * * * *", scheduledTime: new Date() });
  const ctx = createExecutionContext();
  await worker.scheduled(ctrl, env, ctx);
  await waitOnExecutionContext(ctx);
}

async function get(path: string, headers: Record<string, string> = {}, method = "GET"): Promise<Response> {
  const ctx = createExecutionContext();
  const res = await worker.fetch(new Request(`https://wind-watch.example${path}`, { method, headers }), env, ctx);
  await waitOnExecutionContext(ctx);
  return res;
}

async function clearState(): Promise<void> {
  await Promise.all(Object.values(KV_KEYS).map((k) => env.WIND.delete(k)));
  for (const q of ["lat=48.1&lon=-122.75", "lat=48.1&lon=-122.76", "lat=21.31&lon=-157.86"]) {
    await caches.default.delete(new Request(`https://wind-watch.cache/v1/wind?${q}`));
  }
}

beforeEach(async () => {
  await clearState();
  // Any test that forgets to mock gets a loud failure instead of a real network call.
  vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
    throw new Error(`unmocked fetch: ${new Request(input).url}`);
  });
});

afterEach(() => {
  vi.unstubAllGlobals();
});

// ---------------------------------------------------------------------------

describe("scheduled", () => {
  it("first run writes body, etag and meta; body decodes to 43 hours", async () => {
    const c = mockUpstream();
    await runScheduled();
    expect(c.meta).toBe(1);
    expect(c.forecast).toBe(1);
    for (const r of c.requests) expect(r.headers.get("User-Agent")).toBe(USER_AGENT);
    const q = new URL(c.requests[1]!.url).searchParams;
    expect(q.get("cell_selection")).toBe("sea");
    expect(q.get("timezone")).toBe("GMT");
    expect(q.get("timeformat")).toBe("unixtime");
    expect(q.get("latitude")).toBe("48.09");
    expect(q.get("longitude")).toBe("-122.76");

    const body = await env.WIND.get(KV_KEYS.body);
    const etag = await env.WIND.get(KV_KEYS.etag);
    const meta = await env.WIND.get(KV_KEYS.meta);
    expect(body).not.toBeNull();
    expect(etag).toMatch(/^"sha256-[0-9a-f]{16}"$/);
    expect(meta).toBe(String(metaFixture.last_run_availability_time));

    const payload = JSON.parse(body as string) as Payload;
    expect(payload.hours).toBe(43);
    expect(payload.loc.cell).toBe("sea");
    expect(payload.loc.name).toBe("Port Townsend Bay");
    // Snapped coordinates from the response, not the request constants.
    expect(payload.loc.lat).toBe(forecastFixture.latitude);
    expect(payload.loc.lon).toBe(forecastFixture.longitude);
    expect(payload.fetched).toBeGreaterThan(1792600000);
    expect(etag).toBe(await etagFor(body as string));
  });

  it("second run with identical meta makes no forecast request and no KV writes", async () => {
    const c = mockUpstream();
    await runScheduled();
    const before = {
      body: await env.WIND.get(KV_KEYS.body),
      etag: await env.WIND.get(KV_KEYS.etag),
      meta: await env.WIND.get(KV_KEYS.meta),
    };
    await runScheduled();
    expect(c.meta).toBe(2);
    expect(c.forecast).toBe(1);
    expect(await env.WIND.get(KV_KEYS.body)).toBe(before.body);
    expect(await env.WIND.get(KV_KEYS.etag)).toBe(before.etag);
    expect(await env.WIND.get(KV_KEYS.meta)).toBe(before.meta);
  });

  it("a new run rebakes", async () => {
    mockUpstream();
    await runScheduled();
    const first = await env.WIND.get(KV_KEYS.meta);
    const c = mockUpstream({ meta: { ...metaFixture, last_run_availability_time: metaFixture.last_run_availability_time + 3600 } });
    await runScheduled();
    expect(c.forecast).toBe(1);
    expect(await env.WIND.get(KV_KEYS.meta)).toBe(String(metaFixture.last_run_availability_time + 3600));
    expect(await env.WIND.get(KV_KEYS.meta)).not.toBe(first);
  });

  it("a forecast upstream 500 leaves KV untouched", async () => {
    const c = mockUpstream({ forecastStatus: 500 });
    await runScheduled();
    expect(c.forecast).toBe(1);
    expect(await env.WIND.get(KV_KEYS.body)).toBeNull();
    expect(await env.WIND.get(KV_KEYS.etag)).toBeNull();
    expect(await env.WIND.get(KV_KEYS.meta)).toBeNull();
  });

  it("a forecast that is entirely null leaves the previous bake in place", async () => {
    mockUpstream();
    await runScheduled();
    const before = await env.WIND.get(KV_KEYS.body);
    const h = forecastFixture.hourly;
    const nulls = h.time.map(() => null);
    mockUpstream({
      meta: { ...metaFixture, last_run_availability_time: metaFixture.last_run_availability_time + 3600 },
      forecastBody: { ...forecastFixture, hourly: { ...h, wind_speed_10m: nulls, wind_direction_10m: nulls, wind_gusts_10m: nulls } },
    });
    await runScheduled();
    expect(await env.WIND.get(KV_KEYS.body)).toBe(before);
    expect(await env.WIND.get(KV_KEYS.meta)).toBe(String(metaFixture.last_run_availability_time));
  });
});

describe("GET /v1/wind (default location)", () => {
  it("503 no_data when KV is empty", async () => {
    const res = await get("/v1/wind");
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ error: "no_data" });
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
  });

  it("200 with ETag and the §4.4 headers after a bake", async () => {
    mockUpstream();
    await runScheduled();
    const res = await get("/v1/wind");
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("application/json; charset=utf-8");
    expect(res.headers.get("ETag")).toMatch(/^"sha256-[0-9a-f]{16}"$/);
    expect(res.headers.get("Cache-Control")).toBe("no-cache");
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(res.headers.get("Access-Control-Expose-Headers")).toBe("ETag");
    expect(res.headers.get("Content-Encoding")).toBeNull();
    const payload = (await res.json()) as Payload;
    expect(payload.hours).toBe(43);
    expect(payload.v).toBe(1);
  });

  it("304 on a matching If-None-Match, also with a W/ prefix and in a list; 200 otherwise", async () => {
    mockUpstream();
    await runScheduled();
    const etag = (await get("/v1/wind")).headers.get("ETag") as string;

    const same = await get("/v1/wind", { "If-None-Match": etag });
    expect(same.status).toBe(304);
    expect(same.headers.get("ETag")).toBe(etag);
    expect(await same.text()).toBe("");

    expect((await get("/v1/wind", { "If-None-Match": `W/${etag}` })).status).toBe(304);
    expect((await get("/v1/wind", { "If-None-Match": `"sha256-0000000000000000", ${etag}` })).status).toBe(304);
    expect((await get("/v1/wind", { "If-None-Match": '"sha256-0000000000000000"' })).status).toBe(200);
  });

  it("HEAD behaves like GET without a body", async () => {
    mockUpstream();
    await runScheduled();
    const res = await get("/v1/wind", {}, "HEAD");
    expect(res.status).toBe(200);
    expect(res.headers.get("ETag")).toMatch(/^"sha256-/);
    expect(await res.text()).toBe("");
  });

  it("is reachable through the SELF service binding", async () => {
    mockUpstream();
    await runScheduled();
    const res = await SELF.fetch("https://wind-watch.example/v1/wind");
    expect(res.status).toBe(200);
    expect(((await res.json()) as Payload).hours).toBe(43);
  });
});

describe("GET /v1/wind?lat&lon (custom location)", () => {
  const customForecast = { ...forecastFixture, timezone: "America/Los_Angeles", utc_offset_seconds: -25200, latitude: 48.098, longitude: -122.739 };

  it("400 bad_location for non-numeric, out-of-range or missing coordinates", async () => {
    for (const q of ["lat=abc&lon=-122.75", "lat=91&lon=-122.75", "lat=48.1", "lon=-122.75", "lat=48.1&lon=181", "lat=&lon=1"]) {
      const res = await get(`/v1/wind?${q}`);
      expect(res.status, q).toBe(400);
      expect(await res.json()).toEqual({ error: "bad_location" });
    }
  });

  it("200 with cell nearest and the tz from the upstream response; rounds to 2 dp", async () => {
    const c = mockUpstream({ forecastBody: customForecast });
    const res = await get("/v1/wind?lat=48.1004&lon=-122.7496");
    expect(res.status).toBe(200);
    expect(res.headers.get("ETag")).toMatch(/^"sha256-/);
    expect(res.headers.get("Cache-Control")).toBe("no-cache");
    const payload = (await res.json()) as Payload;
    expect(payload.loc).toEqual({ name: "", lat: 48.098, lon: -122.739, tz: "America/Los_Angeles", cell: "nearest" });
    expect(payload.hours).toBe(43);
    expect(c.forecast).toBe(1);
    expect(c.meta).toBe(1);
  });

  it("requests the upstream with cell_selection=nearest and timezone=auto", async () => {
    const c = mockUpstream({ forecastBody: customForecast });
    await get("/v1/wind?lat=48.1004&lon=-122.7496");
    const sent = c.requests.find((r) => new URL(r.url).pathname === "/v1/forecast")!;
    expect(sent.url).toBe(forecastURL({ lat: 48.1, lon: -122.75, cell: "nearest", timezone: "auto" }));
    const url = new URL(sent.url);
    expect(url.searchParams.get("cell_selection")).toBe("nearest");
    expect(url.searchParams.get("timezone")).toBe("auto");
    expect(url.searchParams.get("latitude")).toBe("48.1");
    expect(url.searchParams.get("longitude")).toBe("-122.75");
    expect(url.searchParams.get("forecast_hours")).toBe("50");
    expect(url.searchParams.get("wind_speed_unit")).toBe("kn");
    expect(url.searchParams.get("models")).toBe("ncep_hrrr_conus");
  });

  it("a second identical request is served from the cache without an upstream call", async () => {
    const c = mockUpstream({ forecastBody: customForecast });
    const first = await get("/v1/wind?lat=48.10&lon=-122.75");
    expect(first.status).toBe(200);
    const second = await get("/v1/wind?lat=48.1&lon=-122.750");
    expect(second.status).toBe(200);
    expect(second.headers.get("ETag")).toBe(first.headers.get("ETag"));
    expect(second.headers.get("Cache-Control")).toBe("no-cache");
    expect(await second.text()).toBe(await first.text());
    expect(c.forecast).toBe(1);
    expect(c.meta).toBe(1);
  });

  it("honours If-None-Match with 304", async () => {
    mockUpstream({ forecastBody: customForecast });
    const etag = (await get("/v1/wind?lat=48.1&lon=-122.75")).headers.get("ETag") as string;
    const res = await get("/v1/wind?lat=48.1&lon=-122.75", { "If-None-Match": etag });
    expect(res.status).toBe(304);
    expect(await res.text()).toBe("");
  });

  it("502 upstream when Open-Meteo fails and nothing is cached", async () => {
    mockUpstream({ forecastStatus: 500 });
    const res = await get("/v1/wind?lat=21.31&lon=-157.86");
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ error: "upstream" });
  });
});

describe("other routes", () => {
  it("404 not_found for unknown paths and methods", async () => {
    expect((await get("/")).status).toBe(404);
    expect(await (await get("/v2/wind")).json()).toEqual({ error: "not_found" });
    expect((await get("/v1/wind", {}, "POST")).status).toBe(404);
  });

  it("OPTIONS → 204 with CORS headers", async () => {
    const res = await get("/v1/wind", { Origin: "https://example.org" }, "OPTIONS");
    expect(res.status).toBe(204);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(res.headers.get("Access-Control-Allow-Methods")).toContain("GET");
    expect(res.headers.get("Access-Control-Allow-Headers")).toContain("If-None-Match");
  });
});

describe("etag helpers", () => {
  it("etagFor is deterministic and formatted per §4.4", async () => {
    const a = await etagFor('{"v":1}');
    expect(a).toMatch(/^"sha256-[0-9a-f]{16}"$/);
    expect(await etagFor('{"v":1}')).toBe(a);
    expect(await etagFor('{"v":2}')).not.toBe(a);
  });

  it("etagMatches handles weak tags, lists and *", () => {
    const e = '"sha256-abcdef0123456789"';
    expect(etagMatches(e, e)).toBe(true);
    expect(etagMatches(`W/${e}`, e)).toBe(true);
    expect(etagMatches(`"x", ${e}`, e)).toBe(true);
    expect(etagMatches("*", e)).toBe(true);
    expect(etagMatches('"x"', e)).toBe(false);
    expect(etagMatches(null, e)).toBe(false);
    expect(etagMatches("", e)).toBe(false);
  });
});
