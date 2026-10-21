import SwiftUI
import WindCore

/// D1 placeholder: proves the target links WindCore and the pipeline runs. Replaced in D3.
struct ContentView: View {
    private var forecast: Forecast { PreviewData.forecast }
    private var hero: Forecast.Hour? { forecast.hero(at: PreviewData.now) }
    private var usesFixture: Bool { ProcessInfo.processInfo.environment["WW_FIXTURE"] == "1" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(forecast.location.name)
                .font(Tokens.locationFont(watch: true))
                .foregroundStyle(Tokens.inkSecondary(.dark))
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(hero?.kn ?? 0)")
                    .font(Tokens.heroFont(watch: true))
                    .tracking(Tokens.heroTracking(watch: true))
                Text("kn")
                    .font(Tokens.heroUnitFont(watch: true))
                    .foregroundStyle(Tokens.inkSecondary(.dark))
            }
            HStack(spacing: 5) {
                ArrowView(dirFrom: hero?.dirFrom ?? 0, size: 18, color: Tokens.inkPrimary(.dark))
                Text(Compass.fromText(dirFrom: hero?.dirFrom ?? 0))
                    .font(Tokens.directionFont(watch: true))
            }
            Text(forecast.summary)
                .font(Tokens.summaryFont(watch: true))
                .foregroundStyle(Tokens.inkBody(.dark))
                .lineLimit(2)
            Spacer()
            TrustLineView(state: .fresh, forecast: forecast, now: PreviewData.now, compact: true)
            Text(usesFixture ? "fixture mode" : "placeholder (D1)")
                .font(.system(size: 9))
                .foregroundStyle(Tokens.inkSecondary(.dark))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.groundWatch(.dark))
    }
}

#Preview {
    ContentView()
}
