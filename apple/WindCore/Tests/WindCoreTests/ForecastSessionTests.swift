import Foundation
import Testing
@testable import WindCore

@Suite("ForecastSession (fixture and env handling)")
@MainActor
struct ForecastSessionTests {
    let info: [String: Any] = ["WWBundlePrefix": "com.example", "WWAPIBase": "https://example.test"]

    func session(_ state: String?, extra: [String: String] = [:]) -> ForecastSession {
        var env = ["WW_FIXTURE": "1"]
        if let state { env["WW_STATE"] = state }
        env.merge(extra) { _, new in new }
        return ForecastSession(bundleInfo: info, environment: env)
    }

    @Test func fixtureStates() {
        let f = PreviewData.forecast
        #expect(session(nil).trustState == .fresh)
        #expect(session(nil).now == f.fetched.addingTimeInterval(1800))
        #expect(session(nil).hero == f.hours[0])
        #expect(session("stale").trustState == .stale)
        #expect(session("old").trustState == .old)
        #expect(session("old").ageTier == .old)
        #expect(session("old").hero == f.hours[7])
        #expect(session("offline").trustState == .offlineCached)
        #expect(session("horizon").trustState == .pastHorizon)
        #expect(session("horizon").hero == nil)
        #expect(session("firstrun").trustState == .firstRun)
        #expect(session("firstrun").forecast == nil)
        #expect(session("updating").trustState == .updating)
        #expect(session("updating").hero == f.hours[0])
    }

    @Test func fixtureClockIsFrozen() async {
        let s = session("stale")
        let before = s.now
        s.tick()
        #expect(s.now == before)
        #expect(await s.refreshIfNeeded(force: true) == false) // no client in fixture mode
        #expect(!s.canReachNetwork)
    }

    @Test func pinnedNow() {
        let s = session(nil, extra: ["WW_NOW": "2026-10-22T06:30:00Z"])
        #expect(s.now == Date(timeIntervalSince1970: 1_792_650_600))
        s.tick()
        #expect(s.now == Date(timeIntervalSince1970: 1_792_650_600))
        #expect(s.trustState == .old)
    }

    @Test func typeSizeOverride() {
        #expect(session(nil, extra: ["WW_TYPE_SIZE": "ax1"]).typeSizeOverride == .accessibility1)
        #expect(session(nil, extra: ["WW_TYPE_SIZE": "xxl"]).typeSizeOverride == .xxLarge)
        #expect(session(nil).typeSizeOverride == nil)
    }

    @Test func groupAndClientFromBundleInfo() {
        let s = ForecastSession(bundleInfo: info, environment: [:])
        #expect(s.groupID == "group.com.example.windwatch")
        #expect(s.client?.baseURL.absoluteString == "https://example.test")
        #expect(!s.isFixture)
        let placeholder = ForecastSession(bundleInfo: ["WWAPIBase": "https:/REPLACE"], environment: [:])
        #expect(placeholder.client == nil)
        #expect(placeholder.groupID == "group.com.example.windwatch")
    }

    @Test func locationSelectionInFixtureMode() {
        let s = session(nil)
        let custom = SavedLocation(name: "Seattle", lat: 47.6, lon: -122.3, tz: "America/Los_Angeles")
        defer { s.defaults.removeObject(forKey: LocationSettings.customLocationKey); s.defaults.removeObject(forKey: LocationSettings.useCustomKey) }
        s.saveCustom(custom)
        #expect(s.preferences.effectiveUseCustom)
        #expect(s.locationName == "Seattle")
        #expect(s.forecast?.location.isDefault == false)
        #expect(s.forecast != nil) // fixture keeps the payload
        s.selectDefault()
        #expect(!s.preferences.useCustom)
        #expect(s.locationName == "Port Townsend Bay")
        #expect(s.forecast?.location.isDefault == true)
        s.selectCustom()
        #expect(s.preferences.effectiveUseCustom)
    }
}
