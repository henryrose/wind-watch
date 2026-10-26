import Foundation

/// The view model every surface reads (HANDOFF §2), built once from a `Payload`.
public struct Forecast: Sendable, Equatable {
    public struct Location: Sendable, Equatable {
        public var name: String
        public var lat: Double
        public var lon: Double
        /// Device state, not wire state: true when showing the built-in default location.
        public var isDefault: Bool

        public init(name: String, lat: Double, lon: Double, isDefault: Bool) {
            self.name = name
            self.lat = lat
            self.lon = lon
            self.isDefault = isDefault
        }
    }

    public struct Hour: Sendable, Hashable {
        /// Sustained wind, knots.
        public var kn: Int
        /// Gust, knots.
        public var gust: Int
        /// Direction the wind blows FROM, degrees true.
        public var dirFrom: Int
        /// 2 m temperature, °C (nil when the payload has none). Shown only in the scrub readout and table.
        public var tempC: Double?
        /// Total cloud cover, % (sky band, §12b).
        public var cloud: Int?
        /// Precipitation, mm/h (sky band rain ticks).
        public var precip: Double?

        public init(kn: Int, gust: Int, dirFrom: Int, tempC: Double? = nil, cloud: Int? = nil, precip: Double? = nil) {
            self.kn = kn
            self.gust = gust
            self.dirFrom = dirFrom
            self.tempC = tempC
            self.cloud = cloud
            self.precip = precip
        }
    }

    /// NBM after the HRRR horizon (spec §12a, DESIGN §4.2a). HRRR owns every hour it covers, so
    /// `from` is never before `start + hours.count` hours; `init(payload:)` drops an `extended`
    /// that would overlap.
    public struct Extended: Sendable, Equatable {
        /// One NBM block of `hours` hours from `start`; values are the block's max sustained, max
        /// gust and vector-mean direction, plus mean temperature / cloud and max precipitation.
        public struct Block: Sendable, Hashable {
            public var start: Date
            public var hours: Int
            public var wind: Hour

            public init(start: Date, hours: Int, wind: Hour) {
                self.start = start
                self.hours = hours
                self.wind = wind
            }

            public var end: Date { start.addingTimeInterval(TimeInterval(hours) * 3600) }
        }

        /// Run label, e.g. `NBM 13Z`.
        public var run: String
        public var runDate: Date
        /// When the server last got new NBM data (its own staleness clock).
        public var fetched: Date
        /// Hours per block (3).
        public var step: Int
        /// Start of block 0.
        public var from: Date
        public var blocks: [Block]

        public init(run: String, runDate: Date, fetched: Date, step: Int, from: Date, blocks: [Block]) {
            self.run = run
            self.runDate = runDate
            self.fetched = fetched
            self.step = step
            self.from = from
            self.blocks = blocks
        }

        /// End of the last block (exclusive): where the 7-day chart ends.
        public var end: Date { blocks.last?.end ?? from }
        /// Last block's start: the hour the `ends Tue 9am` label names.
        public var lastBlockStart: Date { blocks.last?.start ?? from }
    }

    public struct SunDay: Sendable, Hashable {
        public var civilDawn: Date
        public var sunrise: Date
        public var sunset: Date
        public var civilDusk: Date

        public init(civilDawn: Date, sunrise: Date, sunset: Date, civilDusk: Date) {
            self.civilDawn = civilDawn
            self.sunrise = sunrise
            self.sunset = sunset
            self.civilDusk = civilDusk
        }
    }

    public struct PeakGust: Sendable, Hashable {
        public var kn: Int
        public var at: Date

        public init(kn: Int, at: Date) {
            self.kn = kn
            self.at = at
        }
    }

    public var location: Location
    /// Model identifier from the wire payload, e.g. `ncep_hrrr_conus`.
    public var model: String
    /// Run label, e.g. `HRRR 15Z` (UTC hour of the latest run's init time).
    public var run: String
    /// Init time of the latest run.
    public var runDate: Date
    /// When the server last got new model data.
    public var fetched: Date
    /// Hour index 0.
    public var start: Date
    /// Last forecast hour (inclusive): `start + (hours.count − 1) × 3600`.
    public var horizon: Date
    public var hours: [Hour]
    public var sun: [SunDay]
    public var summary: String
    public var peakGust: PeakGust
    /// The location's local time zone (from `loc.tz`); all displayed times use it.
    public var timeZone: TimeZone
    /// NBM after the HRRR horizon, or nil when unavailable (the 7-day range then stops at HRRR).
    public var extended: Extended?

