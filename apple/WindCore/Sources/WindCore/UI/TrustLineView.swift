import SwiftUI

/// The trust line (HANDOFF §3): secondary ink when fresh/updating/first run; amber Semibold when
/// stale, old, offline or past horizon; `wifi.slash` leading when offline; a 14 pt activity ring
/// when updating. `compact` is the watch 12 pt variant.
public struct TrustLineView: View {
    public var state: TrustState
    public var forecast: Forecast?
    public var now: Date
    public var tz: TimeZone?
    public var compact: Bool
    /// Appended as ` · suffix` when the line is an "as of" line (fresh, stale, old, updating),
    /// e.g. the phone header's `ends Fri 05:00`.
    public var suffix: String?
    /// 7 d (§12a): name the NBM run after HRRR's, `as of 09:00 · HRRR 15Z + NBM 13Z`. Its staleness
    /// is its own: a stale NBM run ambers only its label.
    public var showsNBM: Bool

    @Environment(\.colorScheme) private var scheme

    public init(state: TrustState, forecast: Forecast?, now: Date, tz: TimeZone? = nil, compact: Bool = false,
                suffix: String? = nil, showsNBM: Bool = false) {
        self.state = state
        self.forecast = forecast
        self.now = now
        self.tz = tz
        self.compact = compact
        self.suffix = suffix
        self.showsNBM = showsNBM
    }

    private var isAsOfLine: Bool {
        switch state {
        case .fresh, .stale, .old, .updating: forecast != nil
        default: false
        }
    }

    /// `NBM 13Z` when it belongs on this line.
    private var nbmRun: String? {
        guard showsNBM, isAsOfLine, let e = forecast?.extended else { return nil }
        // An old NBM run names its day too (`NBM Tue 13Z`, Spec-Models), unless the whole line is
        // already old and dated.
        let old = AgeTier.compute(fetched: e.fetched, now: now) == .old
        guard old, state != .old else { return e.run }
        let day = TimeFormat.weekdayShort(e.runDate, tz: tz ?? forecast?.timeZone ?? .current)
        return e.run.replacingOccurrences(of: "NBM ", with: "NBM \(day) ")
    }

    /// The NBM run is amber on its own when NBM is stale and the line is not already amber.
    private var nbmAmber: Bool {
        guard let e = forecast?.extended, !isAmber else { return false }
        return AgeTier.compute(fetched: e.fetched, now: now) != .fresh
    }

    public var text: String {
        let base = TrustLine.text(state: state, forecast: forecast, now: now, tz: tz)
        guard isAsOfLine else { return base }
        var line = base
        if let nbmRun { line += " + " + nbmRun }
        if let suffix { line += " · " + suffix }
        return line
    }

    /// The line as styled text: the NBM run may be amber on a secondary line.
    private var styledText: Text {
        let base = TrustLine.text(state: state, forecast: forecast, now: now, tz: tz)
        guard isAsOfLine, let nbmRun else { return Text(text) }
        var t = Text(base + " + ")
        t = t + (nbmAmber
            ? Text(nbmRun).foregroundStyle(Tokens.trustAmber(scheme)).fontWeight(.semibold)
            : Text(nbmRun))
        if let suffix { t = t + Text(" · " + suffix) }
        return t
    }

    /// Amber for stale / old / offline / past horizon; secondary otherwise.
    public var isAmber: Bool { state.isAmber || state == .pastHorizon }

    public var body: some View {
        HStack(spacing: 4) {
            if state == .offlineCached {
                WifiSlash().font(.system(size: compact ? 11 : 12, weight: .semibold))
            }
            if state == .updating {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
            }
            styledText
                .lineLimit(state == .offlineCached || state == .pastHorizon ? 2 : 1)
                .minimumScaleFactor(0.85)
        }
        .font(Tokens.trustFont(watch: compact, amber: isAmber))
        .foregroundStyle(isAmber ? Tokens.trustAmber(scheme) : Tokens.inkSecondary(scheme))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(text))
    }
}
