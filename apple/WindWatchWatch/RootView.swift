import SwiftUI
import WindCore

/// Vertical pages: 12-h strip (the launch screen, HANDOFF §6.4d) → Now detail → Settings
/// (§7.2–7.4). `WW_PAGE=strip|now|settings` selects the initial page (screenshots).
enum Page: Hashable {
    case strip
    case now
    case settings
}

struct RootView: View {
    @State private var page: Page

    init() {
        switch ProcessInfo.processInfo.environment["WW_PAGE"] {
        case "now": _page = State(initialValue: .now)
        case "settings": _page = State(initialValue: .settings)
        default: _page = State(initialValue: .strip)
        }
    }

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["WW_PAGE"] == "complications" {
            ComplicationsDebugView()
        } else {
            pages
        }
        #else
        pages
        #endif
    }

    private var pages: some View {
        TabView(selection: $page) {
            StripView().tag(Page.strip)
            NowView().tag(Page.now)
            SettingsView().tag(Page.settings)
        }
        .tabViewStyle(.verticalPage)
        .background(Tokens.groundWatch(.dark))
    }
}
