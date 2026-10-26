import MapKit
import SwiftUI
import WindCore

/// HANDOFF §8.3 / `Phone-Location.dc.html`, `Phone-Location-Full.dc.html`: one list of up to 12
/// equal locations (tap = select, ⓘ = naming sheet, swipe or the permanent `EditButton` = delete
/// and reorder; the last row can't be deleted), then search, a 250 pt map with every pin and the
/// long-press hint, and a caption. At 12 of 12 it opens in Edit mode with a banner, and a map
/// long-press shows a toast instead of adding.
///
/// Debug switches (with `WW_SCREEN=location`): `WW_SHEET=new|edit` opens the naming sheet for a
/// sample pin or the selected row; `WW_CANDIDATE="Name,lat,lon"` opens it for that point;
/// `WW_TOAST=1` pins the list-full toast; `WW_SEARCH="text"` / `WW_PIN="lat,lon"` run the real
/// search or long-press naming path. `WW_LOCATIONS=<n>` (ForecastSession) seeds the list.
struct LocationSettingsView: View {
    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme

    @State private var editMode: EditMode = .inactive
    @State private var query = ""
    @State private var searchError: String?
    @State private var isBusy = false
    @State private var sheet: LocationSheetItem?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var camera: MapCameraPosition = .automatic

    /// Called after a new location is saved (the Welcome chooser closes on it).
    private let onSaved: (() -> Void)?

    init(onSaved: (() -> Void)? = nil) {
        self.onSaved = onSaved
    }

    private static let blue = Color(hex: "#4FA3D8")
    private static let fullToast = "List full \u{2014} delete a location first"

    private var prefs: LocationSettings.Preferences { model.preferences }
    private var isEditing: Bool { editMode.isEditing }

    var body: some View {
        ScrollViewReader { scroller in
            list
                .onAppear {
                    #if DEBUG
                    // `WW_TOAST=1`: bring the map (and its toast) on screen for the screenshot.
                    if model.environment["WW_TOAST"] == "1" {
                        Task { try? await Task.sleep(for: .seconds(1)); scroller.scrollTo("map", anchor: .bottom) }
                    }
                    #endif
                }
        }
    }

