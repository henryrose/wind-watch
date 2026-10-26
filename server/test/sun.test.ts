import { describe, expect, it } from "vitest";
import * as SunCalc from "suncalc";
import forecastFixture from "../../fixtures/openmeteo-forecast-2026-10-21.json";
import metaFixture from "../../fixtures/openmeteo-meta-2026-10-21.json";
import { localDate, localMidnight, sunDays, sunEvents } from "../src/sun.js";
import { transform } from "../src/transform.js";
import { serializePayload } from "../src/stableStringify.js";
import type { Location, OpenMeteoForecast, OpenMeteoMeta, SunDay } from "../src/types.js";
import { withSky } from "./helpers.js";

const forecast = withSky(forecastFixture as OpenMeteoForecast);
const meta = metaFixture as OpenMeteoMeta;

const PT = { lat: 48.0907, lon: -122.7773, tz: "America/Los_Angeles" };

const DEFAULT_LOC: Location = { name: "Port Townsend Bay", ...PT, cell: "sea" };

/** Unix seconds of a wall-clock time in a zone, found through our own localMidnight(). */
function localTime(tz: string, y: number, m: number, d: number, hh: number, mm: number): number {
  return localMidnight({ y, m, d }, tz) + hh * 3600 + mm * 60;
}

function minutesApart(a: number, b: number): number {
  return Math.abs(a - b) / 60;
}

function expectOrdered(day: SunDay): void {
  expect(day.dawn).toBeLessThan(day.rise);
  expect(day.rise).toBeLessThan(day.set);
  expect(day.set).toBeLessThan(day.dusk);
}

describe("sunEvents: Port Townsend Bay, 2026-10-21 PDT", () => {
  const midnight = localMidnight({ y: 2026, m: 10, d: 21 }, PT.tz);
  const day = sunEvents(PT.lat, PT.lon, midnight);

  it("local midnight is 07:00Z (PDT = UTC−7)", () => {
    expect(midnight).toBe(Date.UTC(2026, 9, 21, 7) / 1000);
  });

  it("rise within ±3 min of 07:40 PDT", () => {
    expect(minutesApart(day.rise, localTime(PT.tz, 2026, 10, 21, 7, 40))).toBeLessThanOrEqual(3);
  });
  it("set within ±3 min of 18:12 PDT", () => {
    expect(minutesApart(day.set, localTime(PT.tz, 2026, 10, 21, 18, 12))).toBeLessThanOrEqual(3);
  });
  it("civil dawn within ±3 min of 07:08 PDT", () => {
    expect(minutesApart(day.dawn, localTime(PT.tz, 2026, 10, 21, 7, 8))).toBeLessThanOrEqual(3);
  });
  it("civil dusk within ±3 min of 18:44 PDT", () => {
    expect(minutesApart(day.dusk, localTime(PT.tz, 2026, 10, 21, 18, 44))).toBeLessThanOrEqual(3);
  });
  it("values are integer unix seconds in order", () => {
    for (const v of Object.values(day)) expect(Number.isInteger(v)).toBe(true);
    expectOrdered(day);
  });
});

describe("sunEvents vs suncalc oracle", () => {
  const cases = [
    { name: "Honolulu 2026-06-21", lat: 21.3069, lon: -157.8583, tz: "Pacific/Honolulu", y: 2026, m: 6, d: 21 },
    { name: "Reykjavík 2026-03-01", lat: 64.1466, lon: -21.9426, tz: "Atlantic/Reykjavik", y: 2026, m: 3, d: 1 },
    { name: "Sydney 2026-12-21", lat: -33.8688, lon: 151.2093, tz: "Australia/Sydney", y: 2026, m: 12, d: 21 },
    { name: "Port Townsend 2026-10-21", ...PT, y: 2026, m: 10, d: 21 },
  ];

  for (const c of cases) {
    it(c.name, () => {
      const midnight = localMidnight({ y: c.y, m: c.m, d: c.d }, c.tz);
      const ours = sunEvents(c.lat, c.lon, midnight);
      // suncalc works on the solar day containing the given instant; local noon is safely inside it.
      const oracle = SunCalc.getTimes(new Date((midnight + 12 * 3600) * 1000), c.lat, c.lon);
      const o = (dt: Date | null): number => {
        if (dt === null) throw new Error("suncalc returned null for a non-polar case");
        return dt.getTime() / 1000;
      };
      expect(minutesApart(ours.rise, o(oracle.sunrise))).toBeLessThanOrEqual(2);
      expect(minutesApart(ours.set, o(oracle.sunset))).toBeLessThanOrEqual(2);
      expect(minutesApart(ours.dawn, o(oracle.dawn))).toBeLessThanOrEqual(2);
      expect(minutesApart(ours.dusk, o(oracle.dusk))).toBeLessThanOrEqual(2);
      expectOrdered(ours);
      // Every event falls inside that local day.
      for (const v of Object.values(ours)) {
        expect(v).toBeGreaterThanOrEqual(midnight);
        expect(v).toBeLessThan(midnight + 86400);
      }
    });
  }
});

