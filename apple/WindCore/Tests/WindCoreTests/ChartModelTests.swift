import Foundation
import SwiftUI
import Testing
@testable import WindCore

@Suite("ChartModel")
struct ChartModelTests {
    @Test func allWindowEarly() throws {
        let f = try Fixture.forecast()
        let now = f.start.addingTimeInterval(30 * 60)
        let m = ChartModel(forecast: f, now: now, window: .all, scheme: .dark)
        #expect(m.points.count == 45)
        #expect(m.points.first?.index == 0 && m.points.last?.index == 44)
        #expect(m.points[15] == HourPoint(index: 15, date: f.date(ofHour: 15), kn: 15, gust: 25, dirFrom: 283, step: 4))
        #expect(m.xRange == f.start...f.horizon.addingTimeInterval(3600))
        #expect(m.slotCount == 45)
        #expect(m.yMax == 30)
        #expect(m.horizonEdge == Fixture.la(2026, 10, 23, 6))
        #expect(m.horizonLabel == "HRRR ends 05:00")
        #expect(m.sunMarkers == [f.sun[0].sunset, f.sun[1].sunrise, f.sun[1].sunset])
        #expect(m.arrowCadence == 3)
        #expect(m.tickEvery == 6)
        #expect(m.nowDate == now && m.showsNow)
        #expect(m.nowIndex == 0.5)
        #expect(m.ageTier == .fresh)
        #expect(m.twilightStops == Twilight.gradientStops(range: m.xRange, sun: f.sun))
        #expect(m.twilightStops.count == 8)
        #expect(m.maxGust == 25)
        #expect(m.timeZone.identifier == "America/Los_Angeles")
    }

    @Test func next12MidForecast() throws {
        let f = try Fixture.forecast()
        let now = Fixture.la(2026, 10, 21, 23, 30) // index 14.5
        let m = ChartModel(forecast: f, now: now, window: .next12, scheme: .dark)
        #expect(m.points.map(\.index) == Array(14...25))
        #expect(m.xRange == f.date(ofHour: 14)...f.date(ofHour: 26))
        #expect(m.xRange.upperBound.timeIntervalSince(m.xRange.lowerBound) == 12 * 3600)
        #expect(m.slotCount == 12)
        #expect(m.horizonEdge == nil)
        #expect(m.horizonLabel == nil)
        #expect(m.arrowCadence == 1)
        #expect(m.tickEvery == 3)
        #expect(m.yMax == 30) // max gust 25 in hours 14…25
        #expect(m.sunMarkers == [f.sun[1].sunrise]) // Thu 07:41 within 23:00…11:00
        #expect(m.showsNow)
    }

    @Test func next12NearHorizon() throws {
        let f = try Fixture.forecast()
        let now = Fixture.la(2026, 10, 22, 22, 30) // index 37.5
        let m = ChartModel(forecast: f, now: now, window: .next12, scheme: .dark)
        #expect(m.points.map(\.index) == Array(37...44))
        #expect(m.points.count == 8)
        #expect(m.xRange == f.date(ofHour: 37)...f.date(ofHour: 49))
        #expect(m.slotCount == 12)
        #expect(m.horizonEdge == f.horizon.addingTimeInterval(3600))
        #expect(m.horizonLabel == "ends 05:00")
        #expect(m.yMax == 30) // gusts 20,20,20,18,18,20,21,21 → ceil(24/10)*10 = 30
        #expect(m.ageTier == .old)
    }

    @Test func allWindowShortLabelWhenEdgeNearNow() throws {
        let f = try Fixture.forecast()
        let now = f.date(ofHour: 40)
        let m = ChartModel(forecast: f, now: now, window: .all, scheme: .light)
        #expect(m.horizonLabel == "ends 05:00") // edge at 45, now at 40 → within 12 slots
        #expect(m.points.count == 45)
        #expect(m.ageTier == .old)
    }

    @Test func oldTier() throws {
        let f = try Fixture.forecast()
        let m = ChartModel(forecast: f, now: f.fetched.addingTimeInterval(7 * 3600), window: .all, scheme: .dark)
        #expect(m.ageTier == .old)
        let fresh = ChartModel(forecast: f, now: f.fetched.addingTimeInterval(60), window: .all, scheme: .dark)
        #expect(fresh.ageTier == .fresh)
    }

    @Test func shadeStopsFollowScheme() throws {
        let f = try Fixture.forecast()
        let dark = ChartModel(forecast: f, now: f.start, window: .all, scheme: .dark)
        let light = ChartModel(forecast: f, now: f.start, window: .all, scheme: .light)
        #expect(dark.shadeStops.count == dark.twilightStops.count)
        #expect(dark.shadeStops.first?.color == Color.white.opacity(0.07))
        #expect(dark.shadeStops.last?.color == Color.white.opacity(0))
        #expect(light.shadeStops.first?.color == Color.black.opacity(0))
        #expect(light.shadeStops.last?.color == Color.black.opacity(0.08))
        #expect(dark.shadeStops.map { Double($0.location) } == dark.twilightStops.map(\.fraction))
    }

    @Test func beforeStartClampsWindow() throws {
        let f = try Fixture.forecast()
        let m = ChartModel(forecast: f, now: f.start.addingTimeInterval(-3600), window: .next12, scheme: .dark)
        #expect(m.points.map(\.index) == Array(0...11))
        #expect(!m.showsNow)
    }