    private var list: some View {
        List {
            header
                .plainRow(top: 8, bottom: 6)
            if prefs.isFull {
                banner.plainRow(top: 0, bottom: 12)
            }
            ForEach(Array(prefs.locations.enumerated()), id: \.element.id) { index, location in
                row(location)
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                    .listRowSeparator(.hidden)
                    .listRowBackground(rowBackground(index: index))
                    .deleteDisabled(!prefs.canDelete)
            }
            .onDelete { offsets in
                for id in offsets.map({ prefs.locations[$0].id }) { model.deleteLocation(id) }
            }
            .onMove { model.moveLocations(fromOffsets: $0, toOffset: $1) }
            searchField.plainRow(top: 12, bottom: 0)
            if let searchError {
                Text(searchError)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.trustAmber(scheme))
                    .plainRow(top: 8, bottom: 0)
            }
            map.plainRow(top: 12, bottom: 0).id("map")
            Text("Tap a row to switch; tap \u{24D8} to rename it or see its details. Swipe left, or tap Edit, to delete or reorder \u{2014} any location, including Port Townsend Bay. The last remaining location can\u{2019}t be deleted.")
                .font(.system(size: 12))
                .lineSpacing(5)
                .foregroundStyle(Tokens.inkSecondary(scheme))
                .padding(.horizontal, 4)
                .plainRow(top: 12, bottom: 24)
        }
        .listStyle(.plain)
        // The 16 pt gutter is a content margin, so the Edit-mode minus buttons land inside the card.
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Tokens.ground(scheme))
        .environment(\.editMode, $editMode)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { item in
            LocationSheet(item: item, onSaved: onSaved)
        }
        .onAppear(perform: appear)
        .onChange(of: prefs.isFull) { _, full in
            if full { withAnimation { editMode = .active } }
        }
    }

    private func appear() {
        // Full: land in Edit mode so the way out (delete) is one tap away.
        if prefs.isFull { editMode = .active }
        #if DEBUG
        let env = model.environment
        if env["WW_TOAST"] == "1" { toast = Self.fullToast }
        switch env["WW_SHEET"] {
        case "new":
            sheet = .new(LocationDraft(lat: 48.100, lon: -122.683, tz: "America/Los_Angeles",
                                       suggestion: "Marrowstone Island", chips: ["Nordland", "Kilisut Harbor"]))
        case "edit":
            sheet = .existing(prefs.selectedID)
        default:
            break
        }
        // `WW_SEARCH="text"` / `WW_PIN="lat,lon"`: run the real search or long-press path (network).
        if let text = env["WW_SEARCH"] {
            query = text
            Task { await search() }
        }
        if let spec = env["WW_PIN"], let coords = SavedLocation.parseCoordinates(spec) {
            Task { await propose(lat: coords.lat, lon: coords.lon, searchName: nil, tz: nil) }
        }
        if let spec = env["WW_CANDIDATE"] {
            let parts = spec.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 3, let lat = Double(parts[1]), let lon = Double(parts[2]) {
                sheet = .new(LocationDraft(lat: lat, lon: lon, tz: TimeZone.current.identifier, suggestion: parts[0], chips: []))
            }
        }
        #endif
    }

    // MARK: Header and banner

    private var header: some View {
        BackHeader {
            HStack(spacing: 8) {
                BackHeaderTitle(text: "Locations")
                Spacer(minLength: 8)
                Text(prefs.isFull ? "\(prefs.count) of \(LocationSettings.Preferences.maxCount) \u{00B7} full"
                                  : "\(prefs.count) of \(LocationSettings.Preferences.maxCount)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(prefs.isFull ? Tokens.inkBody(scheme) : Tokens.inkSecondary(scheme))
                EditButton()
                    .font(.system(size: 17, weight: .semibold))
                    .tint(Self.blue)
                    .foregroundStyle(Self.blue)
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.trailing, -10)
            }
        }
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 18))
            Text("List full (\(LocationSettings.Preferences.maxCount)). Delete one to add a new pin.")
                .font(.system(size: 13))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Tokens.inkBody(scheme))
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Tokens.hairline(scheme), lineWidth: 1))
    }

    // MARK: Rows

    private func row(_ location: SavedLocation) -> some View {
        let selected = location.id == prefs.selectedID
        return HStack(spacing: 8) {
            Button {
                model.select(location.id)
            } label: {
                HStack(spacing: 12) {
                    selectionMark(selected)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(location.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Tokens.inkPrimary(scheme))
                            .lineLimit(1)
                        Text(location.coordinateText + (location.isServerDefault && !isEditing ? " \u{00B7} added on first launch" : ""))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(Tokens.inkSecondary(scheme))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: isEditing ? 44 : 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(location.name)
            .accessibilityHint(selected ? "" : "Shows this location's forecast")
            .accessibilityAddTraits(selected ? .isSelected : [])
            if !isEditing {
                Button {
                    sheet = .existing(location.id)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(Self.blue)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .padding(.trailing, -10)
                .accessibilityLabel("Details for \(location.name)")
            }
        }
    }

    /// Filled blue check (dark tick) when selected; a 2.5 pt `ink.disabled` ring otherwise. 24 pt.
    @ViewBuilder
    private func selectionMark(_ selected: Bool) -> some View {
        if selected {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Tokens.ground(scheme), Self.blue)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 24, height: 24)
        } else {
            Circle()
                .strokeBorder(Tokens.inkDisabled(scheme), lineWidth: 2.5)
                .frame(width: 22, height: 22)
                .padding(1)
        }
    }

    /// The card is drawn per row: rounded top on the first, rounded bottom and no hairline on the last.
    private func rowBackground(index: Int) -> some View {
        let first = index == 0, last = index == prefs.count - 1
        return UnevenRoundedRectangle(topLeadingRadius: first ? 14 : 0, bottomLeadingRadius: last ? 14 : 0,
                                      bottomTrailingRadius: last ? 14 : 0, topTrailingRadius: first ? 14 : 0,
                                      style: .continuous)
            .fill(Tokens.card(scheme))
            .overlay(alignment: .bottom) {
                if !last { Rectangle().fill(Color(hex: "#222831")).frame(height: 1) }
            }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Tokens.inkSecondary(scheme))
            TextField("", text: $query, prompt: Text("Search a place or paste lat, lon").foregroundStyle(Tokens.inkSecondary(scheme)))
                .font(.system(size: 16))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
                .foregroundStyle(Tokens.inkPrimary(scheme))
            if isBusy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func search() async {
        searchError = nil
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        guard !prefs.isFull else { return showToast(Self.fullToast) }
        isBusy = true
        defer { isBusy = false }
        if let coords = SavedLocation.parseCoordinates(text) {
            await propose(lat: coords.lat, lon: coords.lon, searchName: nil, tz: nil)
            return
        }
        do {
            guard let hit = try await PlaceNamer.search(text) else {
                searchError = "No place found for \u{201C}\(text)\u{201D}."
                return
            }
            await propose(lat: hit.lat, lon: hit.lon, searchName: hit.name ?? text, tz: hit.tz)
        } catch {
            searchError = "Search failed. Check the connection and try again."
        }
    }

    /// Refuses a point outside HRRR before naming it; otherwise names it once and opens the sheet.
    private func propose(lat: Double, lon: Double, searchName: String?, tz: String?) async {
        guard HRRRCoverage.contains(lat: lat, lon: lon) else {
            searchError = HRRRCoverage.outsideText
            return
        }
        searchError = nil
        let draft = searchName == nil
            ? await PlaceNamer.draft(lat: lat, lon: lon)
            : await PlaceNamer.draft(searchName: searchName, lat: lat, lon: lon, tz: tz)
        camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)))
        sheet = .new(draft)
    }

    // MARK: Map

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                ForEach(prefs.locations) { location in
                    let selected = location.id == prefs.selectedID
                    Annotation(location.name, coordinate: CLLocationCoordinate2D(latitude: location.lat, longitude: location.lon), anchor: .bottom) {
                        LocationPinGlyph(selected: selected)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { value in
                        guard case .second(true, let drag?) = value, let coordinate = proxy.convert(drag.location, from: .local) else { return }
                        guard !prefs.isFull else { return showToast(Self.fullToast) }
                        guard !isBusy else { return }
                        Task {
                            isBusy = true
                            defer { isBusy = false }
                            await propose(lat: coordinate.latitude, lon: coordinate.longitude, searchName: nil, tz: nil)
                        }
                    }
            )
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Text("Long-press the map to add a location")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.inkBody(scheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Tokens.ground(scheme).opacity(0.85), in: Capsule())
                .padding(.leading, 12)
                .padding(.bottom, 34) // clear of the Maps logo and Legal link
                .allowsHitTesting(false)
        }
        .overlay {
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.inkPrimary(scheme))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(Tokens.ground(scheme).opacity(0.92), in: Capsule())
                    .overlay(Capsule().strokeBorder(Tokens.hairline(scheme), lineWidth: 1))
                    .fixedSize()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("Map of your locations. Long-press to add one.")
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation { toast = text }
        AccessibilityNotification.Announcement(text).post()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }
}

/// Map pin (`Phone-Location.dc.html`): a teardrop with a dark eye, blue and larger for the
/// selected location, white for the others.
struct LocationPinGlyph: View {
    let selected: Bool

    var body: some View {
        let width: CGFloat = selected ? 26 : 19
        ZStack(alignment: .top) {
            Image(systemName: "drop.fill")
                .resizable()
                .scaledToFit()
                .rotationEffect(.degrees(180))
                .foregroundStyle(selected ? Color(hex: "#4FA3D8") : Color(hex: "#E6E9ED"))
            Circle()
                .fill(Color(hex: "#0E141B"))
                .frame(width: width * 0.3, height: width * 0.3)
                .padding(.top, width * 0.33)
        }
        .frame(width: width, height: width * 1.38)
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }
}

private extension View {
    /// A full-width list row with no card and no separator (the List supplies the 16 pt gutters).
    func plainRow(top: CGFloat, bottom: CGFloat) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
