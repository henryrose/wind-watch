import Foundation
import Testing
@testable import WindCore

@Suite("Payload (wire) and Forecast (view model)")
struct PayloadForecastTests {
    @Test func fixtureDecodesExactly() throws {
        let p = try Fixture.payload()
        #expect(p.v == 1)
        #expect(p.loc.name == "Port Townsend Bay")
        #expect(p.loc.lat == 48.0907)
        #expect(p.loc.lon == -122.7773)
        #expect(p.loc.tz == "America/Los_Angeles")
        #expect(p.loc.cell == "sea")
        #expect(p.model == "ncep_hrrr_conus")
        #expect(p.fetched == 1_792_598_400)
        #expect(p.run.latest == 1_792_594_800)
        #expect(p.run.extended == 1_792_584_000)
        #expect(p.start == 1_792_598_400)
        #expect(p.hours == 45)
        #expect(p.kn.count == 45 && p.gust.count == 45 && p.dir.count == 45)
        #expect(p.peak.gust == 25 && p.peak.at == 1_792_652_400)
        #expect(p.sun.count == 3)
        #expect(p.summary.count <= 110)
    }

    @Test func roundTripsThroughCodable() throws {
        let p = try Fixture.payload()
        let again = try Payload.decode(try p.encoded())
        #expect(again == p)
        // Wire keys are exactly the design's names.
        let keys = try #require(try JSONSerialization.jsonObject(with: p.encoded()) as? [String: Any]).keys.sorted()
        #expect(keys == ["cloud", "dir", "extended", "fetched", "gust", "hours", "kn", "loc", "model", "peak", "precip", "run", "start",
                         "summary", "sun", "temp", "v"])
    }

    @Test func extendedRunIsOptional() throws {
        var obj = try #require(try JSONSerialization.jsonObject(with: Fixture.data()) as? [String: Any])
        obj["run"] = ["latest": 1_792_594_800, "extended": NSNull()]
        let p = try Payload.decode(try JSONSerialization.data(withJSONObject: obj))
        #expect(p.run.extended == nil)
        obj["run"] = ["latest": 1_792_594_800]
        #expect(try Payload.decode(try JSONSerialization.data(withJSONObject: obj)).run.extended == nil)
    }

    @Test func validationRejectsLengthMismatch() throws {
        var p = try Fixture.payload()
        p.kn.removeLast()
        #expect(throws: Payload.ValidationError.lengthMismatch(hours: 45, kn: 44, gust: 45, dir: 45)) {
            try p.validate()
        }
    }

    @Test func forecastMirrorsHandoffViewModel() throws {
        let f = try Fixture.forecast()
        #expect(f.location.name == "Port Townsend Bay")
        #expect(f.location.isDefault == true)
        #expect(try Fixture.forecast(isDefault: false).location.isDefault == false)
        #expect(f.run == "HRRR 15Z")
        #expect(f.timeZone.identifier == "America/Los_Angeles")
        #expect(f.fetched == Date(timeIntervalSince1970: 1_792_598_400))
        #expect(f.start == Fixture.la(2026, 10, 21, 9))
        #expect(f.hours.count == 45)
        #expect(f.hours[0].kn == 3 && f.hours[0].gust == 4 && f.hours[0].dirFrom == 290)
        #expect(f.hours[15].kn == 15 && f.hours[15].gust == 25 && f.hours[15].dirFrom == 283)
        #expect(f.hours[44].kn == 11 && f.hours[44].gust == 21 && f.hours[44].dirFrom == 296)
        #expect(f.peakGust == Forecast.PeakGust(kn: 25, at: Fixture.la(2026, 10, 22, 0)))
        #expect(f.peakGust.at == f.date(ofHour: 15))
        #expect(f.sun.count == 3)
        #expect(f.sun[0].sunrise == Fixture.la(2026, 10, 21, 7, 40))
        #expect(f.sun[0].sunset == Fixture.la(2026, 10, 21, 18, 12))
        #expect(f.summary == "Light and variable this morning, building to 15 kn W by late afternoon, gusts to 25 overnight. Easing by dawn.")
    }

    @Test func horizonIsStartPlusHoursMinusOne() throws {
        let f = try Fixture.forecast()
        #expect(f.horizon == Fixture.la(2026, 10, 23, 5))
        #expect(f.horizon == f.start.addingTimeInterval(44 * 3600))
        #expect(f.date(ofHour: 44) == f.horizon)
    }

    @Test func runLabelUsesUTCHour() {
        #expect(Forecast.runLabel(latest: Date(timeIntervalSince1970: 1_792_594_800)) == "HRRR 15Z")
        #expect(Forecast.runLabel(latest: Date(timeIntervalSince1970: 1_792_584_000)) == "HRRR 12Z")
        #expect(Forecast.runLabel(latest: Date(timeIntervalSince1970: 0)) == "HRRR 00Z")
        #expect(Forecast.runLabel(latest: Date(timeIntervalSince1970: 5 * 3600)) == "HRRR 05Z")
    }
}
