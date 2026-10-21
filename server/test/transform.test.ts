import { describe, expect, it } from "vitest";
import forecastFixture from "../../fixtures/openmeteo-forecast-2026-10-21.json";
import metaFixture from "../../fixtures/openmeteo-meta-2026-10-21.json";
import { countNonNullHours, inferExtendedRun, normaliseDegrees, transform } from "../src/transform.js";
import { serializePayload, stableStringify } from "../src/stableStringify.js";
import type { Location, OpenMeteoForecast, OpenMeteoMeta, Payload } from "../src/types.js";

const forecast = forecastFixture as OpenMeteoForecast;
const meta = metaFixture as OpenMeteoMeta;

const HOUR = 3600;
const SIX_HOURS = 6 * HOUR;

const DEFAULT_LOC: Location = {
  name: "Port Townsend Bay",
  lat: 48.0907,
  lon: -122.7773,
  tz: "America/Los_Angeles",
  cell: "sea",
};

// A fetch time a little after the fixture's first hour; any value works, it is
// passed through untouched.
const FETCHED = forecast.hourly.time[0]! + 600;

function isInt(n: unknown): n is number {
  return typeof n === "number" && Number.isInteger(n);
}

/** Build a synthetic 50-hour forecast; `nullFrom` makes every index >= nullFrom null. */
function synthetic(nullFrom?: number): OpenMeteoForecast {
  const n = 50;
  const start = 1792605600;
  const time: number[] = [];
  const speed: (number | null)[] = [];
  const dir: (number | null)[] = [];
  const gust: (number | null)[] = [];
  for (let i = 0; i < n; i++) {
    time.push(start + i * HOUR);
    const dead = nullFrom !== undefined && i >= nullFrom;
    speed.push(dead ? null : 5 + (i % 7) * 1.3);
    dir.push(dead ? null : (i * 37) % 360);
    gust.push(dead ? null : 8 + (i % 11) * 1.7);
  }
  return {
    latitude: 48.09075,
    longitude: -122.777275,
    utc_offset_seconds: 0,
    timezone: "GMT",
    hourly: { time, wind_speed_10m: speed, wind_direction_10m: dir, wind_gusts_10m: gust },
  };
}

describe("transform on the 2026-10-21 fixture", () => {
  const payload = transform(forecast, meta, { loc: DEFAULT_LOC, fetched: FETCHED });

  it("has the fixed header fields", () => {
    expect(payload.v).toBe(1);
    expect(payload.model).toBe("ncep_hrrr_conus");
    expect(payload.loc).toEqual(DEFAULT_LOC);
    expect(payload.fetched).toBe(FETCHED);
    expect(payload.summary).toBe("");
    // sun is populated by B2; its content is covered in sun.test.ts.
    expect(payload.sun).toHaveLength(3);
  });

  it("hours equals the number of non-null entries in the fixture (43)", () => {
    const h = forecast.hourly;
    const firstNull = h.wind_speed_10m.findIndex((v) => v === null);
    const expected = firstNull === -1 ? h.wind_speed_10m.length : firstNull;
    expect(payload.hours).toBe(expected);
    expect(expected).toBe(43);
    // All three arrays agree on where the data ends.
    expect(h.wind_gusts_10m.findIndex((v) => v === null)).toBe(firstNull);
    expect(h.wind_direction_10m.findIndex((v) => v === null)).toBe(firstNull);
  });

  it("arrays have length == hours and every value is an integer", () => {
    for (const key of ["kn", "gust", "dir"] as const) {
      expect(payload[key]).toHaveLength(payload.hours);
      for (const v of payload[key]) expect(isInt(v)).toBe(true);
    }
    for (const d of payload.dir) {
      expect(d).toBeGreaterThanOrEqual(0);
      expect(d).toBeLessThan(360);
    }
    for (const [i, v] of payload.kn.entries()) {
      expect(v).toBe(Math.round(forecast.hourly.wind_speed_10m[i] as number));
    }
    for (const [i, v] of payload.gust.entries()) {
      expect(v).toBe(Math.round(forecast.hourly.wind_gusts_10m[i] as number));
    }
    for (const [i, v] of payload.dir.entries()) {
      expect(v).toBe(Math.round(forecast.hourly.wind_direction_10m[i] as number));
    }
  });

  it("start is the fixture's first time and is on an hour boundary", () => {
    expect(payload.start).toBe(forecast.hourly.time[0]);
    expect(payload.start % HOUR).toBe(0);
  });

  it("peak is the max rounded gust, first occurrence, with its hour timestamp", () => {
    const max = Math.max(...payload.gust);
    const idx = payload.gust.indexOf(max);
    expect(payload.peak.gust).toBe(max);
    expect(payload.peak.at).toBe(payload.start + idx * HOUR);
    expect(payload.peak.at).toBe(forecast.hourly.time[idx]);
    // The fixture has a 24.1 / 24.1 / 23.9 plateau; first occurrence wins.
    expect(max).toBe(24);
    expect(idx).toBe(13);
  });

  it("run.latest is the meta init time", () => {
    expect(payload.run.latest).toBe(meta.last_run_initialisation_time);
    expect(payload.run.latest % HOUR).toBe(0);
  });

  it("run.extended is null or a 6-hourly UTC init before run.latest", () => {
    const ext = payload.run.extended;
    if (ext !== null) {
      expect(isInt(ext)).toBe(true);
      expect(ext % SIX_HOURS).toBe(0);
      expect(ext).toBeLessThan(payload.run.latest);
    }
    // For this capture specifically: latest = 16Z, last hour = 12Z two days on,
    // so the long run is 12Z the same day.
    expect(ext).toBe(forecast.hourly.time[42]! - 48 * HOUR);
    expect(ext).toBe(1792584000);
  });

  it("serialises under 1,200 bytes raw", () => {
    const body = serializePayload(payload);
    expect(new TextEncoder().encode(body).byteLength).toBeLessThan(1200);
    // Round-trips and matches the plain JSON.stringify of the transform output.
    expect(JSON.parse(body)).toEqual(payload);
    expect(body).toBe(JSON.stringify(payload));
  });
});

