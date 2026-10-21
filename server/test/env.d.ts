// Types for the Workers test pool: `cloudflare:test` module and the bindings
// `env` carries (mirrors wrangler.toml).

/// <reference types="@cloudflare/vitest-pool-workers/types" />

declare namespace Cloudflare {
  interface Env {
    WIND: KVNamespace;
  }
}
