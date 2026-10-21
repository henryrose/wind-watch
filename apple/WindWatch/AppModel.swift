import Foundation
import Observation
import SwiftUI
import WidgetKit
import WindCore

/// App state: the cached payload, the clock, the trust state, and the location preference.
/// First paint is synchronous from `AppGroupStore.load()`; the network is only touched from
/// `refreshIfNeeded()`.
@MainActor
@Observable
final class AppModel {
    enum Screen: Hashable {
        case location
        case about
    }

    private(set) var cached: Cached?
    private(set) var forecast: Forecast?
    private(set) var now: Date
    private(set) var isUpdating = false
    private(set) var preferences: LocationSettings.Preferences
    var path: [Screen] = []
    /// `WW_TYPE_SIZE=ax1…ax5|xl|xxl|xxxl` forces a Dynamic Type size (screenshots).
    private(set) var typeSizeOverride: DynamicTypeSize?

    let store: AppGroupStore
    let client: WindClient?
    let defaults: UserDefaults
    let groupID: String
    /// `WW_FIXTURE=1`: reference payload, no network.
    let isFixture: Bool
    private let pinnedNow: Date?

    /// Minimum gap between checks while the app is in the foreground.
    static let foregroundMinInterval: TimeInterval = 10 * 60

    init() {
        let env = ProcessInfo.processInfo.environment
        let info = Bundle.main.infoDictionary ?? [:]
        let prefix = (info["WWBundlePrefix"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "com.example"
        groupID = AppGroupStore.groupID(bundlePrefix: prefix)
        defaults = UserDefaults(suiteName: groupID) ?? .standard
        isFixture = env["WW_FIXTURE"] == "1"
        pinnedNow = env["WW_NOW"].flatMap { ISO8601DateFormatter().date(from: $0) }
        now = pinnedNow ?? .now
        preferences = LocationSettings.load(from: defaults)

        if isFixture {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("WindWatchFixture-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            store = AppGroupStore(directory: dir)
            client = nil
        } else {
            store = AppGroupStore(groupID: groupID)
            if let base = info["WWAPIBase"] as? String, let url = URL(string: base), url.host() != nil {
                client = WindClient(baseURL: url)
            } else {
                client = nil
            }
        }

        if isFixture {
            applyFixture(state: env["WW_STATE"])
        } else {
            setCached(store.load())
        }
        if let pinnedNow { now = pinnedNow }
        typeSizeOverride = Self.typeSize(env["WW_TYPE_SIZE"])

        switch env["WW_SCREEN"] {
        case "location": path = [.location]
        case "about": path = [.about]
        default: break
        }
    }

    // MARK: - Derived

    var trustState: TrustState {
        TrustState.compute(forecast: forecast, now: now, lastCheckOK: cached?.meta.lastCheckOK ?? true, isUpdating: isUpdating)
    }

    var ageTier: AgeTier {
        forecast.map { AgeTier.compute(fetched: $0.fetched, now: now) } ?? .fresh
    }

    var hero: Forecast.Hour? {
        guard let forecast, trustState.showsNumbers else { return nil }
        return forecast.hero(at: now)
    }

    var locationName: String {
        if preferences.effectiveUseCustom, let custom = preferences.custom { return custom.name }
        return forecast?.location.name ?? SavedLocation.portTownsendBay.name
    }

    var canReachNetwork: Bool { client != nil && !isFixture }

    // MARK: - Clock and refresh

    /// Advances the clock. Pinned (`WW_NOW`) and fixture clocks stay put so screenshots are stable.
    func tick() {
        if let pinnedNow {
            now = pinnedNow
        } else if !isFixture {
            now = .now
        }
    }

    func refreshIfNeeded(force: Bool = false) async {
        tick()
        guard let client, !isFixture, !isUpdating else { return }
        guard force || RefreshPolicy.shouldFetch(cached: cached, now: now, minInterval: Self.foregroundMinInterval) else { return }
        isUpdating = true
        let before = cached?.meta.savedAt
        let result = await WindCore.refresh(client: client, store: store, location: preferences.activeCustom, now: .now)
        isUpdating = false
        setCached(result)
        tick()
        if let result, result.meta.savedAt != before {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Location

    func selectDefault() {
        guard preferences.useCustom else { return }
        preferences.useCustom = false
        locationChanged()
    }

    func selectCustom() {
        guard preferences.custom != nil, !preferences.useCustom else { return }
        preferences.useCustom = true
        locationChanged()
    }

    func saveCustom(_ location: SavedLocation) {
        preferences.custom = location
        preferences.useCustom = true
        locationChanged()
    }

    private func locationChanged() {
        LocationSettings.save(preferences, to: defaults)
        if isFixture {
            setCached(cached) // rebuilds `forecast` with the new isDefault flag
        } else {
            try? store.clear()
            setCached(nil)
            Task { await refreshIfNeeded(force: true) }
        }
    }

    // MARK: - Private

    private static func typeSize(_ value: String?) -> DynamicTypeSize? {
        switch value {
        case "xl": .xLarge
        case "xxl": .xxLarge
        case "xxxl": .xxxLarge
        case "ax1": .accessibility1
        case "ax2": .accessibility2
        case "ax3": .accessibility3
        case "ax4": .accessibility4
        case "ax5": .accessibility5
        default: nil
        }
    }

    private func setCached(_ value: Cached?) {
        cached = value
        forecast = value.map { Forecast(payload: $0.payload, isDefault: !preferences.effectiveUseCustom) }
    }

    private func applyFixture(state: String?) {
        let payload = PreviewData.payload
        let fetched = payload.fetchedDate
        let base = fetched.addingTimeInterval(30 * 60)
        try? store.clear()
        guard state != "firstrun" else {
            setCached(nil)
            now = base
            return
        }
        guard let data = try? payload.encoded() else { return }
        try? store.save(payloadData: data, etag: "\"fixture\"", at: fetched)
        switch state {
        case "stale":
            now = fetched.addingTimeInterval(2 * 3600)
        case "old":
            now = fetched.addingTimeInterval(7 * 3600)
        case "horizon":
            now = Forecast(payload: payload, isDefault: true).horizon.addingTimeInterval(2 * 3600)
        case "offline":
            try? store.recordCheck(ok: false, at: base)
            now = base
        case "updating":
            isUpdating = true
            now = base
        default:
            now = base
        }
        setCached(store.load())
    }
}
