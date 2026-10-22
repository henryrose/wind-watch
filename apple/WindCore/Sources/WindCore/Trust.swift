import Foundation

/// Age tier of the data itself (DESIGN §6.1). This is what dims numbers; it applies even when the
/// trust line is showing an offline or updating message.
public enum AgeTier: Sendable, Equatable {
    case fresh
    case stale
    case old

    /// 90 minutes.
    public static let staleAfter: TimeInterval = 90 * 60
    /// 6 hours.
    public static let oldAfter: TimeInterval = 6 * 3600

    public static func compute(fetched: Date, now: Date) -> AgeTier {
        let age = now.timeIntervalSince(fetched)
        if age >= oldAfter { return .old }
        if age >= staleAfter { return .stale }
        return .fresh
    }
}

/// Trust state shared by every surface (HANDOFF §3).
public enum TrustState: Sendable, Equatable, CaseIterable {
    case fresh
    case stale
    case old
    case pastHorizon
    case offlineCached
    case firstRun
    case updating

    /// Decides the state. Precedence, highest first:
    /// no forecast → `firstRun`; `now > horizon` → `pastHorizon`; refresh in flight → `updating`;
    /// last check failed → `offlineCached`; otherwise the age tier.
    public static func compute(
        forecast: Forecast?, now: Date, lastCheckOK: Bool, isUpdating: Bool = false
    ) -> TrustState {
        guard let forecast else { return .firstRun }
        if now > forecast.horizon { return .pastHorizon }
        if isUpdating { return .updating }
        if !lastCheckOK { return .offlineCached }
        switch AgeTier.compute(fetched: forecast.fetched, now: now) {
        case .fresh: return .fresh
        case .stale: return .stale
        case .old: return .old
        }
    }

    /// Trust line drawn in `trust.amber` (Semibold).
    public var isAmber: Bool {
        switch self {
        case .stale, .old, .offlineCached: true
        case .fresh, .pastHorizon, .firstRun, .updating: false
        }
    }

    /// Whether wind numbers are shown at all (false → hero shows `—`).
    public var showsNumbers: Bool {
        switch self {
        case .pastHorizon, .firstRun: false
        default: true
        }
    }
}

/// Trust-line strings (HANDOFF §3). Times are in the forecast's time zone unless `tz` overrides.
public enum TrustLine {
    /// Complication text for the past-horizon state.
    public static let pastHorizonComplicationText = "No forecast — open app"
    /// Inline complication text for the past-horizon state.
    public static let pastHorizonInlineText = "Wind — open app"
    /// First-run body text.
    public static let firstRunText = "No data yet. Needs cellular or Wi-Fi once."
    /// First-run footer text (next to the only permitted spinner).
    public static let firstRunFooterText = "trying…"

    /// The app trust line for a state.
    ///
    /// - fresh / stale: `as of 09:00 · HRRR 15Z`
    /// - old: `as of Tue 13:05 · HRRR 15Z`
    /// - pastHorizon: `No forecast · last run HRRR 15Z Tue`
    /// - offlineCached: `Couldn't reach server · showing data from 13:05` (with weekday once old)
    /// - updating: `updating · as of 09:00` (with weekday once old)
    /// - firstRun: `No data yet. Needs cellular or Wi-Fi once.`
    public static func text(state: TrustState, forecast: Forecast?, now: Date, tz: TimeZone? = nil) -> String {
        guard let forecast else { return firstRunText }
        let zone = tz ?? forecast.timeZone
        let tier = AgeTier.compute(fetched: forecast.fetched, now: now)
        let asOf = tier == .old
            ? TimeFormat.weekdayHHMM(forecast.fetched, tz: zone)
            : TimeFormat.hhmm(forecast.fetched, tz: zone)
        switch state {
        case .fresh, .stale:
            return "as of \(TimeFormat.hhmm(forecast.fetched, tz: zone)) · \(forecast.run)"
        case .old:
            return "as of \(TimeFormat.weekdayHHMM(forecast.fetched, tz: zone)) · \(forecast.run)"
        case .pastHorizon:
            return "No forecast · last run \(forecast.run) \(TimeFormat.weekdayShort(forecast.runDate, tz: zone))"
        case .offlineCached:
            return "Couldn't reach server · showing data from \(asOf)"
        case .updating:
            return "updating · as of \(asOf)"
        case .firstRun:
            return firstRunText
        }
    }

