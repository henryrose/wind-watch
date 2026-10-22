import SwiftUI
import WindCore

/// Pushed-screen header (`Phone-Location.dc.html`, `Phone-About.dc.html`): a 44 pt back chevron
/// (pulled 12 pt into the gutter) and the Bold 28 title on one line.
struct BackHeader: View {
    let title: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Tokens.inkPrimary(scheme))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -12)
            .accessibilityLabel("Back")
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Tokens.inkPrimary(scheme))
        }
        .padding(.top, 8)
    }
}
