import SwiftUI

/// Twelve-hour strip for the rectangular complication (HANDOFF §6.3, §7.1): the shared `WindChart`
/// with the `.complication` window and style — bars, gust line, caps and 3-hour ticks; no shading,
/// sun markers, arrows, labels or gridlines; past-horizon slots empty. Fills the height it is given
/// (29 pt at 46 mm, ~25 pt at 42 mm).
public struct MiniStrip: View {
    public var forecast: Forecast
    public var now: Date
    public var scheme: ColorScheme
    /// The grow-only domain for this timeline entry (`TimelineBuilder.stripDomains`); nil uses the
    /// window's own.
    public var yMaxFloor: Int?

    public init(forecast: Forecast, now: Date, scheme: ColorScheme = .dark, yMaxFloor: Int? = nil) {
        self.forecast = forecast
        self.now = now
        self.scheme = scheme
        self.yMaxFloor = yMaxFloor
    }

    public var body: some View {
        let model = ChartModel(forecast: forecast, now: now, window: .complication, scheme: scheme, yMaxFloor: yMaxFloor)
        GeometryReader { geo in
            WindChart(model: model, style: .complication(height: geo.size.height))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Next 12 hours, gusts to \(model.maxGust) knots"))
    }
}
