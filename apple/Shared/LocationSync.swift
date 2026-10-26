import Foundation
import WatchConnectivity
import WidgetKit
import WindCore

/// Phone → watch sync of the location list over `WCSession` application context (DESIGN §7,
/// HANDOFF §8.3).
///
/// The iPhone is the editor: every local change (add, rename, select, delete, reorder) pushes the
/// whole list plus the selected id as `LocationSettings.applicationContext`, and the latest context
/// is re-sent on activation so a newly paired watch catches up. The watch applies whatever arrives
/// (list, order and selection), so the phone wins over a row picked on the wrist; the watch
/// Settings list still switches locally between contexts. Compiled into the two apps only; the
/// widget extension reads the shared defaults instead.
@MainActor
final class LocationSync: NSObject, WCSessionDelegate {
    private let session: ForecastSession
    private let wc: WCSession?

    init(session: ForecastSession) {
        self.session = session
        self.wc = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        guard let wc else { return }
        wc.delegate = self
        wc.activate()
        #if os(iOS)
        session.onPreferencesChanged = { [weak self] prefs in self?.push(prefs) }
        #endif
    }

    #if os(iOS)
    /// Sends the preference to the watch; silently a no-op until the session is activated.
    func push(_ prefs: LocationSettings.Preferences) {
        guard let wc, wc.activationState == .activated else { return }
        try? wc.updateApplicationContext(LocationSettings.applicationContext(prefs))
    }
    #endif

    /// Watch side: persist, reload, and refetch when the active location changed.
    private func apply(_ prefs: LocationSettings.Preferences) {
        LocationSettings.save(prefs, to: session.defaults)
        guard session.reloadPreferences() else { return }
        Task {
            if await session.refreshIfNeeded(force: true) {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    // MARK: - WCSessionDelegate (called off the main actor; decode first, then hop)

    nonisolated func session(_ wcSession: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        guard state == .activated else { return }
        #if os(iOS)
        Task { @MainActor in self.push(self.session.preferences) }
        #else
        let received = wcSession.receivedApplicationContext
        guard !received.isEmpty else { return }
        let prefs = LocationSettings.preferences(fromApplicationContext: received)
        Task { @MainActor in self.apply(prefs) }
        #endif
    }

    nonisolated func session(_ wcSession: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        #if os(watchOS)
        let prefs = LocationSettings.preferences(fromApplicationContext: applicationContext)
        Task { @MainActor in self.apply(prefs) }
        #endif
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ wcSession: WCSession) {}

    nonisolated func sessionDidDeactivate(_ wcSession: WCSession) {
        wcSession.activate() // a different watch was paired; re-activate for it
    }
    #endif
}