    /// Inline complication text: `15 G25 kn`, `15 G25 kn · 13:05` (stale), `15 G25 kn · Tue 13:05`
    /// (old), `Wind — open app` (past horizon / first run). Offline and updating fall back to the
    /// age tier, since the inline slot has no room for a reason.
    public static func inlineText(state: TrustState, hero: Forecast.Hour?, forecast: Forecast?, now: Date, tz: TimeZone? = nil) -> String {
        guard let forecast, let hero, state.showsNumbers else { return pastHorizonInlineText }
        let zone = tz ?? forecast.timeZone
        let numbers = "\(hero.kn) G\(hero.gust) kn"
        switch AgeTier.compute(fetched: forecast.fetched, now: now) {
        case .fresh: return numbers
        case .stale: return numbers + " · " + TimeFormat.hhmm(forecast.fetched, tz: zone)
        case .old: return numbers + " · " + TimeFormat.weekdayHHMM(forecast.fetched, tz: zone)
        }
    }
}

/// Free-function form of `TrustLine.text`, as named in the implementation plan.
public func trustLineText(state: TrustState, forecast: Forecast?, now: Date, tz: TimeZone? = nil) -> String {
    TrustLine.text(state: state, forecast: forecast, now: now, tz: tz)
}

/// Fixed-format time strings (24 h, English weekday abbreviations) independent of device locale.
public enum TimeFormat {
    private static func formatter(_ format: String, tz: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = tz
        f.dateFormat = format
        return f
    }

    /// `13` (axis tick labels)
    public static func hh(_ date: Date, tz: TimeZone) -> String {
        formatter("HH", tz: tz).string(from: date)
    }

    /// `13:05`
    public static func hhmm(_ date: Date, tz: TimeZone) -> String {
        formatter("HH:mm", tz: tz).string(from: date)
    }

    /// `Tue 13:05`
    public static func weekdayHHMM(_ date: Date, tz: TimeZone) -> String {
        formatter("EEE HH:mm", tz: tz).string(from: date)
    }

    /// `Tue`
    public static func weekdayShort(_ date: Date, tz: TimeZone) -> String {
        formatter("EEE", tz: tz).string(from: date)
    }

    /// `Tuesday`
    public static func weekdayLong(_ date: Date, tz: TimeZone) -> String {
        formatter("EEEE", tz: tz).string(from: date)
    }

    /// Local hour of day (0…23).
    public static func hour(_ date: Date, tz: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.component(.hour, from: date)
    }

    /// Chart tick form of an hour (HANDOFF §6.4a): `12am`, `9am`, `noon`, `3pm`.
    public static func hour12Tick(hour: Int) -> String {
        hour == 12 ? "noon" : hour12(hour: hour)
    }

    /// `12am`, `9am`, `12pm`, `5pm`.
    public static func hour12(hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        let twelve = h % 12 == 0 ? 12 : h % 12
        return "\(twelve)" + (h < 12 ? "am" : "pm")
    }

    /// `Fri 5am` (chart title, edge label, header suffix).
    public static func weekdayHour12(_ date: Date, tz: TimeZone) -> String {
        weekdayShort(date, tz: tz) + " " + hour12(hour: hour(date, tz: tz))
    }

    /// Scrub / tooltip hour label: `Thu 12am · midnight`, `Thu 12pm · noon`, else `Thu 3pm`.
    public static func scrubLabel(_ date: Date, tz: TimeZone) -> String {
        let h = hour(date, tz: tz)
        let base = weekdayHour12(date, tz: tz)
        switch h {
        case 0: return base + " · midnight"
        case 12: return base + " · noon"
        default: return base
        }
    }
}
