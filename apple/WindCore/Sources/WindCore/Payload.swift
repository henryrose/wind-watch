import Foundation

/// The wire payload served by the Worker at `GET /v1/wind` (DESIGN.md §4.2).
///
/// Field names and types mirror the JSON exactly; timestamps are unix seconds.
/// UI code should not read this directly — build a `Forecast` from it.
public struct Payload: Codable, Sendable, Equatable {
    public struct Location: Codable, Sendable, Equatable {
        public var name: String
        public var lat: Double
        public var lon: Double
        /// IANA time zone identifier, e.g. `America/Los_Angeles`.
        public var tz: String
        /// Open-Meteo `cell_selection` used for this payload (`sea` for the default).
        public var cell: String

        public init(name: String, lat: Double, lon: Double, tz: String, cell: String) {
            self.name = name
            self.lat = lat
            self.lon = lon
            self.tz = tz
            self.cell = cell
        }
    }

    public struct Run: Codable, Sendable, Equatable {
        /// HRRR init time of the latest run (unix seconds).
        public var latest: Int
        /// HRRR init time of the extended (48 h) run whose tail is used, if different.
        public var extended: Int?

        public init(latest: Int, extended: Int? = nil) {
            self.latest = latest
            self.extended = extended
        }

        public var latestDate: Date { Date(timeIntervalSince1970: TimeInterval(latest)) }
        public var extendedDate: Date? { extended.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    }

    public struct Peak: Codable, Sendable, Equatable {
        public var gust: Int
        public var at: Int

        public init(gust: Int, at: Int) {
            self.gust = gust
            self.at = at
        }

        public var atDate: Date { Date(timeIntervalSince1970: TimeInterval(at)) }
    }

    /// One local civil day: civil dawn, sunrise, sunset, civil dusk (unix seconds).
    public struct Sun: Codable, Sendable, Equatable {
        public var dawn: Int
        public var rise: Int
        public var set: Int
        public var dusk: Int

        public init(dawn: Int, rise: Int, set: Int, dusk: Int) {
            self.dawn = dawn
            self.rise = rise
            self.set = set
            self.dusk = dusk
        }

        public var dawnDate: Date { Date(timeIntervalSince1970: TimeInterval(dawn)) }
        public var riseDate: Date { Date(timeIntervalSince1970: TimeInterval(rise)) }
        public var setDate: Date { Date(timeIntervalSince1970: TimeInterval(set)) }
        public var duskDate: Date { Date(timeIntervalSince1970: TimeInterval(dusk)) }
    }

    /// NBM after the HRRR horizon (DESIGN §4.2a): 3-hour blocks from `from`, which the server sets
    /// to exactly `start + hours × 3600`, so NBM never covers an hour HRRR owns.
    public struct Extended: Codable, Sendable, Equatable {
        public var model: String
        /// NBM init time (unix seconds).
        public var run: Int
        /// When the Worker last pulled NEW NBM data (unix seconds).
        public var fetched: Int
        /// Hours per block.
        public var step: Int
        /// Unix seconds of block 0's start.
        public var from: Int
        /// Count of blocks; each array below has this length.
        public var blocks: Int
        public var kn: [Int]
        public var gust: [Int]
        public var dir: [Int]
        /// Mean °C per block, one decimal.
        public var temp: [Double]?
        /// Mean total cloud cover per block, %.
        public var cloud: [Int]?
        /// Max precipitation per block, mm/h.
        public var precip: [Double]?

        public init(model: String, run: Int, fetched: Int, step: Int, from: Int, blocks: Int,
                    kn: [Int], gust: [Int], dir: [Int], temp: [Double]? = nil, cloud: [Int]? = nil, precip: [Double]? = nil) {
            self.model = model
            self.run = run
            self.fetched = fetched
            self.step = step
            self.from = from
            self.blocks = blocks
            self.kn = kn
            self.gust = gust
            self.dir = dir
            self.temp = temp
            self.cloud = cloud
            self.precip = precip
        }
    }

    public var v: Int
    public var loc: Location
    public var model: String
    /// When the Worker last pulled NEW data from Open-Meteo (unix seconds).
    public var fetched: Int
    public var run: Run
    /// Unix seconds of hour index 0.
    public var start: Int
    /// Count of forecast hours; `kn`, `gust`, `dir` have this length.
    public var hours: Int
    public var kn: [Int]
    public var gust: [Int]
    /// Direction the wind blows FROM, degrees true.
    public var dir: [Int]
    public var peak: Peak
    public var summary: String
    public var sun: [Sun]
    /// HRRR 2 m temperature, °C, one decimal (§4.2a; optional, length == hours).
    public var temp: [Double]?
    /// HRRR total cloud cover, % (§4.2a; optional).
    public var cloud: [Int]?
    /// HRRR precipitation, mm/h (§4.2a; optional).
    public var precip: [Double]?
    /// NBM beyond the HRRR horizon; nil (missing or `null`) when NBM is unavailable.
    public var extended: Extended?

    public init(
        v: Int, loc: Location, model: String, fetched: Int, run: Run, start: Int, hours: Int,
        kn: [Int], gust: [Int], dir: [Int], peak: Peak, summary: String, sun: [Sun],
        temp: [Double]? = nil, cloud: [Int]? = nil, precip: [Double]? = nil, extended: Extended? = nil
    ) {
        self.v = v
        self.loc = loc
        self.model = model
        self.fetched = fetched
        self.run = run
        self.start = start
        self.hours = hours
        self.kn = kn
        self.gust = gust
        self.dir = dir
        self.peak = peak
        self.summary = summary
        self.sun = sun
        self.temp = temp
        self.cloud = cloud
        self.precip = precip
        self.extended = extended
    }

    public var fetchedDate: Date { Date(timeIntervalSince1970: TimeInterval(fetched)) }
    public var startDate: Date { Date(timeIntervalSince1970: TimeInterval(start)) }

    /// Decodes and validates a wire payload.
    public static func decode(_ data: Data) throws -> Payload {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        try payload.validate()
        return payload
    }

    /// Compact JSON (no whitespace), sorted keys for a stable byte sequence.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case unsupportedVersion(Int)
        case lengthMismatch(hours: Int, kn: Int, gust: Int, dir: Int)
        case noHours
    }

    public func validate() throws {
        guard v == 1 else { throw ValidationError.unsupportedVersion(v) }
        guard hours > 0 else { throw ValidationError.noHours }
        guard kn.count == hours, gust.count == hours, dir.count == hours else {
            throw ValidationError.lengthMismatch(hours: hours, kn: kn.count, gust: gust.count, dir: dir.count)
        }
    }
}
