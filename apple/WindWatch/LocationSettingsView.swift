import MapKit
import SwiftUI
import WindCore

/// HANDOFF §8.3 rounds four–five / `Phone-Location.dc.html`, `Phone-Location-Full.dc.html`: one
/// list of up to 12 equal locations. Tap a row to switch; swipe left to delete; the permanent
/// Edit button shows minus buttons (two-tap delete) and drag handles. The last location can't be
/// deleted. Each row's ⓘ opens `LocationDetailSheet` (rename, position, forecast point, delete).
/// Under the list: search, then a 250 pt map with every location pinned (selected blue, others
/// white) where a long-press drops a new pin; a new pin or search result is reverse-geocoded once
/// and opens the sheet as `New Location`. At 12 of 12 the screen opens in Edit mode with a
/// "List full" banner and long-press shows a toast.
struct LocationSettingsView: View {
    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var editMode: EditMode = .inactive
    @State private var query = ""
    /// A pin being named: drawn amber while the geocoder runs.
    @State private var placing: SavedLocation?
    @State private var detail: LocationDetailSheet.Mode?
    @State private var searchError: String?
    @State private var isSearching = false
    @State private var toast: String?
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
                    searchField
                    if let searchError {
                        Text(searchError)
                            .font(.system(size: 13))
                            .foregroundStyle(Tokens.trustAmber(scheme))
                    }
                    map
                    Text("Tap a row to switch; tap ⓘ to rename it or see its details. Swipe left, or tap Edit, to delete or reorder — any location, including Port Townsend Bay. The last remaining location can't be deleted.")
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
        .sheet(item: $detail) { mode in
            LocationDetailSheet(mode: mode) {
                query = ""
                onSaved?()
            }
            .environment(model)
        }
        .onAppear {
            if prefs.isFull { editMode = .active }
            center(on: prefs.selected, span: 0.6)
            #if DEBUG
            // `WW_CANDIDATE="Name,lat,lon"` opens the sheet for a new point (chips from
            // `WW_CHIPS="A|B|C"`); `WW_DETAILS=<row>` opens it for an existing row (screenshots).
            if let spec = model.environment["WW_CANDIDATE"] {
                let parts = spec.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 3, let lat = Double(parts[1]), let lon = Double(parts[2]) {
                    let chips = model.environment["WW_CHIPS"].map { $0.split(separator: "|").map(String.init) } ?? []
                    detail = .new(SavedLocation(name: parts[0], lat: lat, lon: lon, tz: TimeZone.current.identifier,
                                                suggestedName: parts[0]), chips: chips)
                }
            } else if let row = model.environment["WW_DETAILS"].flatMap(Int.init), prefs.locations.indices.contains(row) {
                detail = .existing(prefs.locations[row])
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
        HStack(spacing: 4) {
            selectButton(location)
            if !isEditing {
                Button { detail = .existing(location) } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(Self.selectedBlue)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Details for \(location.name)")
            }
        }
    }

    private func selectButton(_ location: SavedLocation) -> some View {
        let selected = location.id == prefs.selectedID
        return Button {
            guard !isEditing else { return }
            model.select(location.id)
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
        .buttonStyle(.borderless)
        .accessibilityLabel("\(location.name), \(location.coordinateText)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(isEditing ? "" : "Shows this location's forecast")
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
            await propose(lat: coords.lat, lon: coords.lon, preferredName: nil, tz: nil)
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
            await propose(lat: coordinate.latitude, lon: coordinate.longitude,
                          preferredName: item.name, tz: item.timeZone?.identifier)
        } catch {
            searchError = "Search failed. Check the connection and try again."
        }
    }

    /// A new point from a pin, a search result or pasted coordinates: refused outside the HRRR
    /// grid; otherwise reverse-geocoded once (§6) and opened in the sheet as `New Location`.
    private func propose(lat: Double, lon: Double, preferredName: String?, tz: String?) async {
        guard !prefs.isFull else {
            showToast("List full — delete a location first")
            return
        }
        let draft = SavedLocation(name: "", lat: lat, lon: lon, tz: tz ?? TimeZone.current.identifier)
        guard draft.isInHRRRCoverage else {
            searchError = HRRRCoverage.outsideText
            return
        }
        searchError = nil
        placing = draft
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)))
        let names = await PlaceNamer.suggest(lat: lat, lon: lon, preferred: preferredName)
        placing = nil
        var row = draft
        row.name = names.suggestion ?? ""
        row.suggestedName = names.suggestion
        if tz == nil, let zone = names.timeZone { row.tz = zone }
        detail = .new(row, chips: names.chips)
    }

    private func pin(at coordinate: CLLocationCoordinate2D) async {
        await propose(lat: coordinate.latitude, lon: coordinate.longitude, preferredName: nil, tz: nil)
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
                if let placing {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: placing.lat, longitude: placing.lon)) {
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
