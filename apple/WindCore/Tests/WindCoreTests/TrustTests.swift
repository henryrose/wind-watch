import Foundation
import Testing
@testable import WindCore

@Suite("Trust state (HANDOFF §3)")
struct TrustStateTests {
    func state(_ offset: TimeInterval, ok: Bool = true, updating: Bool = false) throws -> TrustState {
        let f = try Fixture.forecast()
        return TrustState.compute(forecast: f, now: f.fetched.addingTimeInterval(offset), lastCheckOK: ok, isUpdating: updating)
    }

    @Test func ageTransitions() throws {
        #expect(try state(0) == .fresh)
        #expect(try state(89 * 60) == .fresh)
        #expect(try state(90 * 60) == .stale)
        #expect(try state(91 * 60) == .stale)
        #expect(try state(6 * 3600 - 1) == .stale)
        #expect(try state(6 * 3600) == .old)
        #expect(try state(30 * 3600) == .old)
    }

    @Test func pastHorizon() throws {
        let f = try Fixture.forecast()
        #expect(TrustState.compute(forecast: f, now: f.horizon, lastCheckOK: true) == .old)
        #expect(TrustState.compute(forecast: f, now: f.horizon.addingTimeInterval(1), lastCheckOK: true) == .pastHorizon)
        // Past horizon beats offline and updating.
        #expect(TrustState.compute(forecast: f, now: f.horizon.addingTimeInterval(1), lastCheckOK: false) == .pastHorizon)
        #expect(TrustState.compute(forecast: f, now: f.horizon.addingTimeInterval(1), lastCheckOK: true, isUpdating: true) == .pastHorizon)
    }

    @Test func offlineCachedAndFirstRun() throws {
        #expect(try state(0, ok: false) == .offlineCached)
        #expect(try state(7 * 3600, ok: false) == .offlineCached)
        #expect(TrustState.compute(forecast: nil, now: .now, lastCheckOK: false) == .firstRun)
        #expect(TrustState.compute(forecast: nil, now: .now, lastCheckOK: true) == .firstRun)
        #expect(TrustState.compute(forecast: nil, now: .now, lastCheckOK: true, isUpdating: true) == .firstRun)
    }

    @Test func updating() throws {
        #expect(try state(0, updating: true) == .updating)
        #expect(try state(0, ok: false, updating: true) == .updating)
    }

    @Test func ageTierIndependentOfState() throws {
        let f = try Fixture.forecast()
        #expect(AgeTier.compute(fetched: f.fetched, now: f.fetched.addingTimeInterval(7 * 3600)) == .old)
        #expect(AgeTier.compute(fetched: f.fetched, now: f.fetched.addingTimeInterval(2 * 3600)) == .stale)
        #expect(AgeTier.compute(fetched: f.fetched, now: f.fetched) == .fresh)
    }

    @Test func flags() {
        #expect(TrustState.stale.isAmber && TrustState.old.isAmber && TrustState.offlineCached.isAmber)
        #expect(!TrustState.fresh.isAmber && !TrustState.updating.isAmber)
        #expect(!TrustState.pastHorizon.showsNumbers && !TrustState.firstRun.showsNumbers)
        #expect(TrustState.old.showsNumbers)
    }
}

@Suite("Trust line text")
struct TrustLineTests {
    @Test func lines() throws {
        let f = try Fixture.forecast() // fetched Wed 09:00 PDT, run 15Z (08:00 PDT Wed)
        let fresh = f.fetched.addingTimeInterval(10 * 60)
        let old = f.fetched.addingTimeInterval(7 * 3600)
        #expect(trustLineText(state: .fresh, forecast: f, now: fresh) == "as of 09:00 · HRRR 15Z")
        #expect(trustLineText(state: .stale, forecast: f, now: f.fetched.addingTimeInterval(2 * 3600)) == "as of 09:00 · HRRR 15Z")
        #expect(trustLineText(state: .old, forecast: f, now: old) == "as of Wed 09:00 · HRRR 15Z")
        #expect(trustLineText(state: .pastHorizon, forecast: f, now: f.horizon.addingTimeInterval(60)) == "No forecast · last run HRRR 15Z Wed")
        #expect(trustLineText(state: .offlineCached, forecast: f, now: fresh) == "Couldn't reach server · showing data from 09:00")
        #expect(trustLineText(state: .offlineCached, forecast: f, now: old) == "Couldn't reach server · showing data from Wed 09:00")
        #expect(trustLineText(state: .updating, forecast: f, now: fresh) == "updating · as of 09:00")
        #expect(trustLineText(state: .firstRun, forecast: nil, now: fresh) == "No data yet. Needs cellular or Wi-Fi once.")
        #expect(trustLineText(state: .fresh, forecast: nil, now: fresh) == "No data yet. Needs cellular or Wi-Fi once.")
    }

    @Test func explicitTimeZoneOverride() throws {
        let f = try Fixture.forecast()
        #expect(trustLineText(state: .fresh, forecast: f, now: f.fetched, tz: Fixture.utc) == "as of 16:00 · HRRR 15Z")
    }

    @Test func inline() throws {
        let f = try Fixture.forecast()
        let hero = f.hours[15]
        #expect(TrustLine.inlineText(state: .fresh, hero: hero, forecast: f, now: f.fetched) == "15 G25 kn")
        #expect(TrustLine.inlineText(state: .stale, hero: hero, forecast: f, now: f.fetched.addingTimeInterval(2 * 3600)) == "15 G25 kn · 09:00")
        #expect(TrustLine.inlineText(state: .old, hero: hero, forecast: f, now: f.fetched.addingTimeInterval(7 * 3600)) == "15 G25 kn · Wed 09:00")
        #expect(TrustLine.inlineText(state: .pastHorizon, hero: nil, forecast: f, now: f.horizon.addingTimeInterval(1)) == "Wind — open app")
        #expect(TrustLine.inlineText(state: .firstRun, hero: nil, forecast: nil, now: .now) == "Wind — open app")
    }
}
