import SwiftUI
import WindCore

/// Vertical pages: Now → 12-h strip → Settings (HANDOFF §7.2–7.4).
/// `WW_PAGE=now|strip|settings` selects the initial page (screenshots).
enum Page: Hashable {
    case now
    case strip
    case settings
}

struct RootView: View {
    @State private var page: Page

    init() {
        switch ProcessInfo.processInfo.environment["WW_PAGE"] {
        case "strip": _page = State(initialValue: .strip)
        case "settings": _page = State(initialValue: .settings)
        default: _page = State(initialValue: .now)
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
            NowView().tag(Page.now)
            StripView().tag(Page.strip)
            SettingsView().tag(Page.settings)
        }
        .tabViewStyle(.verticalPage)
        .background(Tokens.groundWatch(.dark))
    }
}
