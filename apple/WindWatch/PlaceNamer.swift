import CoreLocation
import MapKit
import WindCore

/// A pin that has not been saved yet: where it is and what the geocoder offered for it.
struct LocationDraft: Identifiable, Equatable {
    let id = UUID()
    var lat: Double
    var lon: Double
    var tz: String
    /// Pre-fills the NAME field; nil (geocoder silent or timed out) leaves it empty.
    var suggestion: String?
    /// The other nearby names (≤ 4).
    var chips: [String]

    var location: SavedLocation {
        SavedLocation(id: id, name: suggestion ?? "", lat: lat, lon: lon, tz: tz,
                      suggestedNames: [suggestion].compactMap { $0 } + chips)
    }
}

/// Names a pin once, when it is placed (location-naming §6): the reverse geocoder with a 4 s
/// timeout, mapped onto `GeocodedNames`. iOS 26+ uses `MKReverseGeocodingRequest`; iOS 18–25 the
/// pre-26 `CLGeocoder`, whose placemark carries areasOfInterest / inlandWater / ocean directly.
enum PlaceNamer {
    static let timeout: Duration = .seconds(4)

    struct Found: Sendable {
        var names: GeocodedNames
        var tz: String?
    }

    /// A draft for a long-pressed or pasted point.
    static func draft(lat: Double, lon: Double) async -> LocationDraft {
        let found = await reverse(lat: lat, lon: lon)
        let names = found?.names ?? GeocodedNames()
        return LocationDraft(lat: lat, lon: lon, tz: found?.tz ?? TimeZone.current.identifier,
                             suggestion: names.suggestion, chips: names.chips)
    }

    /// A draft for a search pick: the result's own name leads, the geocoder fills the chips.
    static func draft(searchName: String?, lat: Double, lon: Double, tz: String?) async -> LocationDraft {
        let found = await reverse(lat: lat, lon: lon)
        let ordered = found?.names.ordered ?? []
        let lead = searchName.map(LocationName.normalize).flatMap { $0.isEmpty ? nil : LocationName.clamp($0) } ?? ordered.first
        let chips = ordered.filter { $0.lowercased() != lead?.lowercased() }.prefix(GeocodedNames.maxChips)
        return LocationDraft(lat: lat, lon: lon, tz: tz ?? found?.tz ?? TimeZone.current.identifier,
                             suggestion: lead, chips: Array(chips))
    }

    /// Nil on failure or after `timeout`, whichever comes first.
    static func reverse(lat: Double, lon: Double) async -> Found? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Found?, Never>) in
            let once = ResumeOnce(continuation)
            let work = Task { once.resume(await lookup(lat: lat, lon: lon)) }
            Task {
                try? await Task.sleep(for: timeout)
                work.cancel()
                once.resume(nil)
            }
        }
    }

    private static func lookup(lat: Double, lon: Double) async -> Found? {
        let location = CLLocation(latitude: lat, longitude: lon)
        if #available(iOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let items = try? await request.mapItems, let first = items.first
            else { return nil }
            // The map item's name is the feature at the point (a park, a bay) unless it is a
            // street address; it stands in for areasOfInterest / inlandWater.
            let features = items.compactMap(\.name).filter { !($0.first?.isNumber ?? true) }
            // `regionName` is the country, not the state, so it is not offered.
            let names = GeocodedNames(areasOfInterest: features,
                                      locality: first.addressRepresentations?.cityName)
            return Found(names: names, tz: first.timeZone?.identifier)
        } else {
            guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
            let names = GeocodedNames(areasOfInterest: mark.areasOfInterest ?? [], inlandWater: mark.inlandWater,
                                      ocean: mark.ocean, locality: mark.locality, subLocality: mark.subLocality,
                                      administrativeArea: mark.administrativeArea)
            return Found(names: names, tz: mark.timeZone?.identifier)
        }
    }

    /// First hit for a place search, nil when nothing matched; throws on a transport failure.
    static func search(_ text: String) async throws -> (name: String?, lat: Double, lon: Double, tz: String?)? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.address, .pointOfInterest]
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { return nil }
        let coordinate: CLLocationCoordinate2D
        if #available(iOS 26, *) {
            coordinate = item.location.coordinate
        } else {
            coordinate = item.placemark.coordinate
        }
        return (item.name, coordinate.latitude, coordinate.longitude, item.timeZone?.identifier)
    }
}

/// Resumes a continuation exactly once (the lookup and the timeout race for it).
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}