    public init(
        location: Location, model: String, run: String, runDate: Date, fetched: Date, start: Date,
        hours: [Hour], sun: [SunDay], summary: String, peakGust: PeakGust, timeZone: TimeZone,
        extended: Extended? = nil
    ) {
        self.location = location
        self.model = model
        self.run = run
        self.runDate = runDate
        self.fetched = fetched
        self.start = start
        self.horizon = Forecast.horizon(start: start, hourCount: hours.count)
        self.hours = hours
        self.sun = sun
        self.summary = summary
        self.peakGust = peakGust
        self.timeZone = timeZone
        self.extended = extended
    }

    /// Builds the view model from a wire payload. `isDefault` is device state (IMPLEMENTATION_PLAN §0).
    public init(payload: Payload, isDefault: Bool) {
        let count = min(payload.hours, payload.kn.count, payload.gust.count, payload.dir.count)
        // Sky and temperature are optional (§4.2a); a series of the wrong length is ignored.
        let temp = payload.temp.flatMap { $0.count == payload.hours ? $0 : nil }
        let cloud = payload.cloud.flatMap { $0.count == payload.hours ? $0 : nil }
        let precip = payload.precip.flatMap { $0.count == payload.hours ? $0 : nil }
        let hours = (0..<max(count, 0)).map { i in
            Hour(kn: payload.kn[i], gust: payload.gust[i], dirFrom: payload.dir[i],
                 tempC: temp?[i], cloud: cloud?[i], precip: precip?[i])
        }
        let sun = payload.sun.map {
            SunDay(civilDawn: $0.dawnDate, sunrise: $0.riseDate, sunset: $0.setDate, civilDusk: $0.duskDate)
        }
        self.init(
            location: Location(name: payload.loc.name, lat: payload.loc.lat, lon: payload.loc.lon, isDefault: isDefault),
            model: payload.model,
            run: Forecast.runLabel(latest: payload.run.latestDate),
            runDate: payload.run.latestDate,
            fetched: payload.fetchedDate,
            start: payload.startDate,
            hours: hours,
            sun: sun,
            summary: payload.summary,
            peakGust: PeakGust(kn: payload.peak.gust, at: payload.peak.atDate),
            timeZone: TimeZone(identifier: payload.loc.tz) ?? .current,
            extended: payload.extended.flatMap { Forecast.extended($0, hrrrEnd: payload.start + count * 3600) }
        )
    }

    /// The NBM blocks of a wire payload. Returns nil when there are none, or when `from` would put
    /// NBM on an hour HRRR covers (the server enforces this; this is the belt to its braces).
    static func extended(_ e: Payload.Extended, hrrrEnd: Int) -> Extended? {
        guard e.from >= hrrrEnd, e.step > 0 else { return nil }
        let n = min(e.blocks, e.kn.count, e.gust.count, e.dir.count)
        guard n > 0 else { return nil }
        let temp = e.temp.flatMap { $0.count >= n ? $0 : nil }
        let cloud = e.cloud.flatMap { $0.count >= n ? $0 : nil }
        let precip = e.precip.flatMap { $0.count >= n ? $0 : nil }
        let blocks = (0..<n).map { i in
            Extended.Block(
                start: Date(timeIntervalSince1970: TimeInterval(e.from + i * e.step * 3600)), hours: e.step,
                wind: Hour(kn: e.kn[i], gust: e.gust[i], dirFrom: e.dir[i], tempC: temp?[i], cloud: cloud?[i], precip: precip?[i]))
        }
        let runDate = Date(timeIntervalSince1970: TimeInterval(e.run))
        return Extended(run: runLabel(latest: runDate, model: "NBM"), runDate: runDate,
                        fetched: Date(timeIntervalSince1970: TimeInterval(e.fetched)), step: e.step,
                        from: Date(timeIntervalSince1970: TimeInterval(e.from)), blocks: blocks)
    }

    /// `"HRRR " + two-digit UTC hour + "Z"`, e.g. `HRRR 15Z` (`NBM 13Z` for the second model).
    public static func runLabel(latest: Date, model: String = "HRRR") -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let hour = cal.component(.hour, from: latest)
        return model + " " + String(format: "%02dZ", hour)
    }

    /// `start + (hourCount − 1) × 3600`; equals `start` when there are no hours.
    public static func horizon(start: Date, hourCount: Int) -> Date {
        start.addingTimeInterval(TimeInterval(max(hourCount, 1) - 1) * 3600)
    }

    /// Timestamp of hour index `i` (`start + i × 3600`).
    public func date(ofHour index: Int) -> Date {
        start.addingTimeInterval(TimeInterval(index) * 3600)
    }

    /// Largest gust over all hours (0 when empty).
    public var maxGust: Int { hours.map(\.gust).max() ?? 0 }
}
