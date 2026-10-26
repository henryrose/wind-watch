import SwiftUI
import WindCore

extension UserDefaults {
    /// The App Group suite (shared with the watch): settings such as `tempUnit` live here.
    nonisolated(unsafe) static let windShared = AppGroupStore.sharedDefaults(bundleInfo: Bundle.main.infoDictionary ?? [:])
}

/// The two-segment control of the 26 Oct boards: the chart range `48 h | 7 d` (26 pt,
/// `Phone-Main-7d.dc.html`) and the temperature unit `°F | °C` (30 pt, `Phone-About.dc.html`).
/// A `ground` (or `card`) track with a 1 pt `hairline` ring, radius 8, 2 pt padding; the selected
/// segment is a `hairline` plate, radius 6, primary ink; the others secondary. Semibold 13 / 15.
/// Each segment is a 44 pt-tall hit target and reads as a selected button to VoiceOver.
struct SegmentedPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    var label: (Value) -> String
    var spoken: (Value) -> String
    var height: CGFloat = 26
    var minWidth: CGFloat = 44
    var fontSize: CGFloat = 13
    var track: Color?
    var accessibilityName: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(on ? Tokens.inkPrimary(scheme) : Tokens.inkSecondary(scheme))
                        .padding(.horizontal, 8)
                        .frame(minWidth: minWidth, minHeight: height)
                        .background(on ? Tokens.hairline(scheme) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle().inset(by: -(44 - height) / 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(spoken(option))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(track ?? Tokens.ground(scheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous).inset(by: 0.5).stroke(Tokens.hairline(scheme), lineWidth: 1)
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
    }
}

extension SegmentedPicker where Value == ChartRange {
    /// `48 h | 7 d` in the chart title row (26 pt; the landscape header uses a `card` track).
    init(range: Binding<ChartRange>, track: Color? = nil) {
        self.init(options: ChartRange.allCases, selection: range, label: \.label, spoken: \.spoken,
                  minWidth: track == nil ? 44 : 38, track: track, accessibilityName: "Forecast range")
    }
}

extension SegmentedPicker where Value == TemperatureUnit {
    /// `°F | °C` on the About screen (30 pt, 15 pt type).
    init(unit: Binding<TemperatureUnit>) {
        self.init(options: TemperatureUnit.allCases, selection: unit, label: \.symbol,
                  spoken: { $0 == .fahrenheit ? "Fahrenheit" : "Celsius" },
                  height: 30, fontSize: 15, accessibilityName: "Temperature unit")
    }
}
