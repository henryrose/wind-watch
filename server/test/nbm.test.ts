import { describe, expect, it } from "vitest";
import forecastFixture from "../../fixtures/openmeteo-forecast-2026-10-26.json";
import metaFixture from "../../fixtures/openmeteo-meta-2026-10-26.json";
import nbmFixture from "../../fixtures/openmeteo-nbm-forecast-2026-10-26.json";
import nbmMetaFixture from "../../fixtures/openmeteo-nbm-meta-2026-10-26.json";
import { aggregateNbm, enforceExtended, lastHour, nbmWindow, trimExtended, vectorMeanDegrees } from "../src/nbm.js";
import { nbmURL } from "../src/openmeteo.js";
import { serializePayload } from "../src/stableStringify.js";
import { fillNearest, round1, transform } from "../src/transform.js";
import type { Extended, Location, OpenMeteoForecast, OpenMeteoMeta } from "../src/types.js";

const HOUR = 3600;
const forecast = forecastFixture as OpenMeteoForecast;
const meta = metaFixture as OpenMeteoMeta;
const nbm = nbmFixture as OpenMeteoForecast;
const nbmMeta = nbmMetaFixture as OpenMeteoMeta;

const LOC: Location = { name: "Port Townsend Bay", lat: 48.09075, lon: -122.777275, tz: "America/Los_Angeles", cell: "sea" };
const FETCHED = forecast.hourly.time[0]! + 1200;

const payload = transform(forecast, meta, { loc: LOC, fetched: FETCHED });
const window = nbmWindow(payload.start, payload.hours);

/** A small hourly NBM response from `from`, `n` hours, with per-hour overrides. */
function nbmHours(from: number, n: number, f: (i: number) => Partial<Record<string, number | null>> = () => ({})): OpenMeteoForecast {
  const h = {
    time: [] as number[],
    wind_speed_10m: [] as (number | null)[],
    wind_direction_10m: [] as (number | null)[],
    wind_gusts_10m: [] as (number | null)[],
    temperature_2m: [] as (number | null)[],
    cloud_cover: [] as (number | null)[],
    precipitation: [] as (number | null)[],
  };
  for (let i = 0; i < n; i++) {
    const o = { wind_speed_10m: 5, wind_direction_10m: 180, wind_gusts_10m: 8, temperature_2m: 10, cloud_cover: 50, precipitation: 0, ...f(i) };
    h.time.push(from + i * HOUR);
    h.wind_speed_10m.push(o.wind_speed_10m);
    h.wind_direction_10m.push(o.wind_direction_10m);
    h.wind_gusts_10m.push(o.wind_gusts_10m);
    h.temperature_2m.push(o.temperature_2m);
    h.cloud_cover.push(o.cloud_cover);
    h.precipitation.push(o.precipitation);
  }
  return { latitude: 48.1, longitude: -122.76, utc_offset_seconds: 0, timezone: "GMT", hourly: h };
}

describe("HRRR sky and temperature (26 Oct fixture)", () => {
  it("temp, cloud, precip have length == hours and the contract's precision", () => {
    expect(payload.hours).toBe(44);
    for (const key of ["temp", "cloud", "precip"] as const) expect(payload[key]).toHaveLength(payload.hours);
    for (const c of payload.cloud) {
      expect(Number.isInteger(c)).toBe(true);
      expect(c).toBeGreaterThanOrEqual(0);
      expect(c).toBeLessThanOrEqual(100);
    }
    for (const v of [...payload.temp, ...payload.precip]) expect(round1(v)).toBe(v);
    for (const p of payload.precip) expect(p).toBeGreaterThanOrEqual(0);
    expect(payload.temp.slice(0, 3)).toEqual([10.7, 11.2, 11.4]);
    expect(payload.cloud.slice(0, 3)).toEqual([100, 67, 88]);
    expect(payload.extended).toBeNull();
  });

  it("a sky/temperature null inside the wind range takes its nearest neighbour; wind is not truncated", () => {
    const h = forecast.hourly;
    const temp = [...h.temperature_2m!];
    temp[5] = null;
    temp[6] = null;
    const cloud = [...h.cloud_cover!];
    cloud[0] = null;
    const p = transform({ ...forecast, hourly: { ...h, temperature_2m: temp, cloud_cover: cloud } }, meta, { loc: LOC, fetched: FETCHED });
    expect(p.hours).toBe(44);
    expect(p.temp[5]).toBe(h.temperature_2m![4]); // earlier neighbour
    expect(p.temp[6]).toBe(h.temperature_2m![7]); // later one is nearer
    expect(p.cloud[0]).toBe(h.cloud_cover![1]);
  });

  it("fillNearest prefers the earlier neighbour on a tie and gives up on an all-null series", () => {
    expect(fillNearest([1, null, 3], 3)).toEqual([1, 1, 3]);
    expect(fillNearest([null, null, 3, null], 4)).toEqual([3, 3, 3, 3]);
    expect(fillNearest([null, null], 2)).toBeNull();
    expect(fillNearest(undefined, 2)).toBeNull();
  });

  it("a response missing a sky series fails the transform (not as outside coverage)", () => {
    const { temperature_2m: _, ...rest } = forecast.hourly;
    expect(() => transform({ ...forecast, hourly: rest }, meta, { loc: LOC, fetched: FETCHED })).toThrow(/upstream sent no temperature_2m/);
  });
});

