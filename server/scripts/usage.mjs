#!/usr/bin/env node
// Prints Wind Watch request counts from the `wind_watch_usage` Analytics Engine dataset
// (written by src/usage.ts). Usage: `pnpm usage [days]` (default 14).
//
// Auth: CLOUDFLARE_API_TOKEN (needs "Account Analytics: Read") if set, otherwise the token
// `wrangler login` stored. Account: CLOUDFLARE_ACCOUNT_ID, otherwise the token's only account.

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const DATASET = "wind_watch_usage";
const API = "https://api.cloudflare.com/client/v4";
const days = Math.max(1, Math.min(90, Number(process.argv[2]) || 14));

function wranglerToken() {
  const paths = [
    join(homedir(), "Library/Preferences/.wrangler/config/default.toml"),
    join(homedir(), ".config/.wrangler/config/default.toml"),
    join(homedir(), ".wrangler/config/default.toml"),
  ];
  for (const p of paths) {
    try {
      const m = readFileSync(p, "utf8").match(/^oauth_token\s*=\s*"([^"]+)"/m);
      if (m) return m[1];
    } catch {
      /* try the next path */
    }
  }
  return null;
}

const token = process.env.CLOUDFLARE_API_TOKEN || wranglerToken();
if (!token) {
  console.error("No Cloudflare token: run `pnpm exec wrangler login` or set CLOUDFLARE_API_TOKEN.");
  process.exit(1);
}
const auth = { Authorization: `Bearer ${token}` };

async function accountId() {
  if (process.env.CLOUDFLARE_ACCOUNT_ID) return process.env.CLOUDFLARE_ACCOUNT_ID;
  const res = await fetch(`${API}/accounts`, { headers: auth });
  const json = await res.json();
  if (!json.success || !json.result?.length) throw new Error(`could not list accounts: ${JSON.stringify(json.errors)}`);
  if (json.result.length > 1) throw new Error("several accounts; set CLOUDFLARE_ACCOUNT_ID");
  return json.result[0].id;
}

async function sql(account, query) {
  const res = await fetch(`${API}/accounts/${account}/analytics_engine/sql`, { method: "POST", headers: auth, body: query });
  const text = await res.text();
  if (!res.ok) throw new Error(`SQL API ${res.status}: ${text.slice(0, 300)}`);
  return JSON.parse(text).data;
}

// _sample_interval undoes Analytics Engine sampling (1 at this volume, but correct regardless).
const since = `timestamp > NOW() - INTERVAL '${days}' DAY`;
const byDay = `
  SELECT toDate(timestamp) AS day, blob1 AS surface,
         SUM(_sample_interval) AS requests,
         SUM(IF(blob4 = '200', _sample_interval, 0)) AS new_data,
         SUM(IF(blob3 = 'custom', _sample_interval, 0)) AS custom
  FROM ${DATASET} WHERE ${since}
  GROUP BY day, surface ORDER BY day DESC, surface`;
const byVersion = `
  SELECT blob1 AS surface, blob2 AS version, SUM(_sample_interval) AS requests, MAX(timestamp) AS last_seen
  FROM ${DATASET} WHERE ${since}
  GROUP BY surface, version ORDER BY surface, last_seen DESC`;

const account = await accountId();
const [days_, versions] = await Promise.all([sql(account, byDay), sql(account, byVersion)]);

console.log(`Wind Watch requests, last ${days} days (new_data = 200, the rest were 304 "unchanged" or errors)\n`);
if (!days_.length) console.log("  no requests recorded yet");
else console.table(days_.map((r) => ({ day: r.day, surface: r.surface, requests: +r.requests, new_data: +r.new_data, custom: +r.custom })));
console.log("\nBy version");
console.table(versions.map((r) => ({ surface: r.surface, version: r.version || "-", requests: +r.requests, last_seen: r.last_seen })));
