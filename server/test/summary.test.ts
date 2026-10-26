import { describe, expect, it } from "vitest";
import referenceFixture from "../../fixtures/payload-reference.json";
import forecastFixture from "../../fixtures/openmeteo-forecast-2026-10-21.json";
import metaFixture from "../../fixtures/openmeteo-meta-2026-10-21.json";
import {
  bandWord,
  compass8,
  composeSummary,
  directionSpread,
  meanDirection,
  period,
  summary,
  summaryParts,
} from "../src/summary.js";
import { transform } from "../src/transform.js";
import { serializePayload } from "../src/stableStringify.js";
import type { Location, OpenMeteoForecast, OpenMeteoMeta, Payload } from "../src/types.js";
import { withSky } from "./helpers.js";

const reference = referenceFixture as Payload;
const forecast = withSky(forecastFixture as OpenMeteoForecast);
const meta = metaFixture as OpenMeteoMeta;

const TZ = "America/Los_Angeles";
const LOC: Location = { name: "Port Townsend Bay", lat: 48.0907, lon: -122.7773, tz: TZ, cell: "sea" };
/** 2026-10-21 18:00Z = 11:00 PDT Wednesday (the live fixture's first hour). */
const WED_11 = 1792605600;
const HOUR = 3600;

/** Synthetic payload from per-hour arrays; peak derived like transform does. */
function synthetic(opts: { start?: number; kn: number[]; gust: number[]; dir: number[] }): Payload {
  const start = opts.start ?? WED_11;
  const hours = opts.kn.length;
  let peakIdx = 0;
  for (let i = 1; i < hours; i++) if ((opts.gust[i] as number) > (opts.gust[peakIdx] as number)) peakIdx = i;
  return {
    v: 1,
    loc: LOC,
    model: "ncep_hrrr_conus",
    fetched: start,
    run: { latest: start - 2 * HOUR, extended: null },
    start,
    hours,
    kn: opts.kn,
    gust: opts.gust,
    dir: opts.dir,
    peak: { gust: opts.gust[peakIdx] as number, at: start + peakIdx * HOUR },
    summary: "",
    sun: [],
    temp: fill(hours, 12),
    cloud: fill(hours, 50),
    precip: fill(hours, 0),
    extended: null,
  };
}

const fill = (n: number, v: number) => Array.from({ length: n }, () => v);

function expectWellFormed(s: string): void {
  expect(s.length).toBeGreaterThan(0);
  expect(s.length).toBeLessThanOrEqual(110);
  expect(s).toMatch(/^[A-Z]/);
  expect(s.endsWith(".")).toBe(true);
  expect(s).not.toMatch(/\d\.\d/); // no decimals
  expect(s).not.toMatch(/HRRR|model|run|Z\b/); // no model jargon
}

describe("summary: reference payload", () => {
  const s = summary(reference);

  it("is well-formed and ≤ 110 chars", () => {
    expectWellFormed(s);
  });

  it('mentions "building to 15 kn W" and "gusts to 25"', () => {
    expect(s).toContain("building to 15 kn W");
    expect(s).toContain("gusts to 25");
  });

  it("reads as expected end to end", () => {
    // 09:00 PDT Wed start, 3 kn now, 15 kn W and 25 kn gusts both at hour 15 (midnight).
    expect(s).toBe("Calm this morning, building to 15 kn W around midnight, gusts to 25.");
  });
});

describe("summary: live forecast fixture via transform()", () => {
  const p = transform(forecast, meta, { loc: LOC, fetched: WED_11 + 600 });

  it("is non-empty, ≤ 110 chars and stored on the payload", () => {
    expectWellFormed(p.summary);
    expect(p.summary).toBe(summary(p));
  });

  it("serialised payload with summary and sun stays under 2,000 bytes (no NBM)", () => {
    expect(new TextEncoder().encode(serializePayload(p)).byteLength).toBeLessThan(2000);
  });
});