describe("nbmWindow", () => {
  it("from = start + hours h; whole 3-h blocks ending by start + 168 h", () => {
    expect(window.from).toBe(payload.start + 44 * HOUR);
    expect(window.blocks).toBe(41); // (168 − 44) / 3 = 41.33
    expect(lastHour(window)).toBe(window.from + 41 * 3 * HOUR - HOUR);
    expect(nbmWindow(0, 45)).toEqual({ from: 45 * HOUR, blocks: 41 });
    expect(nbmWindow(0, 48)).toEqual({ from: 48 * HOUR, blocks: 40 });
    expect(nbmWindow(0, 167)).toEqual({ from: 167 * HOUR, blocks: 0 });
    expect(nbmWindow(0, 200).blocks).toBe(0);
  });

  it("nbmURL asks for exactly that window in UTC", () => {
    const u = new URL(nbmURL({ lat: 48.09, lon: -122.76, cell: "sea", first: window.from, last: lastHour(window) }));
    expect(u.searchParams.get("start_hour")).toBe("2026-10-28T13:00");
    expect(u.searchParams.get("end_hour")).toBe("2026-11-02T15:00");
    expect(u.searchParams.get("models")).toBe("ncep_nbm_conus");
    expect(u.searchParams.get("timezone")).toBe("GMT");
    expect(u.searchParams.get("cell_selection")).toBe("sea");
  });
});

describe("aggregateNbm", () => {
  const ext = aggregateNbm(nbm, { window, meta: nbmMeta, fetched: FETCHED })!;

  it("on the live capture: 41 blocks from the HRRR horizon, contract fields and precision", () => {
    expect(ext.model).toBe("ncep_nbm_conus");
    expect(ext.run).toBe(nbmMeta.last_run_initialisation_time);
    expect(ext.fetched).toBe(FETCHED);
    expect(ext.step).toBe(3);
    expect(ext.from).toBe(payload.start + payload.hours * HOUR);
    expect(ext.blocks).toBe(41);
    for (const key of ["kn", "gust", "dir", "temp", "cloud", "precip"] as const) expect(ext[key]).toHaveLength(41);
    for (const v of [...ext.kn, ...ext.gust, ...ext.dir, ...ext.cloud]) expect(Number.isInteger(v)).toBe(true);
    for (const d of ext.dir) expect(d >= 0 && d < 360).toBe(true);
    for (let b = 0; b < 41; b++) expect(ext.gust[b]!).toBeGreaterThanOrEqual(ext.kn[b]!);
  });

  it("block 0 = hours 0..2: max kn and gust (rounded after), mean temp and cloud, max precip", () => {
    const h = nbm.hourly;
    const at = (xs: (number | null)[]) => [0, 1, 2].map((i) => xs[i] as number);
    expect(ext.kn[0]).toBe(Math.round(Math.max(...at(h.wind_speed_10m))));
    expect(ext.gust[0]).toBe(Math.round(Math.max(...at(h.wind_gusts_10m))));
    expect(ext.temp[0]).toBe(round1(at(h.temperature_2m!).reduce((a, b) => a + b) / 3));
    expect(ext.cloud[0]).toBe(Math.round(at(h.cloud_cover!).reduce((a, b) => a + b) / 3));
    expect(ext.precip[0]).toBe(round1(Math.max(...at(h.precipitation!))));
    expect(ext.dir[0]).toBe(170); // 170, 170, 170
  });

  it("starts at window.from even when the response has earlier hours", () => {
    const f = nbmHours(window.from - 6 * HOUR, 30, (i) => ({ wind_speed_10m: i }));
    const e = aggregateNbm(f, { window: { from: window.from, blocks: 4 }, meta: nbmMeta, fetched: 0 })!;
    expect(e.from).toBe(window.from);
    expect(e.kn).toEqual([8, 11, 14, 17]); // hours 6..8, 9..11, …
  });

  it("vector-mean direction across north: 350/10/0 → 0, 340/20/10 → 3, never ~180", () => {
    expect(vectorMeanDegrees([350, 10, 0])).toBe(0);
    expect(vectorMeanDegrees([340, 20, 10])).toBe(3);
    expect(vectorMeanDegrees([359, 359, 358])).toBe(359);
    expect(vectorMeanDegrees([90, 270], [3, 7])).toBe(270); // cancelling: strongest hour stands in
    const f = nbmHours(0, 3, (i) => ({ wind_direction_10m: [350, 5, 15][i]! }));
    expect(aggregateNbm(f, { window: { from: 0, blocks: 1 }, meta: nbmMeta, fetched: 0 })!.dir).toEqual([3]);
  });

  it("whole blocks only: a missing or null-wind hour ends the series at the block before it", () => {
    const short = nbmHours(0, 8); // 2 whole blocks + 2 hours
    expect(aggregateNbm(short, { window: { from: 0, blocks: 5 }, meta: nbmMeta, fetched: 0 })!.blocks).toBe(2);
    const gap = nbmHours(0, 15, (i) => (i === 7 ? { wind_gusts_10m: null } : {}));
    expect(aggregateNbm(gap, { window: { from: 0, blocks: 5 }, meta: nbmMeta, fetched: 0 })!.blocks).toBe(2);
    const capped = nbmHours(0, 30);
    expect(aggregateNbm(capped, { window: { from: 0, blocks: 4 }, meta: nbmMeta, fetched: 0 })!.blocks).toBe(4);
  });

  it("null when no whole block exists at from, or a sky series is absent", () => {
    expect(aggregateNbm(nbmHours(HOUR, 30), { window: { from: 0, blocks: 4 }, meta: nbmMeta, fetched: 0 })).toBeNull();
    const nulls = nbmHours(0, 9, () => ({ wind_speed_10m: null }));
    expect(aggregateNbm(nulls, { window: { from: 0, blocks: 3 }, meta: nbmMeta, fetched: 0 })).toBeNull();
    const f = nbmHours(0, 9);
    delete f.hourly.cloud_cover;
    expect(aggregateNbm(f, { window: { from: 0, blocks: 3 }, meta: nbmMeta, fetched: 0 })).toBeNull();
  });

  it("sky holes take the nearest hour, not zero", () => {
    const f = nbmHours(0, 6, (i) => (i === 3 ? { cloud_cover: null, temperature_2m: null } : { cloud_cover: 90, temperature_2m: 6 }));
    const e = aggregateNbm(f, { window: { from: 0, blocks: 2 }, meta: nbmMeta, fetched: 0 })!;
    expect(e.cloud).toEqual([90, 90]);
    expect(e.temp).toEqual([6, 6]);
  });
});

