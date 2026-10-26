import SwiftUI
import WidgetKit
import WindCore

@main
struct WindWatchApp: App {
    @State private var model: ForecastSession
    @State private var sync: LocationSync
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let session = ForecastSession(bundleInfo: Bundle.main.infoDictionary ?? [:])
        let sync = LocationSync(session: session)
        #if DEBUG
        // `WW_SAVE_CUSTOM="Name,lat,lon"`: add and select a location at launch (sync tests).
        if let spec = ProcessInfo.processInfo.environment["WW_SAVE_CUSTOM"] {
            let parts = spec.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 3, let lat = Double(parts[1]), let lon = Double(parts[2]) {
                session.addLocation(SavedLocation(name: parts[0], lat: lat, lon: lon, tz: TimeZone.current.identifier))
            }
        }
        #endif
        _model = State(initialValue: session)
        _sync = State(initialValue: sync)
    }

    var body: some Scene {
        WindowGroup {
            // First launch: choose the location before the forecast (`WelcomeView`). A root swap,
            // not a cover presented at launch, which can leave a blank window on device.
            Group {
                if model.needsWelcome {
                    WelcomeView()
                } else {
                    MainView()
                }
            }
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
                        Task {
                            if await model.refreshIfNeeded() {
                                WidgetCenter.shared.reloadAllTimelines()
                            }
                        }
                        #if DEBUG
                        // `WW_LANDSCAPE=1` rotates the scene for landscape screenshots in a headless simulator.
                        if ProcessInfo.processInfo.environment["WW_LANDSCAPE"] != nil,
                           let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                        }
                        #endif
                    }
                }
        }
    }
}
