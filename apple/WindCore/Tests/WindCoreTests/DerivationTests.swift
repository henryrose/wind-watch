import Foundation
import Testing
@testable import WindCore

@Suite("HANDOFF §10 expected derived values")
struct ReferenceValueTests {
    @Test func hourZero() throws {
        let f = try Fixture.forecast()
        let h = f.hours[0]
        #expect(h.kn == 3)
        #expect(h.gust == 4)
        #expect(Compass.fromText(dirFrom: h.dirFrom) == "from W")
        #expect(Beaufort.step(kn: h.kn) == 1)
        #expect(Beaufort.colorToken(kn: h.kn).assetName == "bft.calm")
        #expect(Compass.arrowRotation(dirFrom: h.dirFrom) == 110)
    }

    @Test func hourFifteen() throws {
        let f = try Fixture.forecast()
        let h = f.hours[15]
        #expect(h.kn == 15)
        #expect(h.gust == 25)
        #expect(Compass.fromText(dirFrom: h.dirFrom) == "from W")
        #expect(Beaufort.step(kn: h.kn) == 4)
        #expect(Beaufort.colorToken(kn: h.kn).assetName == "bft.4")
        #expect(Compass.arrowRotation(dirFrom: h.dirFrom) == 103)
    }

    @Test func yDomain() throws {
        let f = try Fixture.forecast()
        #expect(Derivations.yDomainMax(hours: f.hours) == 30)
        #expect(f.yDomainMax == 30)
    }

    @Test func runAndHorizon() throws {
        let f = try Fixture.forecast()
        #expect(f.run == "HRRR 15Z")
        #expect(f.horizon == Fixture.la(2026, 10, 23, 5))
        #expect(Derivations.horizonLabel(forecast: f, tz: Fixture.la) == "HRRR ends 05:00")
        #expect(f.horizonLabel == "HRRR ends 05:00")
        #expect(Derivations.horizonLabel(forecast: f, short: true) == "ends 05:00")
        #expect(Derivations.horizonWeekdayLabel(forecast: f) == "ends Fri 5am")
    }

    @Test func peakGustChip() throws {
        let f = try Fixture.forecast()
        #expect(Derivations.peakGustChipText(forecast: f, now: f.start) == "25 kn gusts around midnight")
    }

    @Test func readoutAndTableLabels() throws {
        let f = try Fixture.forecast()
        let now = f.start.addingTimeInterval(25 * 60)
        #expect(Derivations.nowLabel(now: now, tz: Fixture.la) == "Now · Wed 9:25am")
        #expect(Derivations.nowLabel(now: Fixture.la(2026, 10, 22, 12, 5), tz: Fixture.la) == "Now · Thu 12:05pm")
        #expect(Derivations.nowLabel(now: Fixture.la(2026, 10, 22, 0, 0), tz: Fixture.la) == "Now · Thu 12:00am")
        #expect(Derivations.tableHourCount(forecast: f, now: now) == 45)
        #expect(Derivations.tableCaption(forecast: f, now: now) == "45 hours · Wed 9am → Fri 5am")
        #expect(Derivations.tableCaption(forecast: f, now: f.start.addingTimeInterval(43 * 3600 + 1800)) == "2 hours · Fri 4am → Fri 5am")
    }

    @Test func heroAccessibility() throws {
        let f = try Fixture.forecast()
        #expect(Derivations.heroAccessibilityLabel(hour: f.hours[15], forecast: f) == "15 knots, gusting 25, from the west, as of 09:00")
    }
}

@Suite("nowIndex and hero")
struct NowIndexTests {
    @Test func beforeStartIsNegativeButHeroClampsToZero() throws {
        let f = try Fixture.forecast()
        let now = f.start.addingTimeInterval(-30 * 60)
        #expect(Derivations.nowIndex(forecast: f, now: now) == -0.5)
        #expect(Derivations.heroIndex(forecast: f, now: now) == 0)
        #expect(Derivations.hero(forecast: f, now: now) == f.hours[0])
    }

    @Test func midForecast() throws {
        let f = try Fixture.forecast()
        let now = f.start.addingTimeInterval(15.5 * 3600)
        #expect(Derivations.nowIndex(forecast: f, now: now) == 15.5)
        #expect(Derivations.heroIndex(forecast: f, now: now) == 15)
        #expect(f.hero(at: now) == Forecast.Hour(kn: 15, gust: 25, dirFrom: 283, tempC: 7.9, cloud: 100, precip: 1.2))
    }

