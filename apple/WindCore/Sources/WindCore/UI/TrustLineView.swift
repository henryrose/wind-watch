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

    @Environment(\.colorScheme) private var scheme

    public init(state: TrustState, forecast: Forecast?, now: Date, tz: TimeZone? = nil, compact: Bool = false) {
        self.state = state
        self.forecast = forecast
        self.now = now
        self.tz = tz
        self.compact = compact
    }

    public var text: String {
        TrustLine.text(state: state, forecast: forecast, now: now, tz: tz)
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
                .lineLimit(state == .offlineCached ? 2 : 1)
                .minimumScaleFactor(0.85)
        }
        .font(Tokens.trustFont(watch: compact, amber: isAmber))
        .foregroundStyle(isAmber ? Tokens.trustAmber(scheme) : Tokens.inkSecondary(scheme))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(text))
    }
}
