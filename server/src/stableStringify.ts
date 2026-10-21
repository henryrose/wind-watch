// Deterministic JSON serialisation.
//
// The ETag is a hash of the body, so the same logical payload must always
// produce byte-identical JSON. JSON.stringify already preserves insertion order,
// but that makes the wire order depend on how the object happened to be built.
// `serializePayload` rebuilds the object in the §4.2 declared order first, so
// any Payload (hand-built in a test, decoded from KV, produced by transform)
// serialises identically. No whitespace, no undefined, integers stay integers.

import type { Payload } from "./types.js";

type Json = null | boolean | number | string | Json[] | { [k: string]: Json };

/** Serialise with object keys in their insertion order, no whitespace. */
export function stableStringify(value: unknown): string {
  return stringifyValue(value as Json);
}

function stringifyValue(value: Json): string {
  if (value === null) return "null";
  switch (typeof value) {
    case "boolean":
      return value ? "true" : "false";
    case "number":
      if (!Number.isFinite(value)) throw new Error(`stableStringify: non-finite number ${value}`);
      return String(value);
    case "string":
      return JSON.stringify(value);
    case "object": {
      if (Array.isArray(value)) return `[${value.map(stringifyValue).join(",")}]`;
      const parts: string[] = [];
      for (const key of Object.keys(value)) {
        const v = value[key];
        if (v === undefined) continue;
        parts.push(`${JSON.stringify(key)}:${stringifyValue(v)}`);
      }
      return `{${parts.join(",")}}`;
    }
    default:
      throw new Error(`stableStringify: unsupported value of type ${typeof value}`);
  }
}

/** Serialise a Payload in the DESIGN §4.2 key order regardless of how it was built. */
export function serializePayload(p: Payload): string {
  const ordered = {
    v: p.v,
    loc: { name: p.loc.name, lat: p.loc.lat, lon: p.loc.lon, tz: p.loc.tz, cell: p.loc.cell },
    model: p.model,
    fetched: p.fetched,
    run: { latest: p.run.latest, extended: p.run.extended },
    start: p.start,
    hours: p.hours,
    kn: p.kn,
    gust: p.gust,
    dir: p.dir,
    peak: { gust: p.peak.gust, at: p.peak.at },
    summary: p.summary,
    sun: p.sun.map((d) => ({ dawn: d.dawn, rise: d.rise, set: d.set, dusk: d.dusk })),
  };
  return stableStringify(ordered);
}
