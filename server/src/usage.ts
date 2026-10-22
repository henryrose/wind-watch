// Usage counting: one Workers Analytics Engine data point per /v1/wind request.
//
// Clients identify themselves with `X-WW-Client: <surface>/<version>`, e.g.
// `ios/0.1.0+1`, `watch/0.1.0+1`, `widget/0.1.0+1`, `web/1`. Nothing about the
// person is recorded: no IP, no coordinates, only the surface, version, whether
// the default or a custom location was asked for, the response status and the
// Cloudflare-reported country.
//
// Schema (keep in sync with scripts/usage.mjs):
//   index1  surface
//   blob1   surface   blob2 version   blob3 location ("default" | "custom")
//   blob4   status ("200" | "304" | "4xx/5xx code")   blob5 country
//   double1 1 (one request)

export const CLIENT_HEADER = "X-WW-Client";

const SURFACES = new Set(["ios", "watch", "widget", "web"]);

export interface UsagePoint {
  indexes: [string];
  blobs: [string, string, string, string, string];
  doubles: [number];
}

/** Splits `surface/version`; unknown or missing surfaces become "other" so a typo never drops a count. */
export function parseClient(raw: string | null): { surface: string; version: string } {
  if (!raw) return { surface: "unknown", version: "" };
  const [s, ...rest] = raw.trim().slice(0, 64).split("/");
  const surface = (s ?? "").toLowerCase();
  return { surface: SURFACES.has(surface) ? surface : "other", version: rest.join("/").slice(0, 32) };
}

export function usagePoint(request: Request, custom: boolean, status: number): UsagePoint {
  const { surface, version } = parseClient(request.headers.get(CLIENT_HEADER));
  const country = String((request as { cf?: { country?: unknown } }).cf?.country ?? "");
  return {
    indexes: [surface],
    blobs: [surface, version, custom ? "custom" : "default", String(status), country],
    doubles: [1],
  };
}

/** Never throws: counting must not break serving. A missing binding (tests, local dev) is a no-op. */
export function recordUsage(dataset: AnalyticsEngineDataset | undefined, request: Request, custom: boolean, status: number): void {
  if (!dataset) return;
  try {
    dataset.writeDataPoint(usagePoint(request, custom, status));
  } catch (e) {
    console.error(`usage: ${e instanceof Error ? e.message : String(e)}`);
  }
}
