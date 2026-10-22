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
