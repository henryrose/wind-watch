import SwiftUI
import WidgetKit
import WindCore

/// accessoryRectangular (HANDOFF §7.1 rounds four–five, `Comp-Rectangular.png`): 184×72 pt plate,
/// radius 13, padding 6/8/5/8.
/// - Row 1 (25 pt, one line): sustained Rounded Heavy 23 · `G25` Rounded Bold 11 at 90 % ink ·
///   arrow 9 + `from W` Semibold 9 · flexible space · trust text Medium 11, never smaller and
///   never dropped. No `kn`. When the row doesn't fit (`ViewThatFits`, in order): bare arrow →
///   no `G` prefix → 20 pt number. On 41/42 mm the bare arrow is the normal state.
/// - Row 2, 3 pt below: the 12-hour strip, full plate width (§6.3).
/// - Past horizon / first run: `—` + `No forecast` + run label; row 2 becomes a dashed box with
///   `Open app to refresh`.
/// Never the location name.
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
        VStack(alignment: .leading, spacing: 3) {
            if let hour = entry.hour, let forecast = entry.forecast {
                numbersRow(hour)
                    .frame(height: 25)
                ComplicationStrip(forecast: forecast, now: entry.date, scheme: .dark)
                    .frame(height: 31)
                    .opacity(isTinted ? 0.9 : 1)
            } else {
                noForecastRow
                    .frame(height: 25)
                callToAction
                    .frame(height: 31)
            }
        }
        .padding(EdgeInsets(top: 6, leading: 8, bottom: 5, trailing: 8))
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

    // MARK: Row 1

    /// The four fallbacks in §7.1 order; the trust text is identical in every one.
    private func numbersRow(_ hour: Forecast.Hour) -> some View {
        ViewThatFits(in: .horizontal) {
            numbers(hour, size: 23, gPrefix: true, fromText: true)
            numbers(hour, size: 23, gPrefix: true, fromText: false)
            numbers(hour, size: 23, gPrefix: false, fromText: false)
            numbers(hour, size: 20, gPrefix: false, fromText: false)
        }
    }

    private func numbers(_ hour: Forecast.Hour, size: CGFloat, gPrefix: Bool, fromText: Bool) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text("\(hour.kn)")
                .font(.system(size: size, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(ink)
            Text(gPrefix ? "G\(hour.gust)" : "\(hour.gust)")
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(ink.opacity(0.9))
                .padding(.leading, 4)
            HStack(spacing: 2) {
                ArrowView(dirFrom: hour.dirFrom, size: 9, color: ink)
                if fromText {
                    Text(Compass.fromText(dirFrom: hour.dirFrom))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ink)
                }
            }
            .padding(.leading, 4)
            .alignmentGuide(.lastTextBaseline) { d in d[.bottom] - 1 }
            Spacer(minLength: 6)
            trustLabel
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// `as of 23:30` (Medium 11 secondary); Semibold amber when stale / offline / old.
    private var trustLabel: some View {
        Text(trustText)
            .font(.system(size: 11, weight: entry.isAmber ? .semibold : .medium).monospacedDigit())
            .foregroundStyle(ComplicationInk.trust(entry, tinted: isTinted))
            .lineLimit(1)
            .fixedSize()
    }

    /// `as of 23:30`, stale `as of 13:05`, old `Tue 13:05` (§7.1: the day replaces "as of").
    private var trustText: String {
        guard let forecast = entry.forecast else { return "" }
        if entry.tier == .old { return TimeFormat.weekdayHHMM(forecast.fetched, tz: entry.timeZone) }
        return entry.asOfText
    }

    // MARK: Past horizon / first run

    private var noForecastRow: some View {
        HStack(alignment: .center, spacing: 6) {
            Capsule()
                .fill(isTinted ? Color.primary.opacity(0.5) : Tokens.inkDisabled(.dark))
                .frame(width: 16, height: 4)
            Text(entry.trust == .firstRun ? "No data yet" : "No forecast")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(secondary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            if entry.trust != .firstRun {
                Text(entry.runShortText)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// Row 2 when there is nothing to plot: a 1 pt dashed rounded box with the call to action.
    private var callToAction: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            .overlay {
                Text(entry.trust == .firstRun ? "Open app once" : "Open app to refresh")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
            }
    }

    private var accessibility: String {
        guard let hour = entry.hour, let forecast = entry.forecast else {
            return entry.trust == .firstRun ? TrustLine.firstRunText : "No forecast, open app to refresh"
        }
        return Derivations.heroAccessibilityLabel(hour: hour, forecast: forecast)
    }
}
