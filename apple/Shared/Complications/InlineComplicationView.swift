import SwiftUI
import WidgetKit
import WindCore

/// accessoryInline (HANDOFF §7.1, §3 inline rule): 8-point arrow + `15 G25 kn`, with `· 13:05`
/// when stale and `· Tue 13:05` when old; `Wind — open app` past the horizon.
struct InlineComplicationView: View {
    let entry: WindEntry

    var text: String {
        TrustLine.inlineText(state: entry.trust, hero: entry.hour, forecast: entry.forecast, now: entry.date)
    }

    var symbol: String {
        entry.hour.map { Compass.arrowSymbolName(dirFrom: $0.dirFrom) } ?? "wind"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text)
                .font(.system(.body, design: .rounded, weight: .semibold).monospacedDigit())
        }
        .containerBackground(for: .widget) { Color.clear }
        .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        guard let hour = entry.hour, let forecast = entry.forecast else { return "No forecast, open app" }
        return Derivations.heroAccessibilityLabel(hour: hour, forecast: forecast)
    }
}
