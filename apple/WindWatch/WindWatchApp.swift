import SwiftUI
import WindCore

@main
struct WindWatchApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(model)
                .transformEnvironment(\.dynamicTypeSize) { size in
                    if let forced = model.typeSizeOverride { size = forced }
                }
                .task {
                    // One-minute clock so the trust line flips without a fetch.
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(60))
                        model.tick()
                    }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        Task { await model.refreshIfNeeded() }
                    }
                }
        }
    }
}
