import Foundation
import Observation
import SwiftUI

/// Shared app state for the iPhone and watch apps: the cached payload, the clock, the trust
/// state and the location preference. First paint is synchronous from `AppGroupStore.load()`;
/// the network is touched only from `refreshIfNeeded()`.
///
/// Environment switches (screenshots and previews):
/// - `WW_FIXTURE=1`: reference payload in a temp-dir store, no network.
/// - `WW_STATE=fresh|stale|old|offline|horizon|firstrun|updating`: forces a trust state by shifting
///   the clock (stale = fetched + 2 h, old = + 7 h, horizon = horizon + 2 h) or the cache meta.
/// - `WW_NOW=<ISO 8601>`: pins the clock.
/// - `WW_TYPE_SIZE=xl|xxl|xxxl|ax1…ax5`: forces a Dynamic Type size.
@MainActor
@Observable
public final class ForecastSession {
    public private(set) var cached: Cached?
    public private(set) var forecast: Forecast?
    public private(set) var now: Date
    public private(set) var isUpdating = false
    public private(set) var preferences: LocationSettings.Preferences
    public private(set) var typeSizeOverride: DynamicTypeSize?
    /// Called after a local preference edit (`saveCustom`, `selectDefault`, `selectCustom`); the
    /// iPhone app uses it to push the context to the watch. WindCore stays free of WatchConnectivity.
    @ObservationIgnored public var onPreferencesChanged: (@MainActor (LocationSettings.Preferences) -> Void)?

    public let store: AppGroupStore
    public let client: WindClient?
    public let defaults: UserDefaults
    public let groupID: String
    public let isFixture: Bool
    /// The process environment the session was built from (apps read their own keys from it).
    public let environment: [String: String]
    private let pinnedNow: Date?

    /// Minimum gap between checks while an app is in the foreground.
    public static let foregroundMinInterval: TimeInterval = 10 * 60

