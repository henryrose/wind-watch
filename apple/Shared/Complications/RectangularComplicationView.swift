import SwiftUI
import WidgetKit
import WindCore

/// accessoryRectangular (HANDOFF §7.1): 184×72, plate radius 13. Left column numbers, right
/// column mini strip + trust line. Never the location name.
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

    var body: some View {
        Group {
            if entry.hour != nil {
                HStack(alignment: .top, spacing: 4) {
                    leftColumn
                        .frame(width: 88, alignment: .leading)
                    Spacer(minLength: 0)
                    rightColumn
                }
            } else {
                noForecast
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if showsPlate {
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Tokens.complicationPlate(.dark))
            }
        }
        .containerBackground(for: .widget) { Tokens.complicationPlate(.dark) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let hour = entry.hour {
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text("\(hour.kn)")
                        .font(Tokens.complicationPrimaryFont(circular: false))
                        .foregroundStyle(ink)
                    Text("G\(hour.gust)")
                        .font(Tokens.complicationGustFont(circular: false))
                        .foregroundStyle(ink.opacity(0.9))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 4) {
                    ArrowView(dirFrom: hour.dirFrom, size: 11, color: ink)
                    Text(Compass.fromText(dirFrom: hour.dirFrom))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ink)
                    Text("kn")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(secondary)
                }
                .lineLimit(1)
            }
        }
    }

    /// Past horizon / first run: the dash holds row 1's height so the layout never reflows;
    /// row 2 carries the call to action and the last run.
    private var noForecast: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Capsule()
                    .fill(isTinted ? Color.primary.opacity(0.5) : Tokens.inkDisabled(.dark))
                    .frame(width: 26, height: 5)
                Text(entry.trust == .firstRun ? "No data yet" : "No forecast")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
            }
            .frame(height: 30)
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(entry.trust == .firstRun ? "Open app once" : "Open app to refresh")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(trustText)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let forecast = entry.forecast, entry.hour != nil {
                MiniStrip(forecast: forecast, now: entry.date, scheme: .dark)
                    .frame(width: 75, height: 31)
                    .opacity(isTinted ? 0.9 : 1)
            } else {
                Color.clear.frame(width: 75, height: 31) // keeps the layout from reflowing
            }
            Spacer(minLength: 0)
            Text(trustText)
                .font(.system(size: 10, weight: entry.isAmber ? .semibold : .medium).monospacedDigit())
                .foregroundStyle(ComplicationInk.trust(entry, tinted: isTinted))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var trustText: String {
        switch entry.trust {
        case .pastHorizon: entry.lastRunText
        case .firstRun: "no data yet"
        default: entry.asOfText
        }
    }

    private var accessibility: String {
        guard let hour = entry.hour, let forecast = entry.forecast else {
            return entry.trust == .firstRun ? TrustLine.firstRunText : "No forecast, open app to refresh"
        }
        return Derivations.heroAccessibilityLabel(hour: hour, forecast: forecast)
    }
}