    @Test func capWidthGeometry() {
        // Phone: 45 slots over 370 pt → slot 8.22 pt; cap = 0.72 h + 2 pt (0.243 h) → half 0.4817 h.
        let half = ChartStyle.phone.capHalfWidthSeconds(slots: 45) / 3600
        #expect(abs(half - (0.72 + 2 / (370.0 / 45)) / 2) < 1e-9)
        #expect(ChartStyle.watch.slotWidth(slots: 12) == 198.0 / 12)
    }
}

@Suite("MiniStrip window (HANDOFF §6.3)")
struct MiniStripTests {
    @Test func sixHoursFromFloorOfNow() throws {
        let f = try Fixture.forecast()
        let w = MiniStrip.window(forecast: f, now: f.start.addingTimeInterval(13.9 * 3600))
        #expect(w.firstIndex == 13)
        #expect(w.points.map(\.index) == [13, 14, 15, 16, 17, 18])
        #expect(w.yMax == 25) // max gust 25 → already a multiple of 5
        #expect(w.range == f.date(ofHour: 13)...f.date(ofHour: 19))
        #expect(w.sunMarkers.isEmpty)
        #expect(w.ageTier == .old)
    }

    @Test func roundsUpToFive() throws {
        let f = try Fixture.forecast()
        let w = MiniStrip.window(forecast: f, now: f.start)
        #expect(w.points.map(\.gust) == [4, 5, 3, 3, 4, 2])
        #expect(w.yMax == 5)
        let w2 = MiniStrip.window(forecast: f, now: f.date(ofHour: 9))
        #expect(w2.points.map(\.gust) == [9, 13, 15, 18, 19, 24])
        #expect(w2.yMax == 25)
        #expect(w2.sunMarkers == [f.sun[0].sunset]) // 18:12 inside 18:00…24:00
    }

    @Test func pastHorizonSlotsEmpty() throws {
        let f = try Fixture.forecast()
        let w = MiniStrip.window(forecast: f, now: f.date(ofHour: 42))
        #expect(w.points.map(\.index) == [42, 43, 44])
        #expect(w.range == f.date(ofHour: 42)...f.date(ofHour: 48))
        let gone = MiniStrip.window(forecast: f, now: f.horizon.addingTimeInterval(1))
        #expect(gone.points.isEmpty)
        #expect(gone.yMax == 5)
    }
}

@Suite("View smoke tests")
struct ViewSmokeTests {
    @Test @MainActor func viewsConstruct() throws {
        let f = try Fixture.forecast()
        let now = f.start.addingTimeInterval(30 * 60)
        let chart = WindChart(model: ChartModel(forecast: f, now: now, window: .all, scheme: .dark), style: .phone)
        _ = chart.body
        let watchChart = WindChart(model: ChartModel(forecast: f, now: now, window: .next12, scheme: .dark), style: .watch)
        _ = watchChart.body
        let strip = MiniStrip(forecast: f, now: now)
        _ = strip.body
        for state in TrustState.allCases {
            let line = TrustLineView(state: state, forecast: state == .firstRun ? nil : f, now: now, compact: state == .stale)
            _ = line.body
            #expect(line.text == TrustLine.text(state: state, forecast: state == .firstRun ? nil : f, now: now))
        }
        #expect(TrustLineView(state: .pastHorizon, forecast: f, now: now).isAmber)
        #expect(!TrustLineView(state: .fresh, forecast: f, now: now).isAmber)
        _ = ArrowView(dirFrom: 290, size: 18).body
        _ = BeaufortPill(step: 10).body
        _ = BeaufortChip(step: 4).body
        _ = TickCap(width: 10, lineWidth: 1.5).body
        _ = SunDot(radius: 3).body
        _ = WifiSlash().body
    }

    @Test func arrowShapeGeometry() {
        let p = ArrowShape().path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        let b = p.boundingRect
        #expect(abs(b.minX - 12) < 0.01 && abs(b.maxX - 88) < 0.01)
        #expect(abs(b.minY - 0) < 0.01 && abs(b.maxY - 100) < 0.01)
    }

    @Test func previewDataLoads() {
        #expect(PreviewData.forecast.hours.count == 45)
        #expect(PreviewData.forecast.run == "HRRR 15Z")
        #expect(PreviewData.now == PreviewData.forecast.start.addingTimeInterval(1800))
        #expect(PreviewData.chart(window: .all).points.count == 45)
    }

    @Test func tokensAndFonts() {
        #expect(Tokens.ground(.dark) == Color(hex: "#0B0E12"))
        #expect(Tokens.ground(.light) == Color(hex: "#F4F5F7"))
        #expect(Tokens.trustAmber(.light) == Color(hex: "#B86E00"))
        #expect(Tokens.numberInk(.dark, tier: .old) == Tokens.inkOld(.dark))
        #expect(Tokens.numberInk(.dark, tier: .stale) == Tokens.inkPrimary(.dark))
        #expect(WindTheme(.dark).beaufort(step: 4) == Color(hex: "#8DD44A"))
        _ = Tokens.heroFont(watch: true)
        _ = Tokens.trustFont(watch: false, amber: true)
        #expect(Tokens.heroTracking(watch: true) < 0)
    }
}
