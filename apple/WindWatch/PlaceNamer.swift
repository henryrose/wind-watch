import CoreLocation
import MapKit
import WindCore

/// Reverse-geocoded name suggestions for a new pin (location-naming handoff §6). Called once,
/// when the pin is placed; never again for that location. The first non-empty of
/// areasOfInterest → inland water / ocean → locality → sub-locality → administrative area is the
/// suggestion; the rest (deduplicated) become the chips, up to 4. 4 s timeout; nothing on failure.
enum PlaceNamer {
    struct Result: Sendable, Equatable {
        var suggestion: String?
        var chips: [String]
        /// IANA zone of the point when the geocoder knows it.
        var timeZone: String?
    }

    static func suggest(lat: Double, lon: Double, preferred: String? = nil) async -> Result {
        let names = await withTaskGroup(of: Result?.self) { group -> Result in
            group.addTask { await lookup(lat: lat, lon: lon) }
            group.addTask {
                try? await Task.sleep(for: .seconds(4))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? Result(suggestion: nil, chips: [], timeZone: nil)
        }
        // A search result's own name leads; the geocoder's names follow as chips.
        var ordered = [preferred, names.suggestion].compactMap { $0 } + names.chips
        ordered = ordered.map(LocationName.normalize).filter { !$0.isEmpty }
        var seen = Set<String>()
        ordered = ordered.filter { seen.insert($0.lowercased()).inserted }
        return Result(suggestion: ordered.first, chips: Array(ordered.dropFirst().prefix(4)), timeZone: names.timeZone)
    }

    private static func lookup(lat: Double, lon: Double) async -> Result {
        let location = CLLocation(latitude: lat, longitude: lon)
        var ordered: [String?] = []
        var tz: String?
        if #available(iOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try? await request.mapItems.first else { return Result(suggestion: nil, chips: [], timeZone: nil) }
            let reps = item.addressRepresentations
            ordered = [item.name, reps?.cityName, reps?.regionName]
            tz = item.timeZone?.identifier
        } else {
            // iOS 18–25: the pre-26 geocoder exposes the handoff's fields directly.
            guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
                return Result(suggestion: nil, chips: [], timeZone: nil)
            }
            ordered = (mark.areasOfInterest ?? []).map(Optional.some)
                + [mark.inlandWater, mark.ocean, mark.locality, mark.subLocality, mark.administrativeArea]
            tz = mark.timeZone?.identifier
        }
        var seen = Set<String>()
        let names = ordered.compactMap { $0 }.map(LocationName.normalize).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        return Result(suggestion: names.first, chips: Array(names.dropFirst()), timeZone: tz)
    }
}
