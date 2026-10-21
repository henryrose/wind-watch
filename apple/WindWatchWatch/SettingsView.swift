import SwiftUI
import WindCore

/// HANDOFF §7.4: `Location`, two full-width buttons, attribution. Nothing else.
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
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Tokens.inkPrimary(.dark))
            plate(selected: !usingCustom, enabled: true, action: session.selectDefault) {
                Text("\(SavedLocation.portTownsendBay.name) · default")
            }
            .accessibilityLabel("Default location, \(SavedLocation.portTownsendBay.name)")
            .accessibilityAddTraits(usingCustom ? [] : .isSelected)
            plate(selected: usingCustom, enabled: custom != nil, action: session.selectCustom) {
                if let custom {
                    Text("\(custom.name) · set on iPhone")
                } else {
                    Text("No custom location")
                }
            }
            .accessibilityLabel(custom.map { "Custom location, \($0.name)" } ?? "No custom location")
            .accessibilityAddTraits(usingCustom ? .isSelected : [])
            Spacer(minLength: 0)
            Text("Weather data by Open-Meteo.com")
                .font(.system(size: 10))
                .foregroundStyle(Tokens.inkSecondary(.dark))
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
    }

    private func plate<Label: View>(selected: Bool, enabled: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                label()
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(enabled ? Tokens.inkPrimary(.dark) : Tokens.inkDisabled(.dark))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? Tokens.trustAmber(.dark) : Tokens.inkDisabled(.dark))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.white.opacity(selected ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
