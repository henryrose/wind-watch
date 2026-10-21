// Worker entry point. B1 scaffold only: the real `fetch` (GET /v1/wind, ETag,
// custom location) and `scheduled` (cron bake into KV) handlers are task B4.
// This stub exists so `main` in wrangler.toml resolves for `wrangler dev` and
// the vitest Workers pool.

export interface Env {
  WIND: KVNamespace;
}

export default {
  async fetch(_request: Request, _env: Env, _ctx: ExecutionContext): Promise<Response> {
    return new Response(JSON.stringify({ error: "no_data" }), {
      status: 503,
      headers: { "Content-Type": "application/json; charset=utf-8" },
    });
  },

  async scheduled(_controller: ScheduledController, _env: Env, _ctx: ExecutionContext): Promise<void> {
    // B4: fetch meta.json, compare availability time, bake payload into KV.
  },
} satisfies ExportedHandler<Env>;
