// Shared test helpers.

import type { OpenMeteoForecast } from "../src/types.js";

/**
 * The 21 Oct fixture predates §4.2a and has no sky/temperature series; the transform
 * now refuses a response without them. This adds flat ones (12 °C, 50 % cloud, no rain)
 * that go null exactly where the wind does, so the 21 Oct tests keep testing what they
 * always did. The 26 Oct fixture has the real series.
 */
export function withSky(f: OpenMeteoForecast): OpenMeteoForecast {
  const h = f.hourly;
  const like = (v: number) => h.wind_speed_10m.map((w) => (w === null ? null : v));
  return { ...f, hourly: { ...h, temperature_2m: like(12), cloud_cover: like(50), precipitation: like(0) } };
}
