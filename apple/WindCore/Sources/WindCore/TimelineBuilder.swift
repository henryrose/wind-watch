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

    /// Reload policy date: `now + interval` (30 min by default, DESIGN §5.2).
    public static func nextReload(after now: Date, interval: TimeInterval = 30 * 60) -> Date {
        now.addingTimeInterval(interval)
    }
}
