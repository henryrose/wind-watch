import Foundation

/// One WidgetKit timeline entry: a date plus an index into the shared forecast (DESIGN §5.2).
public struct WindTimelineEntry: Sendable, Hashable {
    public var date: Date
    /// Index into `forecast.hours`, nil once past the horizon.
    public var hourIndex: Int?
    public var trust: TrustState

    public init(date: Date, hourIndex: Int?, trust: TrustState) {
        self.date = date
        self.hourIndex = hourIndex
        self.trust = trust
    }
}

/// Builds the complication timeline from one forecast, with no network (DESIGN §5.2, HANDOFF §7.1).
public enum TimelineBuilder {
    /// Hard cap on entries handed to WidgetKit.
    public static let maxEntries = 60
    /// The past-horizon boundary sits one hour after the last forecast hour.
    public static let pastHorizonGrace: TimeInterval = 3600

    /// Entries, sorted and de-duplicated by date:
    /// - one at `now` (the current entry), with the hero index for `now`;
    /// - one per hour boundary strictly after `now`, up to and including `forecast.horizon`;
    /// - trust flips at `fetched + 90 min` and `fetched + 6 h` when they fall after `now` and
    ///   before the past-horizon boundary;
    /// - a final past-horizon entry at `horizon + 1 h` (`hourIndex == nil`).
    /// If `now` is already past the horizon the result is exactly one past-horizon entry at `now`.
    /// Capped at `maxEntries`, dropping from the end but never the past-horizon entry.
    public static func entries(forecast: Forecast, now: Date, lastCheckOK: Bool = true) -> [WindTimelineEntry] {
        func entry(at date: Date) -> WindTimelineEntry {
            WindTimelineEntry(
                date: date,
                hourIndex: Derivations.heroIndex(forecast: forecast, now: date),
                trust: TrustState.compute(forecast: forecast, now: date, lastCheckOK: lastCheckOK, isUpdating: false)
            )
        }

        guard now <= forecast.horizon, !forecast.hours.isEmpty else {
            return [WindTimelineEntry(date: now, hourIndex: nil, trust: .pastHorizon)]
        }

        let boundary = forecast.horizon.addingTimeInterval(pastHorizonGrace)
        var dates: [Date] = [now]

        // Hour boundaries strictly after now, through the last forecast hour.
        let firstAfter = Int(Derivations.nowIndex(forecast: forecast, now: now).rounded(.down)) + 1
        for i in max(firstAfter, 0)..<forecast.hours.count {
            dates.append(forecast.date(ofHour: i))
        }

        // Trust flips so the label changes without a refresh.
        for offset in [AgeTier.staleAfter, AgeTier.oldAfter] {
            let flip = forecast.fetched.addingTimeInterval(offset)
            if flip > now, flip < boundary { dates.append(flip) }
        }

        dates.sort()
        var entries: [WindTimelineEntry] = []
        for date in dates where entries.last?.date != date {
            entries.append(entry(at: date))
        }

        let final = WindTimelineEntry(date: boundary, hourIndex: nil, trust: .pastHorizon)
        if entries.count > maxEntries - 1 {
            entries.removeSubrange((maxEntries - 1)...)
        }
        entries.append(final)
        return entries
    }

    /// The rectangular strip's y domain per entry (HANDOFF §6.3), nil for past-horizon entries.
    /// Each is the running max, in entry order, of `Derivations.stripYMax` over the entry's 12-hour
    /// window (`hourIndex ..< hourIndex + 12`). When `carried` is from the same run at the same
    /// place it seeds the max, together with the windows between its entry and the first one here
    /// (the hours the previous timeline may have shown before this reload). So the scale only grows
    /// within a run (bars don't swell as a peak scrolls out of the window) and starts again from
    /// its own window on a new run.
    public static func stripDomains(forecast: Forecast, entries: [WindTimelineEntry], carried: StripScale? = nil) -> [Int?] {
        func domain(_ i: Int) -> Int {
            let window = forecast.hours[i..<min(i + 12, forecast.hours.count)]
            return Derivations.stripYMax(maxGust: window.map(\.gust).max() ?? 0)
        }
        var running = 0
        if let carried, carried.matches(forecast) {
            running = carried.yMax
            if let from = Derivations.heroIndex(forecast: forecast, now: carried.asOf),
               let to = entries.lazy.compactMap(\.hourIndex).first, from < to {
                for i in from..<to { running = max(running, domain(i)) }
            }
        }
        return entries.map { e in
            guard let i = e.hourIndex, forecast.hours.indices.contains(i) else { return nil }
            running = max(running, domain(i))
            return running
        }
    }

    /// Reload policy date: `now + interval` (30 min by default, DESIGN §5.2).
    public static func nextReload(after now: Date, interval: TimeInterval = 30 * 60) -> Date {
        now.addingTimeInterval(interval)
    }
}

/// The rectangular strip domain last shown, carried between timeline builds (HANDOFF §6.3) so a
/// reload within the same run never shrinks it. Keyed by run init time and coordinates.
public struct StripScale: Codable, Sendable, Equatable {
    public var runDate: Date
    public var lat: Double
    public var lon: Double
    public var yMax: Int
    /// The entry date `yMax` was computed for.
    public var asOf: Date

    public init(runDate: Date, lat: Double, lon: Double, yMax: Int, asOf: Date) {
        self.runDate = runDate
        self.lat = lat
        self.lon = lon
        self.yMax = yMax
        self.asOf = asOf
    }

    public init(forecast: Forecast, yMax: Int, asOf: Date) {
        self.init(runDate: forecast.runDate, lat: forecast.location.lat, lon: forecast.location.lon, yMax: yMax, asOf: asOf)
    }

    /// Same HRRR run at the same place.
    public func matches(_ forecast: Forecast) -> Bool {
        runDate == forecast.runDate && lat == forecast.location.lat && lon == forecast.location.lon
    }

    static let defaultsKey = "ww.stripScale"

    public static func load(from defaults: UserDefaults) -> StripScale? {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(StripScale.self, from: $0) }
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
