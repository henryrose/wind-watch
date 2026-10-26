# Fixtures

- `openmeteo-forecast-2026-10-21.json` — raw Open-Meteo HRRR response for the default location
  (`cell_selection=sea`, `timezone=GMT`, `timeformat=unixtime`, `forecast_hours=50`, knots).
  Input to `server/src/transform.ts` tests.
- `openmeteo-meta-2026-10-21.json` — `https://api.open-meteo.com/data/ncep_hrrr_conus/static/meta.json`
  captured the same minute. Gives `last_run_initialisation_time` / `last_run_availability_time`.
- `openmeteo-forecast-2026-10-26.json` — the same HRRR request with the §4.2a series added
  (`temperature_2m,cloud_cover,precipitation`), captured 2026-10-26 17:27Z: 44 non-null hours from 17Z.
  The 21 Oct file has no sky series; tests that use it add flat ones (`server/test/helpers.ts`).
- `openmeteo-meta-2026-10-26.json` / `openmeteo-nbm-meta-2026-10-26.json` — HRRR and
  `ncep_nbm_conus` meta.json, same minute.
- `openmeteo-nbm-forecast-2026-10-26.json` — NBM for exactly that bake's window
  (`start_hour=2026-10-28T13:00&end_hour=2026-11-02T15:00`, GMT, `cell_selection=sea`, knots): 123 hours,
  41 whole 3-hour blocks.
- `payload-reference.json` — the wire payload (DESIGN.md §4.2) hand-built from the handoff doc's
  reference data (design/DESIGN-HANDOFF.md §10). Hour 0 = 2026-10-21 09:00 PDT, 45 hours.
  Used by Swift tests, the web page's fixture mode, and UI previews. Sun times are the handoff's
  approximations, not computed.
  The 26 Oct additions (DESIGN.md §4.2a: `temp`, `cloud`, `precip`, `extended`) are illustrative:
  sky from `design/handoff-2026-10-26/reference/sky_reference.py`, NBM blocks from `mixed_reference.py`
  (33 blocks, hour 45 → 144, "ends Tue 9am"), temperatures a made-up diurnal curve. The original keys are
  byte-identical to the 21 Oct file. `apple/WindCore/Sources/WindCore/Resources/` holds an identical copy.
