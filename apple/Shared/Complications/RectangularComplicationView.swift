import SwiftUI
import WidgetKit
import WindCore

/// accessoryRectangular (HANDOFF §7.1, `Comp-Rectangular`): 184×72 at 46 mm, ≈166×65 at 42 mm,
/// plate radius 13, padding 6/8/5/8. Row 1 (25 pt): numbers, direction and the trust text; row 2,
/// 3 pt below: the 12-hour strip, full plate width. Never the location name.
struct RectangularComplicationView: View {
    let entry: WindEntry
    /// Override for the DEBUG page; nil reads `widgetRenderingMode`.
    var tinted: Bool? = nil
    /// Draw the plate explicitly (outside WidgetKit `containerBackground` is ignored).
    var showsPlate = false

    @Environment(\.widgetRenderingMode) private var mode
    private var isTinted: Bool { tinted ?? (mode != .fullColor) }
    private var ink: Color { ComplicationInk.number(entry, tinted: isTinted) }
    private var secondary: Color { ComplicationInk.secondary(isTinted) }
    private var disabled: Color { isTinted ? Color.primary.opacity(0.5) : Tokens.inkDisabled(.dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let hour = entry.hour, let forecast = entry.forecast {
                // Row 1 when it doesn't fit, in order (§7.1): drop `from W` and keep the bare arrow →
                // drop the `G` prefix → number 20 pt. The trust text is never removed or shrunk; on
                // 41/42 mm the first fallback is the normal state.
                ViewThatFits(in: .horizontal) {
                    numbersRow(hour, fromText: true, gustPrefix: true, numberSize: 23)
                    numbersRow(hour, fromText: false, gustPrefix: true, numberSize: 23)
                    numbersRow(hour, fromText: false, gustPrefix: false, numberSize: 23)
                    numbersRow(hour, fromText: false, gustPrefix: false, numberSize: 20)
                }
                .frame(height: 25)
                MiniStrip(forecast: forecast, now: entry.date, scheme: .dark, yMaxFloor: entry.stripYMax)
                    .opacity(isTinted ? 0.9 : 1)
            } else {
                noForecast
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 8)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if showsPlate {
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Tokens.complicationPlate(.dark))
            }
        }
        .containerBackground(for: .widget) { Tokens.complicationPlate(.dark) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    /// Sustained Rounded Heavy · `G25` Rounded Bold 11 at 90 % · arrow 9 + `from W` Semibold 9 ·
    /// spacer · trust text Medium 11 (Semibold amber when stale/old). No `kn`. Proportional digits
    /// and 3–4 pt gaps: the full row is ~167 pt for `15 G25 from W as of 23:30`, inside the 168 pt
    /// of a 46 mm plate.
    private func numbersRow(_ hour: Forecast.Hour, fromText: Bool, gustPrefix: Bool, numberSize: CGFloat) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text("\(hour.kn)")
                .font(.system(size: numberSize, weight: .heavy, design: .rounded))
                .tracking(-0.02 * numberSize)
                .foregroundStyle(ink)
                .padding(.trailing, 3)
            Text(gustPrefix ? "G\(hour.gust)" : "\(hour.gust)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(ink.opacity(0.9))
                .padding(.trailing, 4)
            HStack(alignment: .center, spacing: 2.5) {
                ArrowView(dirFrom: hour.dirFrom, size: 9, color: ink)
                if fromText {
                    Text(Compass.fromText(dirFrom: hour.dirFrom))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ink)
                }
            }
            .alignmentGuide(.lastTextBaseline) { $0[VerticalAlignment.center] + 3.5 }
            Spacer(minLength: 4)
            trustLabel(entry.asOfText, color: ComplicationInk.trust(entry, tinted: isTinted), amber: entry.isAmber)
        }
        .lineLimit(1)
    }

    /// Never shrunk, never truncated: 11 pt is the floor (§7.1).
    private func trustLabel(_ text: String, color: Color, amber: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: amber ? .semibold : .medium).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .layoutPriority(1)
    }

    /// Past horizon / first run: `—` + `No forecast` + the last run on row 1; the strip slot becomes
    /// a 1 pt dashed box with the call to action, so the layout never reflows.
    private var noForecast: some View {
        Group {
            // The dash is the em dash of the 23 pt number (23 × 4 pt) but gives way first, so
            // `No forecast` and the run label fit a 42 mm plate untruncated.
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                // Zero-width 23 pt strut: the same baseline as the numbers row.
                Text("0").font(.system(size: 23, weight: .heavy, design: .rounded)).hidden().frame(width: 0)
                    .padding(.trailing, -5)
                Capsule()
                    .fill(disabled)
                    .frame(minWidth: 12, maxWidth: 23)
                    .frame(height: 4)
                    .layoutPriority(1)
                    .alignmentGuide(.lastTextBaseline) { $0[VerticalAlignment.center] + 5.5 }
                Text(entry.trust == .firstRun ? "No data yet" : "No forecast")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(secondary)
                    .fixedSize()
                Spacer(minLength: 0)
                if entry.trust != .firstRun {
                    trustLabel(entry.lastRunText, color: disabled, amber: false)
                }
            }
            .lineLimit(1)
            .frame(height: 25)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(isTinted ? Color.primary.opacity(0.3) : Color.white.opacity(0.18),
                              style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .overlay {
                    Text(entry.trust == .firstRun ? "Open app once" : "Open app to refresh")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
        }
    }

    private var accessibility: String {
        guard let hour = entry.hour, let forecast = entry.forecast else {
            return entry.trust == .firstRun ? TrustLine.firstRunText : "No forecast, open app to refresh"
        }
        return Derivations.heroAccessibilityLabel(hour: hour, forecast: forecast)
    }
}
