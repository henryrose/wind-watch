// Wire payload and upstream input types.
// The Payload shape is the contract in docs/DESIGN.md §4.2 and §4.2a; key order here is
// the order the payload is serialised in (see stableStringify.ts).

/** Unix seconds. */
export type UnixSeconds = number;

export interface Location {
  /** Display name; empty for custom (`?lat&lon`) locations, the device shows its own. */
  name: string;
  /** Snapped grid-cell latitude, as reported by Open-Meteo. */
  lat: number;
  lon: number;
  /** IANA time zone, e.g. "America/Los_Angeles". */
  tz: string;
  /** Open-Meteo `cell_selection` used: "sea" for the default location, "nearest" for custom. */
  cell: "sea" | "nearest";
}

export interface SunDay {
  dawn: UnixSeconds; // civil dawn, sun at −6°
  rise: UnixSeconds;
  set: UnixSeconds;
  dusk: UnixSeconds; // civil dusk
}

export interface Payload {
  v: 1;
  loc: Location;
  model: "ncep_hrrr_conus";
  /** When the Worker last pulled NEW data from Open-Meteo. */
  fetched: UnixSeconds;
  run: {
    /** Init time of the newest HRRR run (from meta.json). */
    latest: UnixSeconds;
    /** Inferred init time of the 48-h run supplying the tail, or null if indistinguishable. */
    extended: UnixSeconds | null;
  };
  /** Unix seconds of hour index 0. `time[i] = start + i*3600`. */
  start: UnixSeconds;
  /** Count of non-null hours; the HRRR horizon is `start + hours*3600`. */
  hours: number;
  /** Sustained 10 m wind, knots, integers, length == hours. */
  kn: number[];
  /** Gusts, knots, integers, length == hours. */
  gust: number[];
  /** Direction the wind blows FROM, degrees true, integers 0..359, length == hours. */
  dir: number[];
  peak: { gust: number; at: UnixSeconds };
  /** Rule-based one-liner (B3). Empty string until then. */
  summary: string;
  /** One entry per local civil day touched by [start, horizon] (B2). */
  sun: SunDay[];
  /** HRRR 2 m temperature, °C, one decimal, length == hours (§4.2a). */
  temp: number[];
  /** HRRR total cloud cover, %, integers 0..100, length == hours. */
  cloud: number[];
  /** HRRR precipitation, mm/h, one decimal, length == hours. */
  precip: number[];
  /** NBM in 3-hour blocks after the HRRR horizon; null when NBM is unavailable (§4.2a). */
  extended: Extended | null;
}

/** NBM beyond the HRRR horizon (DESIGN §4.2a). Block i covers [from + i*step h, from + (i+1)*step h). */
export interface Extended {
  model: "ncep_nbm_conus";
  /** NBM init time (its meta.json `last_run_initialisation_time`). */
  run: UnixSeconds;
  /** When the Worker first pulled this NBM run. */
  fetched: UnixSeconds;
  /** Hours per block. */
  step: 3;
  /** Always `start + hours*3600`: the first hour after HRRR. */
  from: UnixSeconds;
  /** Whole blocks only, ending at or before `start + 168 h`. */
  blocks: number;
  /** Max sustained in the block, knots, integers. */
  kn: number[];
  /** Max gust in the block, knots, integers. */
  gust: number[];
  /** Vector-mean FROM direction of the block's hours, integers 0..359. */
  dir: number[];
  /** Mean °C, one decimal. */
  temp: number[];
  /** Mean %, integers. */
  cloud: number[];
  /** Max mm/h, one decimal. */
  precip: number[];
}

/**
 * Open-Meteo forecast response with `timeformat=unixtime`, `wind_speed_unit=kn` and
 * `hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m,temperature_2m,cloud_cover,precipitation`,
 * for HRRR and NBM alike. Only the fields the transform reads are typed. Hours beyond the
 * model horizon are null. The sky/temperature series are optional only because the
 * 21 Oct fixture predates them; the transform refuses a response without them.
 */
export interface OpenMeteoForecast {
  latitude: number;
  longitude: number;
  utc_offset_seconds: number;
  timezone: string;
  hourly: {
    time: number[];
    wind_speed_10m: (number | null)[];
    wind_direction_10m: (number | null)[];
    wind_gusts_10m: (number | null)[];
    temperature_2m?: (number | null)[];
    cloud_cover?: (number | null)[];
    precipitation?: (number | null)[];
  };
}

/** `https://api.open-meteo.com/data/<model>/static/meta.json` (HRRR and NBM have the same shape). */
export interface OpenMeteoMeta {
  last_run_initialisation_time: UnixSeconds;
  last_run_availability_time: UnixSeconds;
  last_run_modification_time?: UnixSeconds;
  data_end_time?: UnixSeconds;
  update_interval_seconds?: number;
  temporal_resolution_seconds?: number;
}
