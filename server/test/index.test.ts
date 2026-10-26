import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { SELF, createExecutionContext, createScheduledController, env, waitOnExecutionContext } from "cloudflare:test";
import worker, { decodeStored, etagFor, etagMatches } from "../src/index.js";
import { KV_KEYS, USER_AGENT } from "../src/config.js";
import { forecastURL, metaURL, nbmMetaURL } from "../src/openmeteo.js";
import { serializePayload } from "../src/stableStringify.js";
import forecastFixture from "../../fixtures/openmeteo-forecast-2026-10-26.json";
import metaFixture from "../../fixtures/openmeteo-meta-2026-10-26.json";
import nbmFixture from "../../fixtures/openmeteo-nbm-forecast-2026-10-26.json";
import nbmMetaFixture from "../../fixtures/openmeteo-nbm-meta-2026-10-26.json";
import type { Payload } from "../src/types.js";

// The handler tests run on the 26 Oct capture: HRRR with the §4.2a series (44 hours from
// 17Z) and the NBM response for exactly its window (13Z +2 d → 15Z +7 d, 123 hours).

const META_PATH = new URL(metaURL).pathname;
const NBM_META_PATH = new URL(nbmMetaURL).pathname;
const HOUR = 3600;
const START = forecastFixture.hourly.time[0]!;
const HRRR_HOURS = 44;
const FROM = START + HRRR_HOURS * HOUR;

// ---------------------------------------------------------------------------
// Upstream mocking
//
// `cloudflare:test` no longer exports `fetchMock` (removed in pool-workers
// 0.23 / vitest-plugin 1.x). The `main` worker runs in the same isolate as the
// tests, so stubbing the global `fetch` is enough to intercept the Worker's
// outbound Open-Meteo calls, and `vi.stubGlobal` restores it afterwards.

interface Counters {
  meta: number;
  nbmMeta: number;
  /** HRRR forecast requests. */
  forecast: number;
  /** NBM forecast requests. */
  nbm: number;
  /** Every upstream request seen, in order. */
  requests: Request[];
}

interface MockOptions {
  metaStatus?: number;
  meta?: unknown;
  nbmMetaStatus?: number;
  nbmMeta?: unknown;
  forecastStatus?: number;
  forecastBody?: unknown;
  nbmStatus?: number;
  nbmBody?: unknown;
}

function mockUpstream(opts: MockOptions = {}): Counters {
  const counters: Counters = { meta: 0, nbmMeta: 0, forecast: 0, nbm: 0, requests: [] };
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
    if (url.pathname === NBM_META_PATH) {
      counters.nbmMeta++;
      return json(opts.nbmMetaStatus ?? 200, opts.nbmMeta ?? nbmMetaFixture);
    }
    if (url.pathname === "/v1/forecast" && url.searchParams.get("models") === "ncep_nbm_conus") {
      counters.nbm++;
      return json(opts.nbmStatus ?? 200, opts.nbmBody ?? nbmFixture);
    }
    if (url.pathname === "/v1/forecast") {
      counters.forecast++;
      return json(opts.forecastStatus ?? 200, opts.forecastBody ?? forecastFixture);
    }
    throw new Error(`unexpected Open-Meteo path: ${url.pathname}`);
  });
  return counters;
}

/** Requests to a given model's forecast endpoint. */
function forecastRequests(c: Counters, model: string): URL[] {
  return c.requests.map((r) => new URL(r.url)).filter((u) => u.pathname === "/v1/forecast" && u.searchParams.get("models") === model);
}

const newHrrrMeta = { ...metaFixture, last_run_availability_time: metaFixture.last_run_availability_time + 3600 };
const newNbmMeta = {
  ...nbmMetaFixture,
  last_run_availability_time: nbmMetaFixture.last_run_availability_time + 3600,
  last_run_initialisation_time: nbmMetaFixture.last_run_initialisation_time + 3600,
};

