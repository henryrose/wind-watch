import SwiftUI
import WidgetKit
import WindCore

/// accessoryCorner (HANDOFF §7.1): inner label sustained 20 / arrow 8 / `G25` 9; outer gauge
/// (`widgetLabel`) over B0–7 in the ramp colours, dot at the value, B8+ pinned at the end.
/// Stale/old: the gauge is a single amber (dashing is not available on a corner `Gauge`).
struct CornerComplicationView: View {
    let entry: WindEntry
    var tinted: Bool? = nil

    @Environment(\.widgetRenderingMode) private var mode
    private var isTinted: Bool { tinted ?? (mode != .fullColor) }
    private var ink: Color { ComplicationInk.number(entry, tinted: isTinted) }
    private var step: Int { entry.hour.map { Beaufort.step(kn: $0.kn) } ?? 0 }

    var body: some View {
        innerLabel
            .widgetLabel { gauge }
            .containerBackground(for: .widget) { Color.clear }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibility)
    }

    var innerLabel: some View {
        VStack(spacing: 1) {
            if let hour = entry.hour {
                Text("\(min(hour.kn, 99))")
                    .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(ink)
                ArrowView(dirFrom: hour.dirFrom, size: 8, color: ink)
                    .widgetAccentable()
                Text("G\(hour.gust)")
                    .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(ink.opacity(0.85))
            } else {
                Text("—")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(isTinted ? Color.primary.opacity(0.5) : Tokens.inkDisabled(.dark))
                Text("open app")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(ComplicationInk.secondary(isTinted))
            }
        }
        .lineLimit(1)
    }

    /// The outer gauge. WidgetKit draws `widgetLabel` gauges on the corner's arc itself; only
    /// `accessoryLinear`-family styles are honoured there, so the eight ramp steps are expressed
    /// as a gradient tint rather than discrete segments.
    var gauge: some View {
        Gauge(value: entry.hour == nil ? 0 : Double(min(step, 8)), in: 0...8) { EmptyView() }
            .gaugeStyle(.accessoryLinear)
            .tint(gaugeTint)
            .widgetAccentable()
    }

    private var gaugeTint: AnyShapeStyle {
        if entry.hour == nil { return AnyShapeStyle(Color.white.opacity(0.18)) }
        if isTinted { return AnyShapeStyle(Color.primary) }
        if entry.isAmber { return AnyShapeStyle(Tokens.trustAmber(.dark)) }
        return AnyShapeStyle(Gradient(colors: ComplicationInk.rampB0to7))
    }

    private var accessibility: String {
        guard let hour = entry.hour, let forecast = entry.forecast else { return "No forecast, open app" }
        return Derivations.heroAccessibilityLabel(hour: hour, forecast: forecast)
    }
}
