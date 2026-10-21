# Fixtures

- `openmeteo-forecast-2026-10-21.json` — raw Open-Meteo HRRR response for the default location
  (`cell_selection=sea`, `timezone=GMT`, `timeformat=unixtime`, `forecast_hours=50`, knots).
  Input to `server/src/transform.ts` tests.
- `openmeteo-meta-2026-10-21.json` — `https://api.open-meteo.com/data/ncep_hrrr_conus/static/meta.json`
  captured the same minute. Gives `last_run_initialisation_time` / `last_run_availability_time`.
- `payload-reference.json` — the wire payload (DESIGN.md §4.2) hand-built from the handoff doc's
  reference data (WINDWATCH-DESIGN-HANDOFF.md §10). Hour 0 = 2026-10-21 09:00 PDT, 45 hours.
  Used by Swift tests, the web page's fixture mode, and UI previews. Sun times are the handoff's
  approximations, not computed.
