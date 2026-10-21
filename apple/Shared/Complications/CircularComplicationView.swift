import SwiftUI
import WidgetKit
import WindCore

/// accessoryCircular (HANDOFF §7.1): Beaufort ring, arrow at 10.5 pt from the top, the number
/// centred in a fixed 22×17 frame, `G25` 3.5 pt from the bottom. Stale/old: amber dashed ring.
struct CircularComplicationView: View {
    let entry: WindEntry
    var tinted: Bool? = nil

    @Environment(\.widgetRenderingMode) private var mode
    private var isTinted: Bool { tinted ?? (mode != .fullColor) }
    private var ink: Color { ComplicationInk.number(entry, tinted: isTinted) }
    private var step: Int { entry.hour.map { Beaufort.step(kn: $0.kn) } ?? 0 }
    private var dashed: Bool { entry.isAmber }

    private var ringColor: Color {
        if isTinted { return .primary }
        if entry.isAmber { return Tokens.trustAmber(.dark) }
        return Beaufort.color(step: step, scheme: .dark)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(isTinted ? Color.primary.opacity(0.18) : Color.white.opacity(0.18), lineWidth: 3)
            if entry.hour != nil {
                Circle()
                    .trim(from: 0, to: CGFloat(min(step, 12)) / 12)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: dashed ? [7, 6] : []))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
            if let hour = entry.hour {
                ArrowView(dirFrom: hour.dirFrom, size: 7, color: ink)
                    .widgetAccentable()
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 7) // centre at 10.5 pt from the top
                Text("\(min(hour.kn, 99))")
                    .font(Tokens.complicationPrimaryFont(circular: true))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: 22, height: 17) // fixed: two tabular digits never move the arrow or gust
                Text("G\(hour.gust)")
                    .font(Tokens.complicationGustFont(circular: true))
                    .foregroundStyle(ink.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 3.5)
            } else {
                Text("—")
                    .font(Tokens.complicationPrimaryFont(circular: true))
                    .foregroundStyle(isTinted ? Color.primary.opacity(0.5) : Tokens.inkDisabled(.dark))
                    .frame(width: 22, height: 17)
                Text("open app")
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .foregroundStyle(ComplicationInk.secondary(isTinted))
                    .lineLimit(1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 4)
            }
        }
        .padding(1.5)
        .opacity(entry.tier == .old && entry.hour != nil ? (isTinted ? 0.6 : 0.72) : 1)
        .containerBackground(for: .widget) { Color.clear }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        guard let hour = entry.hour, let forecast = entry.forecast else { return "No forecast, open app" }
        return Derivations.heroAccessibilityLabel(hour: hour, forecast: forecast)
    }
}
