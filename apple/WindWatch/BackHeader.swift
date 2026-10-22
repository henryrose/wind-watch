import SwiftUI
import WindCore

/// Pushed-screen header (`Phone-Location.dc.html`, `Phone-About.dc.html`): a 44 pt back chevron
/// (pulled 12 pt into the gutter) and the Bold 28 title on one line, or a custom title view
/// (About uses the brand lockup, HANDOFF §10a).
struct BackHeader<Title: View>: View {
    @ViewBuilder let title: () -> Title

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
            title()
        }
        .padding(.top, 8)
    }
}

extension BackHeader where Title == BackHeaderTitle {
    init(title: String) {
        self.init { BackHeaderTitle(text: title) }
    }
}

struct BackHeaderTitle: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(Tokens.inkPrimary(scheme))
    }
}
