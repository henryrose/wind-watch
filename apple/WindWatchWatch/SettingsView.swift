import SwiftUI
import WindCore

/// HANDOFF §7.4 / `Watch-Settings.dc.html`: `Location` Rounded Bold 13 (4 pt side inset), two
/// full-width buttons (44 pt min, radius 12, plates 14 % / 8 % white, padding 0 10) with a
/// two-line label (name Semibold 14 · sub Regular 10 secondary), a filled blue check on the
/// selected row and an empty ring on the other, then `Weather data by Open-Meteo.com`
/// Regular 10 secondary. Nothing else.
struct SettingsView: View {
    @Environment(ForecastSession.self) private var session

    private var custom: SavedLocation? { session.preferences.custom }
    private var usingCustom: Bool { session.preferences.effectiveUseCustom }

    var body: some View {
        GeometryReader { geo in
            content
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Tokens.groundWatch(.dark))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Tokens.inkPrimary(.dark))
                .padding(.horizontal, 4)
            VStack(spacing: 5) {
                plate(
                    name: SavedLocation.portTownsendBay.name, sub: "default",
                    selected: !usingCustom, enabled: true, action: session.selectDefault
                )
                .accessibilityLabel("Default location, \(SavedLocation.portTownsendBay.name)")
                .accessibilityAddTraits(usingCustom ? [] : .isSelected)
                plate(
                    name: custom?.name ?? "No custom location",
                    sub: custom == nil ? "set it on iPhone" : "set on iPhone",
                    selected: usingCustom, enabled: custom != nil, action: session.selectCustom
                )
                .accessibilityLabel(custom.map { "Custom location, \($0.name)" } ?? "No custom location, set it on iPhone")
                .accessibilityAddTraits(usingCustom ? .isSelected : [])
            }
            Spacer(minLength: 0)
            Text("Weather data by Open-Meteo.com")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Tokens.inkSecondary(.dark))
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
    }

    private func plate(name: String, sub: String, selected: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(enabled ? Tokens.inkPrimary(.dark) : Tokens.inkDisabled(.dark))
                    Text(sub)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(enabled ? Tokens.inkSecondary(.dark) : Tokens.inkDisabled(.dark))
                }
                .lineLimit(1)
                .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                mark(selected: selected)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.white.opacity(selected ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// Selected: `checkmark.circle.fill`, black check on the default blue (`bft.2`).
    /// Unselected: `circle` in `ink.secondary`. 14 pt.
    @ViewBuilder
    private func mark(selected: Bool) -> some View {
        if selected {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Tokens.groundWatch(.dark), Beaufort.color(step: 2, scheme: .dark))
                .font(.system(size: 14, weight: .bold))
        } else {
            Image(systemName: "circle")
                .foregroundStyle(Tokens.inkSecondary(.dark))
                .font(.system(size: 14, weight: .medium))
        }
    }
}
