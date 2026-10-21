# Wind Watch — web

One static page: `index.html`, `styles.css`, `app.js`, `config.js`, and the pure
derivation module `lib/derive.js`. No build step, no dependencies, no CDN.

## Run locally (fixture mode)

`config.js` ships with `apiBase: ""`, which makes the page load
`../fixtures/payload-reference.json` relative to itself. Serve the **repo root**
so that path resolves:

```sh
cd <repo root>
python3 -m http.server 8080
open http://localhost:8080/web/
```

Opening `index.html` from the filesystem does not work: `app.js` is an ES module
and the fixture is fetched, both of which browsers block on `file://`.

## Verification query strings

The page pins its clock to `start + 30 min` in fixture mode so the reference
payload reads as fresh. Override for screenshots:

| Param | Values | Effect |
|---|---|---|
| `state` | `fresh` `stale` `old` `offline` `horizon` `firstrun` `updating` | Forces a HANDOFF §3 trust state. Each state also picks a sensible default `now` (stale = fetched + 2 h, old = fetched + 7 h, horizon = past the last hour) unless `now` is given. |
| `now` | ISO 8601, e.g. `2026-10-22T06:30:00Z`, or `live` | Pins the clock. `live` uses the real clock and re-renders every minute so the 90-min / 6-h flips happen without a reload. |
| `scheme` | `dark` `light` | Forces a colour scheme instead of `prefers-color-scheme` (headless screenshots). |

Examples:

```
http://localhost:8080/web/?state=fresh
http://localhost:8080/web/?state=old&scheme=light
http://localhost:8080/web/?state=offline&now=2026-10-22T06:30:00Z
http://localhost:8080/web/?state=horizon
```

## Tests

```sh
export PATH="$HOME/.nvm/versions/node/v24.13.0/bin:$PATH"   # this machine
cd web && node --test
```

`test/derive.test.js` checks the HANDOFF §10 expected values, the §6.2 twilight
fractions, trust-state transitions, labels, and that `styles.css` carries the
exact §4.1 ramp hexes.

## Live mode (E2)

Set `apiBase` in `config.js` to the Worker origin; the page then fetches
`<apiBase>/v1/wind`. Cache/ETag/offline-with-cache handling lands with task E2.
