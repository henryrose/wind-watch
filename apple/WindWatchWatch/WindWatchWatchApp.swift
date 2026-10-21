import SwiftUI
import WidgetKit
import WindCore

@main
struct WindWatchWatchApp: App {
    @State private var session: ForecastSession
    @State private var sync: LocationSync
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let session = ForecastSession(bundleInfo: Bundle.main.infoDictionary ?? [:])
        _session = State(initialValue: session)
        _sync = State(initialValue: LocationSync(session: session))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task {
                    // One-minute clock so the trust line flips without a fetch.
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(60))
                        session.tick()
                    }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        Task {
                            if await session.refreshIfNeeded() {
                                WidgetCenter.shared.reloadAllTimelines()
                            }
                        }
                    }
                }
        }
    }
}
