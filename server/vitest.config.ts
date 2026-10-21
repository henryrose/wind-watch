import { defineConfig } from "vitest/config";
import { cloudflareTest } from "@cloudflare/vitest-pool-workers";

// The Workers pool runs tests inside workerd with the bindings from wrangler.toml
// (KV `WIND`, cron). B1's tests are pure unit tests and would run under plain
// node too; the pool is configured now so B4's handler tests can use
// `env.WIND`, `SELF` and `fetchMock` from "cloudflare:test" without touching
// this file. Miniflare treats the KV id placeholder as a local namespace name.
export default defineConfig({
  plugins: [cloudflareTest({ wrangler: { configPath: "./wrangler.toml" } })],
  test: {
    include: ["test/**/*.test.ts"],
  },
});
