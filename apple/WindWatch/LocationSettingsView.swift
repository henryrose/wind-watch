import MapKit
import SwiftUI
import WindCore

/// HANDOFF §8.3 rounds four–five / `Phone-Location.dc.html`, `Phone-Location-Full.dc.html`: one
/// list of up to 12 equal locations. Tap a row to switch; swipe left to delete; the permanent
/// Edit button shows minus buttons (two-tap delete) and drag handles. The last location can't be
/// deleted. Under the list: search, then a 250 pt map with every location pinned (selected blue,
/// others white) where a long-press drops a new pin; a new point is named, then added. At 12 of
/// 12 the screen opens in Edit mode with a "List full" banner and long-press shows a toast.
struct LocationSettingsView: View {
    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var editMode: EditMode = .inactive
    @State private var query = ""
    @State private var candidate: SavedLocation?
    @State private var searchError: String?
    @State private var isSearching = false
    @State private var isSaving = false
    @State private var toast: String?
    @State private var renaming: SavedLocation?
    @State private var renameText = ""
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: SavedLocation.portTownsendBay.lat, longitude: SavedLocation.portTownsendBay.lon),
            span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)
        )
    )

    /// Called after a location is added (the Welcome chooser closes on it).
    private let onSaved: (() -> Void)?

    init(onSaved: (() -> Void)? = nil) {
        self.onSaved = onSaved
    }

    private static let selectedBlue = Color(hex: "#4FA3D8")
    private var prefs: LocationSettings.Preferences { model.preferences }
    private var isEditing: Bool { editMode.isEditing }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if prefs.isFull {
                    fullBanner
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            Section {
                ForEach(prefs.locations) { location in
                    row(location)
                        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                        .listRowBackground(Tokens.card(scheme))
                        .listRowSeparatorTint(Tokens.hairline(scheme))
                        .deleteDisabled(!prefs.canDelete)
                }
                .onDelete { offsets in
                    for id in offsets.map({ prefs.locations[$0].id }) { model.delete(id) }
                }
                .onMove { source, destination in model.move(fromOffsets: source, toOffset: destination) }
            }
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if let candidate { candidateCard(candidate) }
                    searchField
                    if let searchError {
                        Text(searchError)
                            .font(.system(size: 13))
                            .foregroundStyle(Tokens.trustAmber(scheme))
                    }
                    map
                    Text("Tap a row to switch. Swipe left, or tap Edit, to delete or reorder — any location, including Port Townsend Bay. The selected location drives every surface; order is just order. The last remaining location can't be deleted.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                        .padding(.horizontal, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 24, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(12)
        .environment(\.defaultMinListRowHeight, 44)
        .scrollContentBackground(.hidden)
        .background(Tokens.ground(scheme))
        .environment(\.editMode, $editMode)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .center) { toastView }
        .alert("Rename location", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let renaming { model.rename(renaming.id, to: renameText) }
                renaming = nil
            }
        }
        .onAppear {
            if prefs.isFull { editMode = .active }
            center(on: prefs.selected, span: 0.6)
            #if DEBUG
            // `WW_CANDIDATE="Name,lat,lon"`: propose an unsaved point at launch (screenshots).
            if let spec = model.environment["WW_CANDIDATE"] {
                let parts = spec.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 3, let lat = Double(parts[1]), let lon = Double(parts[2]) {
                    propose(SavedLocation(name: parts[0], lat: lat, lon: lon, tz: TimeZone.current.identifier))
                }
            }
            #endif
        }
    }

    // MARK: Header

    /// Back chevron · `Locations` Bold 28 · `5 of 12` (13 Semibold secondary; `12 of 12 · full`
    /// in `ink.body`) · Edit / Done.
    private var header: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Tokens.inkPrimary(scheme))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -12)
            .accessibilityLabel("Back")
            Text("Locations")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Tokens.inkPrimary(scheme))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(prefs.isFull ? "\(prefs.locations.count) of \(LocationSettings.maxCount) · full" : "\(prefs.locations.count) of \(LocationSettings.maxCount)")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(prefs.isFull ? Tokens.inkBody(scheme) : Tokens.inkSecondary(scheme))
                .lineLimit(1)
            Button(isEditing ? "Done" : "Edit") {
                withAnimation { editMode = isEditing ? .inactive : .active }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Self.selectedBlue)
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.trailing, -6)
        }
        .padding(.top, 8)
    }

    private var fullBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 16, weight: .semibold))
            Text("List full (\(LocationSettings.maxCount)). Delete one to add a new pin.")
                .font(.system(size: 14))
        }
        .foregroundStyle(Tokens.inkBody(scheme))
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Tokens.hairline(scheme), lineWidth: 1))
    }

    // MARK: Rows

    /// 52 pt (44 in Edit mode): selection ring / check · name Semibold 16 · coords 12 secondary.
    private func row(_ location: SavedLocation) -> some View {
        let selected = location.id == prefs.selectedID
        return Button {
            guard !isEditing else { return }
            model.select(location.id)
            candidate = nil
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? Self.selectedBlue : Tokens.inkDisabled(scheme))
                VStack(alignment: .leading, spacing: 0) {
                    Text(location.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Tokens.inkPrimary(scheme))
                        .lineLimit(1)
                    Text(location.id == SavedLocation.portTownsendBay.id && !isEditing
                         ? location.coordinateText + " · added on first launch" : location.coordinateText)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: isEditing ? 44 : 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                renameText = location.name
                renaming = location
            }
            if prefs.canDelete {
                Button("Delete", systemImage: "trash", role: .destructive) { model.delete(location.id) }
            }
        }
        .accessibilityLabel("\(location.name), \(location.coordinateText)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(isEditing ? "" : "Shows this location's forecast")
    }

    // MARK: New point

    /// A proposed point: an editable name, its coordinates, and Add (amber). No Add for a point
    /// outside the HRRR grid; `searchError` says why.
    private func candidateCard(_ location: SavedLocation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Name", text: Binding(
                    get: { candidate?.name ?? "" },
                    set: { candidate?.name = $0 }))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tokens.inkPrimary(scheme))
                    .submitLabel(.done)
                if location.isInHRRRCoverage {
                    Button { Task { await add(location) } } label: {
                        if isSaving { ProgressView().controlSize(.small) } else { Text("Add") }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Tokens.trustAmber(scheme))
                    .foregroundStyle(Color.black)
                    .frame(minHeight: 44)
                    .disabled(isSaving || location.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button { candidate = nil; searchError = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                        .frame(width: 32, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Discard this point")
            }
            Text(location.coordinateText + " · nearest 3 km HRRR cell")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Tokens.inkSecondary(scheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Tokens.trustAmber(scheme).opacity(0.6), lineWidth: 1))
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
                .disabled(prefs.isFull)
            if isSearching { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(prefs.isFull ? 0.5 : 1)
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

    /// Fetches the point before adding it; the server can still refuse one at the grid edge.
    private func add(_ location: SavedLocation) async {
        isSaving = true
        defer { isSaving = false }
        switch await model.tryAdd(location) {
        case .saved:
            candidate = nil
            searchError = nil
            query = ""
            onSaved?()
        case .outsideCoverage:
            searchError = HRRRCoverage.outsideText
        case .full:
            showToast("List full — delete a location first")
        }
    }

    private func center(on location: SavedLocation, span: Double) {
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: location.lat, longitude: location.lon),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)))
    }

    // MARK: Map

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                ForEach(prefs.locations) { location in
                    let selected = location.id == prefs.selectedID
                    Annotation(location.name, coordinate: CLLocationCoordinate2D(latitude: location.lat, longitude: location.lon)) {
                        pin(selected ? Self.selectedBlue : Color.white.opacity(0.9), size: selected ? 28 : 22)
                    }
                }
                if let candidate {
                    Annotation(candidate.name, coordinate: CLLocationCoordinate2D(latitude: candidate.lat, longitude: candidate.lon)) {
                        pin(Tokens.trustAmber(.dark), size: 26)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { value in
                        guard case .second(true, let drag?) = value else { return }
                        if prefs.isFull {
                            showToast("List full — delete a location first")
                        } else if let coordinate = proxy.convert(drag.location, from: .local) {
                            Task { await pin(at: coordinate) }
                        }
                    }
            )
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if !prefs.isFull {
                Text("Long-press the map to add a location")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tokens.inkBody(.dark))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Tokens.ground(.dark).opacity(0.85), in: Capsule())
                    .padding(12)
            }
        }
        .accessibilityLabel("Map of your locations. Long-press to add a location.")
    }

    /// Map pin: a teardrop with a dark eye (`Phone-Location.dc.html`).
    private func pin(_ color: Color, size: CGFloat) -> some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: size * 0.8, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color(hex: "#0E141B"), color)
            .shadow(radius: 2)
    }

    // MARK: Toast

    @ViewBuilder private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tokens.inkPrimary(.dark))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Tokens.ground(.dark).opacity(0.92), in: Capsule())
                .overlay(Capsule().stroke(Tokens.hairline(.dark), lineWidth: 1))
                .transition(.opacity)
                .accessibilityAddTraits(.isStaticText)
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { if toast == text { toast = nil } }
        }
    }
}
