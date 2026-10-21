import SwiftUI
import WindCore

/// D1 placeholder: proves the target links WindCore and the pipeline runs. Replaced in D2.
struct ContentView: View {
    @Environment(\.colorScheme) private var scheme

    private var forecast: Forecast { PreviewData.forecast }
    private var usesFixture: Bool { ProcessInfo.processInfo.environment["WW_FIXTURE"] == "1" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(forecast.location.name)
                .font(Tokens.locationFont(watch: false))
            TrustLineView(state: .fresh, forecast: forecast, now: PreviewData.now)
            Text(forecast.summary)
                .font(Tokens.summaryFont(watch: false))
                .foregroundStyle(Tokens.inkBody(scheme))
            WindChart(model: ChartModel(forecast: forecast, now: PreviewData.now, window: .all, scheme: scheme), style: .phone)
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
                .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(usesFixture ? "fixture mode" : "placeholder (D1)")
                .font(.caption)
                .foregroundStyle(Tokens.inkSecondary(scheme))
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.ground(scheme))
    }
}

#Preview {
    ContentView()
}
