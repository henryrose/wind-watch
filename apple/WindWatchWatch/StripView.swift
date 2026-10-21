import SwiftUI
import WindCore

/// HANDOFF §7.3: `Next 12 h` header, 12-slot chart, trust line footer.
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
        VStack(alignment: .leading, spacing: 4) {
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
                WindChart(model: model, style: .watch)
                    .frame(height: 115)
            } else {
                Text("—")
                    .font(Tokens.gustFont(watch: true))
                    .foregroundStyle(Tokens.inkDisabled(.dark))
                Text(session.trustState == .firstRun ? "No data yet" : "No forecast")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Tokens.inkSecondary(.dark))
            }
            Spacer(minLength: 0)
            HStack {
                TrustLineView(state: session.trustState, forecast: session.forecast, now: session.now, compact: true)
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
    }

    /// Whole hours left before the horizon, capped at the 12-slot window.
    private func hoursRemaining(_ forecast: Forecast) -> Int {
        let left = Int((forecast.horizon.timeIntervalSince(session.now) / 3600).rounded(.down))
        return min(max(left, 0), 12)
    }
}
