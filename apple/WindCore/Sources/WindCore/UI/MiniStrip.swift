import SwiftUI

/// Six-hour mini strip for the rectangular complication (HANDOFF §6.3): the shared `WindChart`
/// with the `.next6` window and `.mini` style — bars, gust line, caps and a sun dot; no arrows,
/// ticks or gridlines; past-horizon slots empty.
public struct MiniStrip: View {
    public var forecast: Forecast
    public var now: Date
    public var scheme: ColorScheme

    public init(forecast: Forecast, now: Date, scheme: ColorScheme = .dark) {
        self.forecast = forecast
        self.now = now
        self.scheme = scheme
    }

    public var body: some View {
        let model = ChartModel(forecast: forecast, now: now, window: .next6, scheme: scheme)
        WindChart(model: model, style: .mini)
            .accessibilityLabel(Text("Next 6 hours, gusts to \(model.maxGust) knots"))
    }
}
