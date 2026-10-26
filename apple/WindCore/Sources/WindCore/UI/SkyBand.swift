import SwiftUI

/// The sky band (§12b, `sky_reference.py`): a 14 pt strip directly above the chart, sharing its
/// x-scale, one cell per 3 hours (NBM blocks in 7 d). Cloud cover < 25 % → `sun` at 22 %;
/// 25–70 % → `ink.secondary` at 28 %; ≥ 70 % → `ink.secondary` at 60 %. Rain hangs 1–3 blue 2 pt
/// ticks from the bottom edge. No icons, text or legend; desaturates with the chart when Old.
/// Draws nothing when the payload has no sky data. Not on the watch.
public struct SkyBand: View {
    public var model: ChartModel
    public var style: ChartStyle

    public static let height: CGFloat = 14

    public init(model: ChartModel, style: ChartStyle) {
        self.model = model
        self.style = style
    }

    public var body: some View {
        if !model.skyCells.isEmpty {
            GeometryReader { geo in
                let g = ChartGeometry(model: model, style: style, width: geo.size.width)
                Canvas(rendersAsynchronously: false) { ctx, _ in
                    draw(g, in: &ctx)
                }
            }
            .frame(height: Self.height)
            .oldStateDesaturation(model.ageTier)
            .accessibilityHidden(true)
        }
    }

    private func draw(_ g: ChartGeometry, in ctx: inout GraphicsContext) {
        let secondary = Tokens.inkSecondary(model.scheme)
        let rainColor = Beaufort.color(step: 2, scheme: model.scheme)
        for cell in model.skyCells {
            let fill: Color
            switch cell.sky {
            case .clear: fill = Tokens.sun(model.scheme).opacity(0.22)
            case .partlyCloudy: fill = secondary.opacity(0.28)
            case .overcast: fill = secondary.opacity(0.6)
            }
            ctx.fill(Path(roundedRect: g.skyRect(cell, bandHeight: Self.height), cornerRadius: 2), with: .color(fill))
            for x in g.rainTickXs(cell) {
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: Self.height - 6))
                tick.addLine(to: CGPoint(x: x, y: Self.height - 1))
                ctx.stroke(tick, with: .color(rainColor), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }
}
