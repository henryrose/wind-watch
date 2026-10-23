import MapKit
import SwiftUI
import WindCore

/// HANDOFF §8.3 / `Phone-Location.dc.html`. The default card is always one tap and never moves;
/// the custom card holds the name, the selection ring, the search field, the map and the legend.
struct LocationSettingsView: View {
    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme

    @State private var query = ""
    @State private var candidate: SavedLocation?
    @State private var searchError: String?
    @State private var isSearching = false
    @State private var isSaving = false
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: SavedLocation.portTownsendBay.lat, longitude: SavedLocation.portTownsendBay.lon),
            span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)
        )
    )

    /// Called after a custom location is saved (the Welcome chooser closes on it).
    private let onSaved: (() -> Void)?

    init(onSaved: (() -> Void)? = nil) {
        self.onSaved = onSaved
    }

    private static let defaultBlue = Color(hex: "#4FA3D8")

    private var custom: SavedLocation? { candidate ?? model.preferences.custom }
    private var customIsSelected: Bool { model.preferences.effectiveUseCustom && candidate == nil }
    private var hasUnsavedCandidate: Bool { candidate != nil && candidate != model.preferences.custom }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BackHeader(title: "Location")
                defaultCard
                caption("One custom location. Pick the default above at any time with one tap; it never moves.")
                customCard
                caption("The custom point is snapped to the nearest HRRR grid cell (3 km) when saved; the name is yours.")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Tokens.ground(scheme))
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            #if DEBUG
            // `WW_CANDIDATE="Name,lat,lon"`: propose an unsaved point at launch (screenshots).
            if let spec = model.environment["WW_CANDIDATE"] {
                let parts = spec.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 3, let lat = Double(parts[1]), let lon = Double(parts[2]) {
                    propose(SavedLocation(name: parts[0], lat: lat, lon: lon, tz: TimeZone.current.identifier))
                    return
                }
            }
            #endif
            if let custom = model.preferences.custom {
                camera = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: custom.lat, longitude: custom.lon),
                    span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)))
            }
        }
    }

    // MARK: Cards

    private var defaultCard: some View {
        Button {
            model.selectDefault()
            candidate = nil
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(SavedLocation.portTownsendBay.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Tokens.inkPrimary(scheme))
                    Text("Default · \(SavedLocation.portTownsendBay.coordinateText) · HRRR point")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                }
                Spacer()
                selectionMark(selected: !model.preferences.effectiveUseCustom)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Default location, \(SavedLocation.portTownsendBay.name)")
        .accessibilityAddTraits(model.preferences.effectiveUseCustom ? [] : .isSelected)
    }

    private var customCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let custom {
                        Text(custom.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Tokens.inkPrimary(scheme))
                            .lineLimit(1)
                        Text(custom.coordinateText)
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(Tokens.inkSecondary(scheme))
                    } else {
                        Text("Custom location")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Tokens.inkDisabled(scheme))
                        Text("Search below or long-press the map")
                            .font(.system(size: 13))
                            .foregroundStyle(Tokens.inkSecondary(scheme))
                    }
                }
                Spacer()
                if hasUnsavedCandidate, let candidate {
                    // No Save for a point outside the HRRR grid; `searchError` says why.
                    if candidate.isInHRRRCoverage {
                        Button { Task { await save(candidate) } } label: {
                            if isSaving { ProgressView().controlSize(.small) } else { Text("Save") }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(Tokens.trustAmber(scheme))
                        .foregroundStyle(Color.black)
                        .frame(minHeight: 44)
                        .disabled(isSaving)
                    }
                } else {
                    Button {
                        model.selectCustom()
                    } label: {
                        selectionMark(selected: customIsSelected)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.preferences.custom == nil)
                    .accessibilityLabel(custom.map { "Use \($0.name)" } ?? "Use custom location")
                }
            }
            searchField
            if let searchError {
                Text(searchError)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.trustAmber(scheme))
            }
            map
            legend
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Tokens.inkSecondary(scheme))
            .padding(.horizontal, 4)
    }

    /// Filled check in the default blue (`bft.2`) when selected, an empty ring otherwise.
    private func selectionMark(selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(selected ? Self.defaultBlue : Tokens.inkSecondary(scheme))
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Tokens.inkSecondary(scheme))
            TextField("Search a place or paste lat, lon", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
                .foregroundStyle(Tokens.inkPrimary(scheme))
            if isSearching { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Tokens.ground(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func search() async {
        searchError = nil
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if let coords = SavedLocation.parseCoordinates(text) {
            propose(SavedLocation(name: "Custom point", lat: coords.lat, lon: coords.lon, tz: TimeZone.current.identifier))
            return
        }
        isSearching = true
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.address, .pointOfInterest]
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else {
                searchError = "No place found for “\(text)”."
                return
            }
            let coordinate: CLLocationCoordinate2D
            if #available(iOS 26, *) {
                coordinate = item.location.coordinate
            } else {
                coordinate = item.placemark.coordinate
            }
            propose(SavedLocation(
                name: item.name ?? text,
                lat: coordinate.latitude, lon: coordinate.longitude,
                tz: item.timeZone?.identifier ?? TimeZone.current.identifier))
        } catch {
            searchError = "Search failed. Check the connection and try again."
        }
    }

    private func propose(_ location: SavedLocation) {
        candidate = location
        searchError = location.isInHRRRCoverage ? nil : HRRRCoverage.outsideText
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: location.lat, longitude: location.lon),
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)))
    }

    private func pin(at coordinate: CLLocationCoordinate2D) async {
        var name = "Dropped pin"
        var tz = TimeZone.current.identifier
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if #available(iOS 26, *) {
            if let request = MKReverseGeocodingRequest(location: location),
               let item = try? await request.mapItems.first {
                name = item.name ?? item.address?.shortAddress ?? name
                tz = item.timeZone?.identifier ?? tz
            }
        } else if let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            // iOS 18–25: the pre-26 geocoder gives the same name and time zone.
            name = mark.name ?? mark.locality ?? name
            tz = mark.timeZone?.identifier ?? tz
        }
        propose(SavedLocation(name: name, lat: coordinate.latitude, lon: coordinate.longitude, tz: tz))
    }

    /// Fetches the point before switching to it; the server can still refuse one at the grid edge.
    private func save(_ location: SavedLocation) async {
        isSaving = true
        defer { isSaving = false }
        switch await model.trySaveCustom(location) {
        case .saved:
            candidate = nil
            searchError = nil
            onSaved?()
        case .outsideCoverage:
            searchError = HRRRCoverage.outsideText
        }
    }

    // MARK: Map

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                Annotation(SavedLocation.portTownsendBay.name,
                           coordinate: CLLocationCoordinate2D(latitude: SavedLocation.portTownsendBay.lat, longitude: SavedLocation.portTownsendBay.lon)) {
                    dot(Self.defaultBlue)
                }
                if let custom {
                    Annotation(custom.name, coordinate: CLLocationCoordinate2D(latitude: custom.lat, longitude: custom.lon)) {
                        dot(Tokens.trustAmber(.dark))
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { value in
                        if case .second(true, let drag?) = value, let coordinate = proxy.convert(drag.location, from: .local) {
                            Task { await pin(at: coordinate) }
                        }
                    }
            )
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Text("Long-press to pin")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.inkBody(.dark))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Tokens.ground(.dark).opacity(0.85), in: Capsule())
                .padding(12)
        }
        .accessibilityLabel("Map. Long-press to drop a custom pin.")
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(radius: 2)
    }

    private var legend: some View {
        HStack(spacing: 18) {
            HStack(spacing: 10) {
                Circle().fill(Self.defaultBlue).frame(width: 10, height: 10)
                Text("default")
            }
            HStack(spacing: 10) {
                Circle().fill(Tokens.trustAmber(.dark)).frame(width: 10, height: 10)
                Text("custom pin")
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Tokens.inkSecondary(scheme))
    }
}