describe("trimExtended and enforceExtended", () => {
  const base = aggregateNbm(nbm, { window, meta: nbmMeta, fetched: FETCHED }) as Extended;

  it("same from: kept as is, capped to the new window's blocks", () => {
    expect(trimExtended(base, window)).toEqual(base);
    expect(trimExtended(base, { from: window.from, blocks: 30 })!.blocks).toBe(30);
  });

  it("from later by whole blocks: leading blocks dropped, run and fetched kept", () => {
    const t = trimExtended(base, { from: window.from + 6 * HOUR, blocks: 41 })!;
    expect(t.from).toBe(window.from + 6 * HOUR);
    expect(t.blocks).toBe(39);
    expect(t.gust).toEqual(base.gust.slice(2));
    expect(t.cloud).toEqual(base.cloud.slice(2));
    expect(t.run).toBe(base.run);
    expect(t.fetched).toBe(base.fetched);
  });

  it("from earlier, or later by a part block, or nothing left: null", () => {
    expect(trimExtended(base, { from: window.from - 3 * HOUR, blocks: 41 })).toBeNull();
    expect(trimExtended(base, { from: window.from + HOUR, blocks: 41 })).toBeNull();
    expect(trimExtended(base, { from: window.from + 41 * 3 * HOUR, blocks: 5 })).toBeNull();
    expect(trimExtended(null, window)).toBeNull();
  });

  it("enforceExtended drops an extended that doesn't start exactly at the horizon or overruns 168 h", () => {
    const good = { ...payload, extended: base };
    expect(enforceExtended(good).extended).toBe(base);
    expect(enforceExtended({ ...payload, extended: { ...base, from: base.from + 3 * HOUR } }).extended).toBeNull();
    expect(enforceExtended({ ...payload, extended: { ...base, blocks: 42, kn: [...base.kn, 1] } }).extended).toBeNull();
    expect(enforceExtended({ ...payload, extended: { ...base, kn: base.kn.slice(1) } }).extended).toBeNull();
  });
});

describe("the full §4.2a payload", () => {
  const full = { ...payload, extended: aggregateNbm(nbm, { window, meta: nbmMeta, fetched: FETCHED }) };
  const body = serializePayload(full);

  it("serialises in contract order: §4.2 keys, then temp, cloud, precip, extended", () => {
    expect(Object.keys(JSON.parse(body))).toEqual([
      "v", "loc", "model", "fetched", "run", "start", "hours", "kn", "gust", "dir", "peak", "summary", "sun",
      "temp", "cloud", "precip", "extended",
    ]);
    expect(body).toContain('"extended":{"model":"ncep_nbm_conus","run":');
    expect(JSON.parse(body)).toEqual(full);
    // Same object built in another order → same bytes.
    const { extended, ...rest } = full;
    expect(serializePayload({ extended, ...rest })).toBe(body);
  });

  it("is about 2.5 KB raw (§4.2a), under 3,000 bytes", () => {
    expect(new TextEncoder().encode(body).byteLength).toBeLessThan(3000);
  });
});
