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

        public init(kn: Int, gust: Int, dirFrom: Int) {
            self.kn = kn
            self.gust = gust
            self.dirFrom = dirFrom
        }
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

    public init(
        location: Location, model: String, run: String, runDate: Date, fetched: Date, start: Date,
        hours: [Hour], sun: [SunDay], summary: String, peakGust: PeakGust, timeZone: TimeZone
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
    }

    /// Builds the view model from a wire payload. `isDefault` is device state (IMPLEMENTATION_PLAN §0).
    public init(payload: Payload, isDefault: Bool) {
        let count = min(payload.hours, payload.kn.count, payload.gust.count, payload.dir.count)
        let hours = (0..<max(count, 0)).map { i in
            Hour(kn: payload.kn[i], gust: payload.gust[i], dirFrom: payload.dir[i])
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
            timeZone: TimeZone(identifier: payload.loc.tz) ?? .current
        )
    }

    /// `"HRRR " + two-digit UTC hour + "Z"`, e.g. `HRRR 15Z`.
    public static func runLabel(latest: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let hour = cal.component(.hour, from: latest)
        return "HRRR " + String(format: "%02dZ", hour)
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
