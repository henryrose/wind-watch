import Testing
@testable import WindCore

@Suite("HRRR coverage")
struct HRRRCoverageTests {
    @Test func cornersMapToTheGridCorners() throws {
        let sw = try #require(HRRRCoverage.gridPosition(lat: 21.138123, lon: -122.719528))
        #expect(abs(sw.x) < 0.01 && abs(sw.y) < 0.01)
        let ne = try #require(HRRRCoverage.gridPosition(lat: 47.842, lon: -60.917))
        #expect(abs(ne.x - 1798) < 0.5 && abs(ne.y - 1058) < 0.5)
    }

    /// Each point checked against Open-Meteo's `ncep_hrrr_conus` on 2026-10-22.
    @Test(arguments: [
        (48.09, -122.78, true),   // Port Townsend Bay
        (43.65, -79.38, true),    // Toronto
        (49.28, -123.12, true),   // Vancouver
        (52.0, -100.0, true),     // near the top edge
        (25.5, -100.0, true),     // near the bottom edge
        (47.0, -62.5, true),      // near the NE corner
        (47.0, -133.5, true),     // 2 cells inside the west edge
        (24.0, -80.5, true),      // Florida Keys
        (51.5, -0.12, false),     // London
        (61.2, -149.9, false),    // Anchorage
        (19.43, -99.13, false),   // Mexico City
        (21.3, -157.8, false),    // Honolulu
        (53.5, -100.0, false),    // past the top edge
        (47.2, -61.0, false),     // past the east edge
        (48.5, -133.0, false),    // past the NW corner
        (90.0, 0.0, false),
        (-33.9, 151.2, false),    // Sydney
    ])
    func matchesOpenMeteo(lat: Double, lon: Double, covered: Bool) {
        #expect(HRRRCoverage.contains(lat: lat, lon: lon) == covered)
    }
}

@Suite("HRRR cell")
struct HRRRCellTests {
    @Test func cellCentreRoundTripsThroughTheGrid() throws {
        let cell = try #require(HRRRCoverage.cell(lat: 48.1, lon: -122.683))
        let pos = try #require(HRRRCoverage.gridPosition(lat: cell.lat, lon: cell.lon))
        #expect(abs(pos.x - pos.x.rounded()) < 1e-6 && abs(pos.y - pos.y.rounded()) < 1e-6)
        #expect(cell.corners.count == 4)
        // A 3 km cell: each side ≈ 3 km, the centre within ~2.2 km of the 2 dp point.
        let side = HRRRCoverage.distanceKm(cell.corners[0].lat, cell.corners[0].lon, cell.corners[1].lat, cell.corners[1].lon)
        #expect(abs(side - 3) < 0.1)
        #expect(HRRRCoverage.distanceKm(48.10, -122.68, cell.lat, cell.lon) < 2.2)
        #expect(HRRRCoverage.cell(lat: 51.5, lon: -0.12) == nil)
    }

    @Test func forecastPointText() throws {
        let cell = try #require(HRRRCoverage.cell(lat: 48.1, lon: -122.683))
        #expect(HRRRCoverage.forecastPointText(lat: cell.lat, lon: cell.lon) == "HRRR cell at pin")
        let text = try #require(HRRRCoverage.forecastPointText(lat: 48.1, lon: -122.683))
        #expect(text.range(of: #"^HRRR cell (at pin|\d+\.\d km (N|NE|E|SE|S|SW|W|NW))$"#, options: .regularExpression) != nil)
        #expect(HRRRCoverage.forecastPointText(lat: 51.5, lon: -0.12) == nil)
        #expect(Int(HRRRCoverage.initialBearing(48, -122, 48.1, -122)) == 0)
        #expect(Int(HRRRCoverage.initialBearing(48, -122, 48, -121.9).rounded()) == 90)
    }
}