describe("sunEvents polar edge cases do not crash", () => {
  it("midnight sun: Longyearbyen 2026-06-21 gives a 24 h day", () => {
    const tz = "Arctic/Longyearbyen";
    const midnight = localMidnight({ y: 2026, m: 6, d: 21 }, tz);
    const day = sunEvents(78.2232, 15.6267, midnight);
    for (const v of Object.values(day)) expect(Number.isFinite(v)).toBe(true);
    expect(day.set - day.rise).toBe(86400);
    expect(day.dawn).toBeLessThanOrEqual(day.rise);
    expect(day.dusk).toBeGreaterThanOrEqual(day.set);
  });
  it("polar night: Longyearbyen 2026-12-21 collapses rise/set onto noon", () => {
    const tz = "Arctic/Longyearbyen";
    const midnight = localMidnight({ y: 2026, m: 12, d: 21 }, tz);
    const day = sunEvents(78.2232, 15.6267, midnight);
    for (const v of Object.values(day)) expect(Number.isFinite(v)).toBe(true);
    expect(day.rise).toBe(day.set);
    expect(day.dawn).toBeLessThanOrEqual(day.rise);
    expect(day.dusk).toBeGreaterThanOrEqual(day.set);
    // Solar noon: 12:00 − 15.6°/15 h − EqT(≈2 min) ≈ 10:55Z ≈ 11:55 CET.
    const solarNoon = SunCalc.getTimes(new Date((midnight + 12 * 3600) * 1000), 78.2232, 15.6267).solarNoon;
    expect(minutesApart(day.rise, solarNoon.getTime() / 1000)).toBeLessThan(2);
    expect(minutesApart(day.rise, midnight + 11 * 3600 + 55 * 60)).toBeLessThan(10);
  });
});

describe("local civil days via Intl", () => {
  it("localDate and localMidnight agree across a DST change (PT, 2026-11-01)", () => {
    const tz = PT.tz;
    const before = localMidnight({ y: 2026, m: 11, d: 1 }, tz); // still PDT at 00:00
    const after = localMidnight({ y: 2026, m: 11, d: 2 }, tz); // PST
    expect(after - before).toBe(25 * 3600);
    expect(localDate(before, tz)).toEqual({ y: 2026, m: 11, d: 1 });
    expect(localDate(before - 1, tz)).toEqual({ y: 2026, m: 10, d: 31 });
    expect(localDate(after, tz)).toEqual({ y: 2026, m: 11, d: 2 });
  });

  it("sunDays covers exactly the local days touched by [start, last hour]", () => {
    // 18Z Oct 21 = 11:00 PDT Oct 21; 43 hours → last hour 12Z Oct 23 = 05:00 PDT Oct 23.
    const days = sunDays({ ...PT, start: 1792605600, hours: 43 });
    expect(days).toHaveLength(3);
    expect(localDate(days[0]!.rise, PT.tz)).toEqual({ y: 2026, m: 10, d: 21 });
    expect(localDate(days[1]!.rise, PT.tz)).toEqual({ y: 2026, m: 10, d: 22 });
    expect(localDate(days[2]!.rise, PT.tz)).toEqual({ y: 2026, m: 10, d: 23 });
  });

  it("a single hour yields one day; zero hours yields none", () => {
    expect(sunDays({ ...PT, start: 1792605600, hours: 1 })).toHaveLength(1);
    expect(sunDays({ ...PT, start: 1792605600, hours: 0 })).toHaveLength(0);
  });

  it("the last hour's trailing minutes do not pull in an extra day", () => {
    // 23:00 PDT Oct 21 = 06:00Z Oct 22 as the single hour.
    const days = sunDays({ ...PT, start: Date.UTC(2026, 9, 22, 6) / 1000, hours: 1 });
    expect(days).toHaveLength(1);
    expect(localDate(days[0]!.rise, PT.tz)).toEqual({ y: 2026, m: 10, d: 21 });
  });
});

describe("transform populates sun", () => {
  const payload = transform(forecast, meta, { loc: DEFAULT_LOC, fetched: 1792606200 });

  it("yields exactly local days 2026-10-21, -22, -23 in order", () => {
    expect(payload.sun).toHaveLength(3);
    const dates = payload.sun.map((d) => localDate(d.rise, PT.tz));
    expect(dates).toEqual([
      { y: 2026, m: 10, d: 21 },
      { y: 2026, m: 10, d: 22 },
      { y: 2026, m: 10, d: 23 },
    ]);
    for (let i = 1; i < payload.sun.length; i++) {
      expect(payload.sun[i]!.rise).toBeGreaterThan(payload.sun[i - 1]!.rise);
    }
  });

  it("every entry satisfies dawn < rise < set < dusk with integer seconds", () => {
    for (const day of payload.sun) {
      expectOrdered(day);
      for (const v of Object.values(day)) expect(Number.isInteger(v)).toBe(true);
    }
  });

  it("matches the reference payload's hand-built sun times within 3 min", () => {
    // fixtures/payload-reference.json sun block (HANDOFF §10 approximations).
    const reference: SunDay[] = [
      { dawn: 1792591680, rise: 1792593600, set: 1792631520, dusk: 1792633440 },
      { dawn: 1792678140, rise: 1792680060, set: 1792717800, dusk: 1792719720 },
      { dawn: 1792764600, rise: 1792766580, set: 1792804080, dusk: 1792806000 },
    ];
    for (const [i, ref] of reference.entries()) {
      const ours = payload.sun[i]!;
      for (const k of ["dawn", "rise", "set", "dusk"] as const) {
        expect(minutesApart(ours[k], ref[k])).toBeLessThanOrEqual(3);
      }
    }
  });

  it("serialised payload with sun populated stays under 2,000 bytes (no NBM)", () => {
    const bytes = new TextEncoder().encode(serializePayload(payload)).byteLength;
    expect(bytes).toBeLessThan(2000);
  });
});
