import { describe, expect, it, vi } from "vitest";
import { CLIENT_HEADER, parseClient, recordUsage, usagePoint } from "../src/usage.js";

const req = (client?: string) =>
  new Request("https://example.test/v1/wind", { headers: client ? { [CLIENT_HEADER]: client } : {} });

describe("parseClient", () => {
  it("splits surface and version", () => {
    expect(parseClient("watch/0.1.0+1")).toEqual({ surface: "watch", version: "0.1.0+1" });
    expect(parseClient("Web/1")).toEqual({ surface: "web", version: "1" });
  });
  it("labels missing and unknown clients instead of dropping them", () => {
    expect(parseClient(null)).toEqual({ surface: "unknown", version: "" });
    expect(parseClient("curl/8.0")).toEqual({ surface: "other", version: "8.0" });
  });
  it("caps lengths", () => {
    expect(parseClient(`ios/${"9".repeat(200)}`).version.length).toBeLessThanOrEqual(32);
  });
});

describe("usagePoint", () => {
  it("records surface, version, location kind and status, nothing else", () => {
    expect(usagePoint(req("widget/0.1.0+2"), true, 304)).toEqual({
      indexes: ["widget"],
      blobs: ["widget", "0.1.0+2", "custom", "304", ""],
      doubles: [1],
    });
  });
});

describe("recordUsage", () => {
  it("is a no-op without a binding", () => {
    expect(() => recordUsage(undefined, req("ios/1"), false, 200)).not.toThrow();
  });
  it("writes one point", () => {
    const writeDataPoint = vi.fn();
    recordUsage({ writeDataPoint } as unknown as AnalyticsEngineDataset, req("ios/1"), false, 200);
    expect(writeDataPoint).toHaveBeenCalledTimes(1);
    expect(writeDataPoint.mock.calls[0]?.[0]?.blobs[2]).toBe("default");
  });
  it("never throws when the dataset does", () => {
    const writeDataPoint = vi.fn(() => {
      throw new Error("boom");
    });
    vi.spyOn(console, "error").mockImplementation(() => {});
    expect(() => recordUsage({ writeDataPoint } as unknown as AnalyticsEngineDataset, req(), false, 200)).not.toThrow();
  });
});