    /// - Parameters:
    ///   - bundleInfo: the app's `Bundle.main.infoDictionary` (`WWAPIBase`, `WWBundlePrefix`).
    ///   - environment: the process environment.
    ///   - mirrorFixtureToGroup: in fixture mode, also write the fixture cache and the
    ///     `FixtureFlag` into the real App Group store/defaults so the widget extension (which
    ///     cannot see the app's environment) renders the same data. Tests pass false.
    ///   - store: overrides the cache store (tests); nil uses the App Group store, or a temp
    ///     directory in fixture mode.
    public init(bundleInfo: [String: Any], environment: [String: String] = ProcessInfo.processInfo.environment,
                mirrorFixtureToGroup: Bool = true, store: AppGroupStore? = nil) {
        self.environment = environment
        let prefix = (bundleInfo["WWBundlePrefix"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "com.example"
        groupID = AppGroupStore.groupID(bundlePrefix: prefix)
        defaults = UserDefaults(suiteName: groupID) ?? .standard
        isFixture = environment["WW_FIXTURE"] == "1"
        pinnedNow = environment["WW_NOW"].flatMap { ISO8601DateFormatter().date(from: $0) }
        now = pinnedNow ?? .now
        preferences = LocationSettings.load(from: defaults)
        typeSizeOverride = Self.typeSize(environment["WW_TYPE_SIZE"])

        if isFixture {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("WindWatchFixture-\(UUID().uuidString)", isDirectory: true)
            self.store = store ?? AppGroupStore(directory: dir)
            client = nil
        } else {
            self.store = store ?? AppGroupStore(groupID: groupID)
            if let base = bundleInfo["WWAPIBase"] as? String, let url = URL(string: base), url.host() != nil {
                client = WindClient(baseURL: url, clientTag: WindClient.clientTag(bundleInfo: bundleInfo))
            } else {
                client = nil
            }
        }

        if isFixture {
            applyFixture(state: environment["WW_STATE"])
            if mirrorFixtureToGroup { mirrorFixtureToGroupStore() }
        } else {
            setCached(self.store.load())
            if mirrorFixtureToGroup { FixtureFlag.set(false, in: defaults) }
        }
        if let pinnedNow { now = pinnedNow }
    }

    /// Copies the fixture cache (payload + meta) into the real group store and raises the flag.
    private func mirrorFixtureToGroupStore() {
        let real = AppGroupStore(groupID: groupID)
        try? real.clear()
        if let data = store.loadPayloadData(), let meta = store.loadMeta() {
            try? real.save(payloadData: data, etag: meta.etag, at: meta.savedAt)
            try? real.recordCheck(ok: meta.lastCheckOK, at: meta.lastChecked ?? meta.savedAt)
        }
        FixtureFlag.set(true, in: defaults)
    }

    // MARK: - Derived

    public var trustState: TrustState {
        TrustState.compute(forecast: forecast, now: now, lastCheckOK: cached?.meta.lastCheckOK ?? true, isUpdating: isUpdating)
    }

    public var ageTier: AgeTier {
        forecast.map { AgeTier.compute(fetched: $0.fetched, now: now) } ?? .fresh
    }

    /// The hero hour, nil when numbers must not be shown (past horizon, first run).
    public var hero: Forecast.Hour? {
        guard let forecast, trustState.showsNumbers else { return nil }
        return forecast.hero(at: now)
    }

    public var locationName: String {
        if preferences.effectiveUseCustom, let custom = preferences.custom { return custom.name }
        return forecast?.location.name ?? SavedLocation.portTownsendBay.name
    }

    public var canReachNetwork: Bool { client != nil && !isFixture }

    // MARK: - Clock and refresh

    /// Advances the clock. Pinned (`WW_NOW`) and fixture clocks stay put so screenshots are stable.
    public func tick() {
        if let pinnedNow {
            now = pinnedNow
        } else if !isFixture {
            now = .now
        }
    }

    /// Fetches when the policy says so (or `force`). Returns true when a new payload was stored,
    /// so the caller can reload widget timelines.
    @discardableResult
    public func refreshIfNeeded(force: Bool = false) async -> Bool {
        tick()
        guard let client, !isFixture, !isUpdating else { return false }
        guard force || RefreshPolicy.shouldFetch(cached: cached, now: now, minInterval: Self.foregroundMinInterval) else { return false }
        isUpdating = true
        let before = cached?.meta.savedAt
        let result = await WindCore.refresh(client: client, store: store, location: preferences.activeCustom, now: .now)
        isUpdating = false
        setCached(result)
        tick()
        return result != nil && result?.meta.savedAt != before
    }

    // MARK: - Location

    public func selectDefault() {
        guard preferences.useCustom else { return }
        preferences.useCustom = false
        locationChanged()
    }

    public func selectCustom() {
        guard preferences.custom != nil, !preferences.useCustom else { return }
        preferences.useCustom = true
        locationChanged()
    }

    public func saveCustom(_ location: SavedLocation) {
        preferences.custom = location
        preferences.useCustom = true
        locationChanged()
    }

    /// Re-reads the preference from the group defaults after an external write (the watch's
    /// `WCSession` handler, D5). Returns true when the *active* location changed; only then is the
    /// cache dropped (a different location is a different payload). Fixture mode keeps its data and
    /// just rebuilds `forecast` with the new `isDefault` flag.
    @discardableResult
    public func reloadPreferences() -> Bool {
        let fresh = LocationSettings.load(from: defaults)
        guard fresh != preferences else { return false }
        let activeChanged = fresh.activeCustom != preferences.activeCustom
        preferences = fresh
        if isFixture || !activeChanged {
            setCached(cached)
        } else {
            try? store.clear()
            setCached(nil)
        }
        return activeChanged
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
        onPreferencesChanged?(preferences)
    }

    // MARK: - Private

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
}

/// `ww.fixture` in the group defaults: set by an app launched with `WW_FIXTURE=1` so the widget
/// extension, which has no access to that environment, knows to treat the group store as fixture
/// data. Cleared on any non-fixture launch.
public enum FixtureFlag {
    public static let key = "ww.fixture"

    public static func isSet(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: key)
    }

    public static func set(_ value: Bool, in defaults: UserDefaults) {
        defaults.set(value, forKey: key)
    }
}
