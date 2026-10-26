import SwiftUI

/// Twelve-hour strip for the rectangular complication (HANDOFF §6.3, §7.1 round five): the shared
/// `WindChart` with the `.complication12` window and `.complicationStrip` style — bars, gust line,
/// caps and 3-hourly ticks across the full plate width; past-horizon slots stay empty. The y
/// domain floors at 20 kn and never shrinks within a run.
public struct ComplicationStrip: View {
    public var forecast: Forecast
    public var now: Date
    public var scheme: ColorScheme

    public init(forecast: Forecast, now: Date, scheme: ColorScheme = .dark) {
        self.forecast = forecast
        self.now = now
        self.scheme = scheme
    }

    public var body: some View {
        let model = ChartModel(forecast: forecast, now: now, window: .complication12, scheme: scheme)
        WindChart(model: model, style: .complicationStrip)
            .accessibilityLabel(Text("Next 12 hours, gusts to \(model.maxGust) knots"))
    }
}