async function storedPayload(): Promise<Payload> {
  return JSON.parse((await env.WIND.get(KV_KEYS.body)) as string) as Payload;
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
  for (const q of ["lat=48.1&lon=-122.75", "lat=48.1&lon=-122.76", "lat=21.31&lon=-157.86", "lat=51.5&lon=-0.12"]) {
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
  it("first run writes body, etag and both metas; HRRR 44 hours + NBM from the horizon", async () => {
    const c = mockUpstream();
    await runScheduled();
    expect(c.meta).toBe(1);
    expect(c.nbmMeta).toBe(1);
    expect(c.forecast).toBe(1);
    expect(c.nbm).toBe(1);
    for (const r of c.requests) expect(r.headers.get("User-Agent")).toBe(USER_AGENT);
    const [hrrr] = forecastRequests(c, "ncep_hrrr_conus");
    const q = hrrr!.searchParams;
    expect(q.get("cell_selection")).toBe("sea");
    expect(q.get("timezone")).toBe("GMT");
    expect(q.get("timeformat")).toBe("unixtime");
    expect(q.get("latitude")).toBe("48.09");
    expect(q.get("longitude")).toBe("-122.76");
    expect(q.get("hourly")).toBe("wind_speed_10m,wind_direction_10m,wind_gusts_10m,temperature_2m,cloud_cover,precipitation");

    // NBM is asked for exactly [start + hours h, start + 168 h) in whole blocks: 13Z Oct 28 → 15Z Nov 2 inclusive.
    const [nbm] = forecastRequests(c, "ncep_nbm_conus");
    const n = nbm!.searchParams;
    expect(n.get("start_hour")).toBe("2026-10-28T13:00");
    expect(n.get("end_hour")).toBe("2026-11-02T15:00");
    expect(n.get("timezone")).toBe("GMT");
    expect(n.get("cell_selection")).toBe("sea");
    expect(n.get("wind_speed_unit")).toBe("kn");
    expect(n.get("hourly")).toBe(q.get("hourly"));
    expect(n.has("forecast_hours")).toBe(false);

    const body = await env.WIND.get(KV_KEYS.body);
    const etag = await env.WIND.get(KV_KEYS.etag);
    expect(body).not.toBeNull();
    expect(etag).toMatch(/^"sha256-[0-9a-f]{16}"$/);
    expect(await env.WIND.get(KV_KEYS.meta)).toBe(String(metaFixture.last_run_availability_time));
    expect(await env.WIND.get(KV_KEYS.nbmMeta)).toBe(String(nbmMetaFixture.last_run_availability_time));

    const payload = JSON.parse(body as string) as Payload;
    expect(payload.hours).toBe(HRRR_HOURS);
    expect(payload.loc.cell).toBe("sea");
    expect(payload.loc.name).toBe("Port Townsend Bay");
    // Snapped coordinates from the response, not the request constants.
    expect(payload.loc.lat).toBe(forecastFixture.latitude);
    expect(payload.loc.lon).toBe(forecastFixture.longitude);
    expect(payload.fetched).toBeGreaterThan(1793030000);
    expect(etag).toBe(await etagFor(body as string));

    const ext = payload.extended!;
    expect(ext.model).toBe("ncep_nbm_conus");
    expect(ext.run).toBe(nbmMetaFixture.last_run_initialisation_time);
    expect(ext.fetched).toBe(payload.fetched);
    expect(ext.from).toBe(payload.start + payload.hours * HOUR);
    expect(ext.blocks).toBe(41);
    expect(ext.from + ext.blocks * 3 * HOUR).toBeLessThanOrEqual(payload.start + 168 * HOUR);
    // Key order: §4.2a appends after `sun`, extended's keys in contract order.
    expect(Object.keys(payload).slice(-5)).toEqual(["sun", "temp", "cloud", "precip", "extended"]);
    expect(Object.keys(ext)).toEqual(["model", "run", "fetched", "step", "from", "blocks", "kn", "gust", "dir", "temp", "cloud", "precip"]);
  });

  it("second run with identical metas makes no forecast request and no KV writes", async () => {
    const c = mockUpstream();
    await runScheduled();
    const before = {
      body: await env.WIND.get(KV_KEYS.body),
      etag: await env.WIND.get(KV_KEYS.etag),
      meta: await env.WIND.get(KV_KEYS.meta),
    };
    await runScheduled();
    expect(c.meta).toBe(2);
    expect(c.nbmMeta).toBe(2);
    expect(c.forecast).toBe(1);
    expect(c.nbm).toBe(1);
    expect(await env.WIND.get(KV_KEYS.body)).toBe(before.body);
    expect(await env.WIND.get(KV_KEYS.etag)).toBe(before.etag);
    expect(await env.WIND.get(KV_KEYS.meta)).toBe(before.meta);
  });

  it("a new HRRR run rebakes; same NBM run and same horizon reuses extended without an NBM call", async () => {
    mockUpstream();
    await runScheduled();
    const first = await storedPayload();
    const c = mockUpstream({ meta: newHrrrMeta });
    await runScheduled();
    expect(c.forecast).toBe(1);
    expect(c.nbm).toBe(0);
    expect(await env.WIND.get(KV_KEYS.meta)).toBe(String(newHrrrMeta.last_run_availability_time));
    const second = await storedPayload();
    expect(second.fetched).toBeGreaterThanOrEqual(first.fetched);
    expect(second.extended).toEqual(first.extended);
  });

  it("a new HRRR run with a moved horizon refetches NBM for the new window; extended.fetched holds for the same NBM run", async () => {
    mockUpstream();
    await runScheduled();
    const first = await storedPayload();
    // HRRR now ends 3 h earlier: 41 hours → from moves back one block, 42 blocks fit.
    const h = forecastFixture.hourly;
    const cut = <T,>(xs: T[]) => xs.map((v, i) => (i >= 41 ? null : v));
    const shorter = {
      ...forecastFixture,
      hourly: { ...h, wind_speed_10m: cut(h.wind_speed_10m), wind_gusts_10m: cut(h.wind_gusts_10m), wind_direction_10m: cut(h.wind_direction_10m) },
    };
    const c = mockUpstream({ meta: newHrrrMeta, forecastBody: shorter });
    await runScheduled();
    expect(c.nbm).toBe(1);
    expect(forecastRequests(c, "ncep_nbm_conus")[0]!.searchParams.get("start_hour")).toBe("2026-10-28T10:00");
    const p = await storedPayload();
    expect(p.hours).toBe(41);
    // The fixture has no hours before 13Z, so block 0 is missing and nothing is usable:
    // aggregation fails, and the previous extended (from 13Z) can't be re-cut onto 10Z.
    expect(p.extended).toBeNull();
    expect(await env.WIND.get(KV_KEYS.nbmMeta)).toBeNull();
    expect(first.extended).not.toBeNull();
  });

  it("a new NBM run alone rebakes extended only: HRRR part and top-level fetched unchanged", async () => {
    mockUpstream();
    await runScheduled();
    const first = await storedPayload();
    const firstEtag = await env.WIND.get(KV_KEYS.etag);
    const c = mockUpstream({ nbmMeta: newNbmMeta });
    await runScheduled();
    expect(c.forecast).toBe(0);
    expect(c.nbm).toBe(1);
    const second = await storedPayload();
    expect(second.fetched).toBe(first.fetched);
    expect(second.start).toBe(first.start);
    expect(second.kn).toEqual(first.kn);
    expect(second.extended!.run).toBe(newNbmMeta.last_run_initialisation_time);
    expect(second.extended!.fetched).toBeGreaterThanOrEqual(first.extended!.fetched);
    expect(await env.WIND.get(KV_KEYS.etag)).not.toBe(firstEtag);
    expect(await env.WIND.get(KV_KEYS.nbmMeta)).toBe(String(newNbmMeta.last_run_availability_time));
  });

  it("NBM failure with the same horizon keeps the previous extended and retries next cron", async () => {
    mockUpstream();
    await runScheduled();
    const first = await storedPayload();
    const firstEtag = await env.WIND.get(KV_KEYS.etag);

    const c = mockUpstream({ nbmMeta: newNbmMeta, nbmStatus: 500 });
    await runScheduled();
    expect(c.nbm).toBe(1);
    expect(await storedPayload()).toEqual(first);
    expect(await env.WIND.get(KV_KEYS.etag)).toBe(firstEtag);
    // Cleared so the next cron tries again even though the NBM meta hasn't moved.
    expect(await env.WIND.get(KV_KEYS.nbmMeta)).toBeNull();

    const d = mockUpstream({ nbmMeta: newNbmMeta });
    await runScheduled();
    expect(d.nbm).toBe(1);
    expect(d.forecast).toBe(0);
    expect((await storedPayload()).extended!.run).toBe(newNbmMeta.last_run_initialisation_time);
    expect(await env.WIND.get(KV_KEYS.nbmMeta)).toBe(String(newNbmMeta.last_run_availability_time));
  });

  it("NBM failure on a later HRRR horizon keeps the previous extended re-cut to whole blocks at the new from", async () => {
    // First bake with HRRR cut to 38 hours: from = 07Z Oct 28, 43 blocks to 17Z Nov 2.
    const h = forecastFixture.hourly;
    const cut = <T,>(xs: T[]) => xs.map((v, i) => (i >= 38 ? null : v));
    const shorter = {
      ...forecastFixture,
      hourly: { ...h, wind_speed_10m: cut(h.wind_speed_10m), wind_gusts_10m: cut(h.wind_gusts_10m), wind_direction_10m: cut(h.wind_direction_10m) },
    };
    // NBM for that window: shift the 13Z fixture back 6 h so it starts at 07Z.
    const shifted = { ...nbmFixture, hourly: { ...nbmFixture.hourly, time: nbmFixture.hourly.time.map((t) => t - 6 * HOUR) } };
    mockUpstream({ forecastBody: shorter, nbmBody: shifted });
    await runScheduled();
    const first = await storedPayload();
    expect(first.extended!.from).toBe(START + 38 * HOUR);
    expect(first.extended!.blocks).toBe(41);

    // New HRRR run reaches 44 hours (from + 6 h, two whole blocks later); NBM is down.
    const c = mockUpstream({ meta: newHrrrMeta, nbmStatus: 503 });
    await runScheduled();
    expect(c.nbm).toBe(1);
    const p = await storedPayload();
    expect(p.hours).toBe(44);
    expect(p.extended!.from).toBe(FROM);
    expect(p.extended!.blocks).toBe(39);
    expect(p.extended!.kn).toEqual(first.extended!.kn.slice(2));
    expect(p.extended!.run).toBe(first.extended!.run);
    expect(p.extended!.fetched).toBe(first.extended!.fetched);
  });

  it("NBM failure on a horizon that isn't a whole number of blocks later makes extended null; HRRR still bakes", async () => {
    const h = forecastFixture.hourly;
    const cut = <T,>(xs: T[]) => xs.map((v, i) => (i >= 43 ? null : v));
    const shorter = {
      ...forecastFixture,
      hourly: { ...h, wind_speed_10m: cut(h.wind_speed_10m), wind_gusts_10m: cut(h.wind_gusts_10m), wind_direction_10m: cut(h.wind_direction_10m) },
    };
    const shifted = { ...nbmFixture, hourly: { ...nbmFixture.hourly, time: nbmFixture.hourly.time.map((t) => t - HOUR) } };
    mockUpstream({ forecastBody: shorter, nbmBody: shifted });
    await runScheduled();
    expect((await storedPayload()).extended!.from).toBe(FROM - HOUR);

    const c = mockUpstream({ meta: newHrrrMeta, nbmBody: { error: true, reason: "boom" }, nbmStatus: 500 });
    await runScheduled();
    expect(c.forecast).toBe(1);
    const p = await storedPayload();
    expect(p.hours).toBe(44);
    expect(p.extended).toBeNull();
    expect(await env.WIND.get(KV_KEYS.meta)).toBe(String(newHrrrMeta.last_run_availability_time));
  });

  it("an all-null NBM response or a failed NBM meta never fails the bake", async () => {
    const nulls = nbmFixture.hourly.time.map(() => null);
    mockUpstream({ nbmBody: { ...nbmFixture, hourly: { ...nbmFixture.hourly, wind_speed_10m: nulls } } });
    await runScheduled();
    expect((await storedPayload()).extended).toBeNull();
    expect((await storedPayload()).hours).toBe(HRRR_HOURS);
    expect(await env.WIND.get(KV_KEYS.nbmMeta)).toBeNull();

    await clearState();
    const c = mockUpstream({ nbmMetaStatus: 500 });
    await runScheduled();
    expect(c.nbm).toBe(0);
    expect((await storedPayload()).extended).toBeNull();
    expect((await storedPayload()).hours).toBe(HRRR_HOURS);
  });

  it("a stored body from before §4.2a counts as no bake: HRRR is refetched even if its meta is unchanged", async () => {
    mockUpstream();
    await runScheduled();
    const p = await storedPayload();
    const legacy = { ...p } as Partial<Payload>;
    delete legacy.temp;
    delete legacy.cloud;
    delete legacy.precip;
    delete legacy.extended;
    await env.WIND.put(KV_KEYS.body, JSON.stringify(legacy));
    expect(decodeStored(JSON.stringify(legacy))).toBeNull();
    const c = mockUpstream();
    await runScheduled();
    expect(c.forecast).toBe(1);
    expect((await storedPayload()).temp).toHaveLength(HRRR_HOURS);
  });

  it("the stored body is the stable serialisation (ETag is a pure function of the payload)", async () => {
    mockUpstream();
    await runScheduled();
    const body = (await env.WIND.get(KV_KEYS.body)) as string;
    expect(serializePayload(JSON.parse(body) as Payload)).toBe(body);
    expect(await env.WIND.get(KV_KEYS.etag)).toBe(await etagFor(body));
  });

  it("a forecast upstream 500 leaves KV untouched", async () => {
    const c = mockUpstream({ forecastStatus: 500 });
    await runScheduled();
    expect(c.forecast).toBe(1);
    expect(c.nbm).toBe(0);
    expect(await env.WIND.get(KV_KEYS.body)).toBeNull();
    expect(await env.WIND.get(KV_KEYS.etag)).toBeNull();
    expect(await env.WIND.get(KV_KEYS.meta)).toBeNull();
    expect(await env.WIND.get(KV_KEYS.nbmMeta)).toBeNull();
  });

  it("a forecast that is entirely null leaves the previous bake in place", async () => {
    mockUpstream();
    await runScheduled();
    const before = await env.WIND.get(KV_KEYS.body);
    const h = forecastFixture.hourly;
    const nulls = h.time.map(() => null);
    mockUpstream({
      meta: newHrrrMeta,
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
    expect(payload.hours).toBe(HRRR_HOURS);
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
    expect(((await res.json()) as Payload).hours).toBe(HRRR_HOURS);
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
    expect(payload.hours).toBe(HRRR_HOURS);
    expect(payload.extended!.from).toBe(payload.start + payload.hours * HOUR);
    expect(payload.extended!.blocks).toBe(41);
    expect(payload.extended!.fetched).toBe(payload.fetched);
    expect(c.forecast).toBe(1);
    expect(c.meta).toBe(1);
    expect(c.nbmMeta).toBe(1);
    expect(c.nbm).toBe(1);
    const nbm = forecastRequests(c, "ncep_nbm_conus")[0]!;
    expect(nbm.searchParams.get("cell_selection")).toBe("nearest");
    expect(nbm.searchParams.get("timezone")).toBe("GMT");
    expect(nbm.searchParams.get("latitude")).toBe("48.1");
    expect(nbm.searchParams.get("longitude")).toBe("-122.75");
  });

  it("NBM failing (error, outside its grid, or meta down) gives extended null, never an error", async () => {
    const cases: MockOptions[] = [
      { nbmStatus: 500 },
      { nbmStatus: 400, nbmBody: { error: true, reason: "No data is available for this location" } },
      { nbmMetaStatus: 503 },
    ];
    for (const [i, opts] of cases.entries()) {
      await clearState();
      mockUpstream({ forecastBody: customForecast, ...opts });
      const res = await get("/v1/wind?lat=48.1&lon=-122.75");
      expect(res.status, String(i)).toBe(200);
      const payload = (await res.json()) as Payload;
      expect(payload.extended, String(i)).toBeNull();
      expect(payload.hours).toBe(HRRR_HOURS);
      expect(payload.temp).toHaveLength(HRRR_HOURS);
    }
  });

  it("requests the upstream with cell_selection=nearest and timezone=auto", async () => {
    const c = mockUpstream({ forecastBody: customForecast });
    await get("/v1/wind?lat=48.1004&lon=-122.7496");
    const sent = c.requests.find((r) => new URL(r.url).searchParams.get("models") === "ncep_hrrr_conus")!;
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
    expect(c.nbm).toBe(1);
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

  it("422 outside_coverage when Open-Meteo has no HRRR data for the point", async () => {
    mockUpstream({ forecastStatus: 400, forecastBody: { error: true, reason: "No data is available for this location" } });
    const res = await get("/v1/wind?lat=51.5&lon=-0.12");
    expect(res.status).toBe(422);
    expect(await res.json()).toEqual({ error: "outside_coverage" });
  });

  it("422 outside_coverage when every hour is null (the grid edge)", async () => {
    const nulls = forecastFixture.hourly.time.map(() => null);
    const empty = { ...forecastFixture, hourly: { ...forecastFixture.hourly, wind_speed_10m: nulls, wind_gusts_10m: nulls, wind_direction_10m: nulls } };
    mockUpstream({ forecastBody: empty });
    const res = await get("/v1/wind?lat=51.5&lon=-0.12");
    expect(res.status).toBe(422);
  });

  it("other upstream 400s stay 502", async () => {
    mockUpstream({ forecastStatus: 400, forecastBody: { error: true, reason: "Parameter 'hourly' is invalid" } });
    const res = await get("/v1/wind?lat=21.31&lon=-157.86");
    expect(res.status).toBe(502);
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
    expect(res.headers.get("Access-Control-Allow-Headers")).toContain("X-WW-Client");
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
