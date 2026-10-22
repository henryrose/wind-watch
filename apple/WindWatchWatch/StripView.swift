import SwiftUI
import WindCore

/// HANDOFF §7.3 / `Watch-Strip.dc.html`: `Next 12 h` Rounded Bold 13 left, `gusts to 15`
/// Semibold 11 secondary right (7 pt side inset), the 198×115 strip 15 pt below, trust line in
/// the footer. Short horizon: `Next 6 h`, the axis keeps 12 slots, `ends 05:00` at the edge.
/// The page indicator is the system's (`verticalPage`).
struct StripView: View {
    @Environment(ForecastSession.self) private var session

    var body: some View {
        GeometryReader { geo in
            content
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Tokens.groundWatch(.dark))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let forecast = session.forecast, session.trustState.showsNumbers {
                let model = ChartModel(forecast: forecast, now: session.now, window: .next12, scheme: .dark)
                HStack(alignment: .firstTextBaseline) {
                    Text("Next \(hoursRemaining(forecast)) h")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Tokens.inkPrimary(.dark))
                    Spacer()
                    Text("gusts to \(model.maxGust)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Tokens.inkSecondary(.dark))
                }
                .padding(.horizontal, 7)
                WindChart(model: model, style: .watchStrip)
                    .padding(.top, 15)
            } else {
                Text("—")
                    .font(Tokens.gustFont(watch: true))
                    .foregroundStyle(Tokens.inkDisabled(.dark))
                    .padding(.horizontal, 7)
                Text(session.trustState == .firstRun ? "No data yet" : "No forecast")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Tokens.inkSecondary(.dark))
                    .padding(.horizontal, 7)
            }
            Spacer(minLength: 0)
            HStack {
                TrustLineView(state: session.trustState, forecast: session.forecast, now: session.now, compact: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 5)
        .padding(.bottom, 12)
    }

    /// Whole hours left before the horizon, capped at the 12-slot window.
    private func hoursRemaining(_ forecast: Forecast) -> Int {
        let left = Int((forecast.horizon.timeIntervalSince(session.now) / 3600).rounded(.down))
        return min(max(left, 0), 12)
    }
}