describe("summary: synthetic payloads", () => {
  it("flat calm for 24 hours → 'Calm through tomorrow.'", () => {
    const p = synthetic({ kn: fill(24, 2), gust: fill(24, 3), dir: fill(24, 200) });
    expect(summary(p)).toBe("Calm through tomorrow.");
  });

  it("flat calm for 43 hours (ends Friday 05:00) → 'Calm through Friday.'", () => {
    const p = synthetic({ kn: fill(43, 2), gust: fill(43, 3), dir: fill(43, 200) });
    expect(summary(p)).toBe("Calm through Friday.");
  });

  it("steady 20 kn S → 'Fresh S', no building", () => {
    const p = synthetic({ kn: fill(30, 20), gust: fill(30, 24), dir: fill(30, 180) });
    const s = summary(p);
    expectWellFormed(s);
    expect(s).toContain("Fresh S");
    expect(s).not.toContain("building");
    expect(s).toBe("Fresh S this morning. Gusts to 24 this morning.");
  });

  it("steady 20 kn S with small gusts → no gust clause at all", () => {
    const p = synthetic({ kn: fill(30, 20), gust: fill(30, 14), dir: fill(30, 180) });
    expect(summary(p)).toBe("Fresh S this morning.");
  });

  it("light and variable when the first three hours spread more than 90°", () => {
    // 3 kn now with directions all over the place, 7 kn later (not enough to "build").
    const p = synthetic({ kn: [3, 3, 3, ...fill(9, 7)], gust: fill(12, 9), dir: [10, 200, 100, ...fill(9, 100)] });
    expect(summary(p)).toBe("Light and variable this morning.");
  });

  it("whole-forecast calm wins over variable directions", () => {
    const p = synthetic({ kn: fill(12, 3), gust: fill(12, 5), dir: [10, 200, 100, ...fill(9, 100)] });
    expect(summary(p)).toBe("Calm through today.");
  });

  it("building, gusts and easing all appear when the pattern calls for them", () => {
    // Wed 11:00 start; 5 kn until a 27 kn SW burst over hours 30–35 (Thu 17:00–22:00),
    // gust peak 45 at hour 36 (Thu 23:00), then 5 kn to the end.
    const kn = [...fill(30, 5), ...fill(6, 27), ...fill(14, 5)];
    const gust = [...fill(36, 8), 45, ...fill(13, 8)];
    const dir = [...fill(30, 300), ...fill(6, 225), ...fill(14, 300)];
    const parts = summaryParts(synthetic({ kn, gust, dir }));
    expect(parts.now).toBe("Light NW this morning");
    expect(parts.building).toBe("building to 27 kn SW by tomorrow evening");
    expect(parts.gusts).toBe("gusts to 45 tomorrow night");
    expect(parts.easing).toBe("Easing tomorrow night");
    expect(composeSummary(parts, Infinity)).toBe(
      "Light NW this morning, building to 27 kn SW by tomorrow evening, gusts to 45 tomorrow night. Easing tomorrow night.",
    );
  });

  it("trims whole clauses, never mid-word, to fit 110 chars", () => {
    // Same shape, but a variable start makes the untrimmed text exceed 110 chars.
    const kn = [...fill(30, 5), ...fill(6, 27), ...fill(14, 5)];
    const gust = [...fill(36, 8), 45, ...fill(13, 8)];
    const dir = [10, 200, 100, ...fill(27, 300), ...fill(6, 225), ...fill(14, 300)];
    const p = synthetic({ kn, gust, dir });
    const parts = summaryParts(p);
    const full = composeSummary(parts, Infinity);
    expect(full.length).toBeGreaterThan(110);
    const s = summary(p);
    expectWellFormed(s);
    expect(s).toBe("Light and variable this morning, building to 27 kn SW by tomorrow evening, gusts to 45 tomorrow night.");
    // Every word of the trimmed text is a word of the full text, in order.
    const words = (t: string) => t.replace(/[.,]/g, "").split(/\s+/);
    const fw = words(full);
    let j = 0;
    for (const w of words(s)) {
      j = fw.indexOf(w, j);
      expect(j).toBeGreaterThanOrEqual(0);
      j++;
    }
  });

  it("drops gusts and then building if the first sentence alone is too long", () => {
    const parts = summaryParts(
      synthetic({
        kn: [...fill(30, 5), ...fill(6, 27), ...fill(14, 5)],
        gust: [...fill(36, 8), 45, ...fill(13, 8)],
        dir: [10, 200, 100, ...fill(27, 300), ...fill(6, 225), ...fill(14, 300)],
      }),
    );
    expect(composeSummary(parts, 80)).toBe("Light and variable this morning, building to 27 kn SW by tomorrow evening.");
    expect(composeSummary(parts, 40)).toBe("Light and variable this morning.");
  });

  it("gust period is omitted when it equals the building period", () => {
    const kn = [...fill(12, 5), ...fill(6, 15), ...fill(6, 5)];
    // Building window hours 12–17 (23:00 Wed – 04:00 Thu), max 15 first at hour 12 = "around midnight";
    // gust peak at hour 13 = 00:00 Thu, also "around midnight".
    const gust = [...fill(12, 8), 18, 22, ...fill(4, 18), ...fill(6, 8)];
    const dir = fill(24, 270);
    const parts = summaryParts(synthetic({ kn, gust, dir }));
    expect(parts.building).toBe("building to 15 kn W around midnight");
    expect(parts.gusts).toBe("gusts to 22");
  });
});

