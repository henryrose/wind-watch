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

    @Environment(\.colorScheme) private var scheme

    public init(state: TrustState, forecast: Forecast?, now: Date, tz: TimeZone? = nil, compact: Bool = false, suffix: String? = nil) {
        self.state = state
        self.forecast = forecast
        self.now = now
        self.tz = tz
        self.compact = compact
        self.suffix = suffix
    }

    public var text: String {
        let base = TrustLine.text(state: state, forecast: forecast, now: now, tz: tz)
        switch state {
        case .fresh, .stale, .old, .updating:
            if let suffix, forecast != nil { return base + " · " + suffix }
            return base
        default:
            return base
        }
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
            Text(text)
                .lineLimit(state == .offlineCached || state == .pastHorizon ? 2 : 1)
                .minimumScaleFactor(0.85)
        }
        .font(Tokens.trustFont(watch: compact, amber: isAmber))
        .foregroundStyle(isAmber ? Tokens.trustAmber(scheme) : Tokens.inkSecondary(scheme))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(text))
    }
}