describe("transform on synthetic forecasts", () => {
  it("truncates at the first null (index 10 → 10 hours)", () => {
    const p = transform(synthetic(10), meta, { loc: DEFAULT_LOC, fetched: FETCHED });
    expect(p.hours).toBe(10);
    expect(p.kn).toHaveLength(10);
    expect(p.gust).toHaveLength(10);
    expect(p.dir).toHaveLength(10);
  });

  it("returns all 50 hours when nothing is null", () => {
    const p = transform(synthetic(), meta, { loc: DEFAULT_LOC, fetched: FETCHED });
    expect(p.hours).toBe(50);
    expect(p.kn).toHaveLength(50);
    expect(p.peak.at).toBe(p.start + p.gust.indexOf(Math.max(...p.gust)) * HOUR);
  });

  it("a null in any one array ends the forecast", () => {
    const f = synthetic();
    f.hourly.wind_direction_10m[7] = null;
    expect(countNonNullHours(f.hourly)).toBe(7);
    const g = synthetic();
    g.hourly.wind_gusts_10m[3] = null;
    expect(countNonNullHours(g.hourly)).toBe(3);
  });

  it("normalises direction 360 → 0", () => {
    const f = synthetic();
    f.hourly.wind_direction_10m[0] = 360;
    f.hourly.wind_direction_10m[1] = 359.6;
    const p = transform(f, meta, { loc: DEFAULT_LOC, fetched: FETCHED });
    expect(p.dir[0]).toBe(0);
    expect(p.dir[1]).toBe(0);
    expect(normaliseDegrees(360)).toBe(0);
    expect(normaliseDegrees(-10)).toBe(350);
    expect(normaliseDegrees(725)).toBe(5);
  });

  it("throws on an empty or all-null forecast", () => {
    expect(() => transform(synthetic(0), meta, { loc: DEFAULT_LOC, fetched: FETCHED })).toThrow();
  });
});

describe("inferExtendedRun", () => {
  const day = 1792540800; // 2026-10-21 00:00Z
  it("yields lastHour − 48 h when that is a 6-hourly init before latest", () => {
    // latest 16Z, last hour 12Z +2 days → 12Z today.
    expect(inferExtendedRun(day + 60 * HOUR, day + 16 * HOUR)).toBe(day + 12 * HOUR);
  });
  it("is null when the candidate is not on a 6-hour boundary", () => {
    // last hour 13Z +2 days → candidate 13Z: not a long-run init.
    expect(inferExtendedRun(day + 61 * HOUR, day + 16 * HOUR)).toBeNull();
  });
  it("is null when the candidate equals latest (newest run is the long run)", () => {
    expect(inferExtendedRun(day + 60 * HOUR, day + 12 * HOUR)).toBeNull();
  });
  it("is null when the candidate would be after latest", () => {
    expect(inferExtendedRun(day + 66 * HOUR, day + 16 * HOUR)).toBeNull();
  });
});

describe("stableStringify", () => {
  it("serialises in §4.2 key order regardless of construction order", () => {
    const p = transform(forecast, meta, { loc: DEFAULT_LOC, fetched: FETCHED });
    // Rebuild the object with keys in a scrambled order.
    const scrambled = {
      sun: p.sun,
      summary: p.summary,
      peak: { at: p.peak.at, gust: p.peak.gust },
      dir: p.dir,
      gust: p.gust,
      kn: p.kn,
      hours: p.hours,
      start: p.start,
      run: { extended: p.run.extended, latest: p.run.latest },
      fetched: p.fetched,
      model: p.model,
      loc: { cell: p.loc.cell, tz: p.loc.tz, lon: p.loc.lon, lat: p.loc.lat, name: p.loc.name },
      v: p.v,
    } as Payload;
    expect(serializePayload(scrambled)).toBe(serializePayload(p));
    expect(serializePayload(p).startsWith('{"v":1,"loc":{"name":')).toBe(true);
  });

  it("emits compact JSON, skips undefined, keeps null", () => {
    expect(stableStringify({ a: 1, b: undefined, c: null, d: [1, "x", true] })).toBe(
      '{"a":1,"c":null,"d":[1,"x",true]}',
    );
    expect(() => stableStringify({ a: Number.NaN })).toThrow();
  });
});