describe("summary helpers", () => {
  it("band words", () => {
    expect([2, 3, 4, 10, 11, 16, 17, 21, 22, 27, 28, 40].map(bandWord)).toEqual([
      "calm", "calm", "light", "light", "moderate", "moderate", "fresh", "fresh", "strong", "strong", "gale", "gale",
    ]);
  });

  it("8-point compass", () => {
    expect([0, 22, 23, 45, 90, 135, 180, 225, 270, 283, 315, 338, 359].map(compass8)).toEqual([
      "N", "N", "NE", "NE", "E", "SE", "S", "SW", "W", "W", "NW", "N", "N",
    ]);
  });

  it("vector-mean direction wraps across north", () => {
    expect(Math.round(meanDirection([350, 10]))).toBe(0);
    expect(Math.round(meanDirection([80, 100]))).toBe(90);
    expect(compass8(meanDirection([290, 289, 313]))).toBe("NW");
  });

  it("direction spread", () => {
    expect(directionSpread([290, 289, 313])).toBe(24);
    expect(directionSpread([350, 10])).toBe(20);
    expect(directionSpread([10, 200, 100])).toBe(170);
  });

  it("periods relative to a Wednesday first day", () => {
    const firstDay = { y: 2026, m: 10, d: 21 };
    const at = (dayOffset: number, h: number) => Date.UTC(2026, 9, 21 + dayOffset, h + 7) / 1000; // PDT = UTC−7
    const p = (d: number, h: number) => period(at(d, h), TZ, firstDay);
    expect(p(0, 9)).toEqual({ text: "this morning", by: true });
    expect(p(0, 14)).toEqual({ text: "this afternoon", by: true });
    expect(p(0, 19)).toEqual({ text: "this evening", by: true });
    expect(p(0, 23)).toEqual({ text: "around midnight", by: false });
    expect(p(1, 0)).toEqual({ text: "around midnight", by: false });
    expect(p(1, 3)).toEqual({ text: "overnight", by: false });
    expect(p(1, 5)).toEqual({ text: "dawn", by: true });
    expect(p(1, 6)).toEqual({ text: "dawn", by: true });
    expect(p(1, 9)).toEqual({ text: "tomorrow morning", by: true });
    expect(p(1, 15)).toEqual({ text: "tomorrow afternoon", by: true });
    expect(p(1, 23)).toEqual({ text: "tomorrow night", by: false });
    expect(p(2, 2)).toEqual({ text: "tomorrow night", by: false });
    expect(p(2, 5)).toEqual({ text: "Friday morning", by: true });
    expect(p(2, 13)).toEqual({ text: "Friday afternoon", by: true });
    expect(p(2, 23)).toEqual({ text: "Friday night", by: false });
    expect(p(3, 1)).toEqual({ text: "Friday night", by: false });
  });
});