    @Test func atHorizonIsLastHour() throws {
        let f = try Fixture.forecast()
        #expect(Derivations.nowIndex(forecast: f, now: f.horizon) == 44)
        #expect(Derivations.heroIndex(forecast: f, now: f.horizon) == 44)
        #expect(f.hero(at: f.horizon) == f.hours[44])
    }

    @Test func pastHorizonHasNoHero() throws {
        let f = try Fixture.forecast()
        let now = f.horizon.addingTimeInterval(1)
        #expect(Derivations.nowIndex(forecast: f, now: now) > 44)
        #expect(Derivations.heroIndex(forecast: f, now: now) == nil)
        #expect(Derivations.hero(forecast: f, now: now) == nil)
    }

    @Test func yDomainEdges() {
        func h(_ gusts: [Int]) -> [Forecast.Hour] { gusts.map { Forecast.Hour(kn: 0, gust: $0, dirFrom: 0) } }
        #expect(Derivations.yDomainMax(hours: []) == 20)
        #expect(Derivations.yDomainMax(hours: h([5])) == 20)
        #expect(Derivations.yDomainMax(hours: h([17])) == 20)
        #expect(Derivations.yDomainMax(hours: h([18])) == 30)
        #expect(Derivations.yDomainMax(hours: h([27])) == 30)
        #expect(Derivations.yDomainMax(hours: h([28])) == 40)
        #expect(Derivations.yDomainMax(hours: h([3, 47, 12])) == 50)
    }
}

@Suite("Relative time phrases (HANDOFF §8.1)")
struct RelativeTimePhraseTests {
    let tz = Fixture.la
    let now = Fixture.la(2026, 10, 21, 9) // Wednesday 09:00

    @Test func sameDayPeriods() {
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 21, 10), now: now, tz: tz) == "this morning")
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 21, 14), now: now, tz: tz) == "this afternoon")
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 21, 19), now: now, tz: tz) == "this evening")
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 21, 23, 30), now: now, tz: tz) == "around midnight")
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 22, 0), now: now, tz: tz) == "around midnight")
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 22, 3), now: now, tz: tz) == "overnight")
    }

    @Test func tomorrowPeriods() {
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 22, 8), now: now, tz: tz) == "tomorrow morning")
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 22, 15), now: now, tz: tz) == "tomorrow afternoon")
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 22, 21), now: now, tz: tz) == "tomorrow evening")
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 23, 1), now: now, tz: tz) == "tomorrow night")
    }

    @Test func fartherOutUsesWeekday() {
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 23, 5), now: now, tz: tz) == "Friday morning")
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 24, 2), now: now, tz: tz) == "Friday night")
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 25, 13), now: now, tz: tz) == "Sunday afternoon")
    }

    @Test func pastPhrases() {
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 20, 15), now: now, tz: tz) == "yesterday afternoon")
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 21, 2), now: now, tz: tz) == "last night")
    }

    @Test func nightBelongsToPrecedingDay() {
        // At 23:30 Wednesday, 00:00 Thursday is still "around midnight".
        let late = Fixture.la(2026, 10, 21, 23, 30)
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 22, 0), now: late, tz: tz) == "around midnight")
        // At 02:00 Thursday, 10:00 Thursday is "this morning".
        let small = Fixture.la(2026, 10, 22, 2)
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 22, 10), now: small, tz: tz) == "this morning")
    }
}

@Suite("Relative time phrases from the small hours")
struct SmallHoursPhraseTests {
    let tz = Fixture.la
    let now = Fixture.la(2026, 10, 22, 2) // Thursday 02:00

    @Test func smallHours() {
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 22, 0), now: now, tz: tz) == "around midnight")
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 22, 4), now: now, tz: tz) == "overnight")
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 22, 10), now: now, tz: tz) == "this morning")
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 22, 20), now: now, tz: tz) == "this evening")
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 23, 0), now: now, tz: tz) == "tomorrow night")
        #expect(Derivations.relativeTimePhrase(for: Fixture.la(2026, 10, 23, 9), now: now, tz: tz) == "tomorrow morning")
    }
}
