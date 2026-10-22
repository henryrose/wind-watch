import Foundation

/// The HRRR CONUS grid (NCEP): Lambert conformal on a 6 371 229 m sphere, tangent at 38.5°N,
/// centre meridian 97.5°W, 1799 × 1059 cells of 3 km with the first cell at 21.138123°N
/// 122.719528°W. A point is covered when it projects inside the grid; Open-Meteo answers
/// "No data is available for this location" everywhere else (checked 2026-10-22 against points
/// 2 cells inside and 3 cells outside each edge). The server stays the authority; this lets the
/// Location screen refuse a point before offering Save, offline too.
public enum HRRRCoverage {
    static let radius = 6_371_229.0
    static let tangentLat = 38.5
    static let centreLon = -97.5
    static let firstLat = 21.138123
    static let firstLon = -122.719528
    static let cellSize = 3000.0
    static let columns = 1799
    static let rows = 1059

    /// Shown when a point is outside the grid.
    public static let outsideText = "HRRR covers the continental US and nearby Canada and Mexico only. Pick a point inside it."

    public static func contains(lat: Double, lon: Double) -> Bool {
        guard let cell = gridPosition(lat: lat, lon: lon) else { return false }
        return (0...Double(columns - 1)).contains(cell.x) && (0...Double(rows - 1)).contains(cell.y)
    }

    /// Fractional (column, row) of a point, (0, 0) at the first cell; nil at the poles.
    static func gridPosition(lat: Double, lon: Double) -> (x: Double, y: Double)? {
        guard abs(lat) < 89.9, let p = project(lat: lat, lon: lon), let o = project(lat: firstLat, lon: firstLon) else { return nil }
        return ((p.x - o.x) / cellSize, (p.y - o.y) / cellSize)
    }

    private static func project(lat: Double, lon: Double) -> (x: Double, y: Double)? {
        let rad = Double.pi / 180
        let phi1 = tangentLat * rad
        let n = sin(phi1)
        let f = cos(phi1) * pow(tan(.pi / 4 + phi1 / 2), n) / n
        let rho = radius * f / pow(tan(.pi / 4 + lat * rad / 2), n)
        let rho0 = radius * f / pow(tan(.pi / 4 + phi1 / 2), n)
        var dLon = lon - centreLon
        if dLon > 180 { dLon -= 360 }
        if dLon < -180 { dLon += 360 }
        let theta = n * dLon * rad
        guard rho.isFinite else { return nil }
        return (rho * sin(theta), rho0 - rho * cos(theta))
    }
}

extension SavedLocation {
    /// True when the point is inside the HRRR grid (`HRRRCoverage`).
    public var isInHRRRCoverage: Bool { HRRRCoverage.contains(lat: lat, lon: lon) }
}
