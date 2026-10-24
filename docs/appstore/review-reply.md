# App Review reply — Wind Watch Sailing 1.0 (7)

Rejected 2026-10-24 with a request for more information (six items). Paste sections 2–6 into
the Resolution Center reply **and** into App Review Information → Notes, then attach the
screen recording (item 1) to the reply.

---

**1. Screen recording**

Attached: a recording on a physical iPhone running the latest iOS, paired with an Apple Watch
running the latest watchOS. It starts at launch and shows the typical flow: the first-launch
location choice, the forecast chart, touching a bar for an hour, the hourly table, choosing a
custom location, the About screen, then the watch app and its complications. Wind Watch has no
accounts, no user-generated content and no paid content or features.

**2. Purpose and target audience**

Wind Watch shows the hourly wind forecast from NOAA's HRRR model (High-Resolution Rapid
Refresh, 3 km, updated hourly) for one location at a time, as a single chart: sustained wind
as Beaufort-coloured bars, gusts as a line, arrows for direction, and day/night shading.
It is for sailors, kayakers, kiteboarders, windsurfers and other small-boat and shoreline
users who need to decide when to go out. General weather apps show wind as a single number
or a smoothed line; Wind Watch shows the model's hour-by-hour sustained wind and gusts up to
the end of the latest forecast run, says how old the data is, and puts the next hours on the
Apple Watch face as complications so the forecast is a glance away on the water.

**3. Setup and main features**

No login, account, credentials or sample files are needed.

1. Launch the app. On first launch choose "Port Townsend Bay" (one tap) or "Somewhere else".
2. "Somewhere else" or the gear button on the main screen opens Location: search a place name
   or long-press the map to drop a pin, then Save. Points outside HRRR coverage are refused
   with an explanation.
3. The main screen shows current wind, the 40–48 hour chart (touch and drag a bar to see that
   hour), a plain-language summary, and an expandable hourly table. Rotate to landscape for a
   wider chart. "About" (bottom right) explains the model and colours.
4. Apple Watch: open Wind Watch for a 12-hour strip, a Now page and Settings (scroll with the
   Digital Crown). Long-press a watch face → Edit → Complications → "Wind Watch" to add the
   rectangular, circular, inline or corner complication. The watch app works without the
   phone nearby, and follows the location chosen on the iPhone.

**4. External services**

- Wind Watch server (our own Cloudflare Worker at
  wind-watch.wind-watch-server.workers.dev): fetches and caches the forecast; the apps only
  talk to this server. It keeps anonymous request counts (surface, version, country) with no
  identifiers.
- Open-Meteo (open-meteo.com): weather data provider; the server retrieves NOAA HRRR forecasts
  from it under CC BY 4.0, credited in the app's About screen and footer. The app is free and
  non-commercial, within Open-Meteo's free-tier terms.
- Apple MapKit: place search and reverse geocoding on the Location screen.
- No authentication, payment, advertising, third-party analytics or AI services.

**5. Regional differences**

The app works the same in every region and its interface is English only. The forecast data
(NOAA HRRR) covers the continental United States and nearby parts of Canada and Mexico, so the
default location (Port Townsend Bay, Washington) works for everyone, and custom locations can
be chosen anywhere inside that coverage; points outside it are refused in the app with a
message explaining why.

**6. Regulated industry / third-party material**

Not applicable. Wind Watch is not in a regulated industry and provides forecast guidance only.
The weather data is public NOAA model output redistributed by Open-Meteo under CC BY 4.0, with
the required attribution shown in the app. No protected third-party material is used.

---

Contact: windwatch@wilder-roses.com
