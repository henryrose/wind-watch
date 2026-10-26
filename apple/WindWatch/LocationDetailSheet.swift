import MapKit
import SwiftUI
import WindCore

/// Location-naming handoff §2–§3 (`docs/location-naming/`): one sheet for a new pin (`New Location`
/// · Save) and for an existing row's ⓘ (its name · Done · Delete Location). Name field first, a
/// helper line, a non-interactive map of the pin and its 3 km HRRR cell, POSITION / FORECAST
/// POINT tiles, and suggestion chips. Renaming never moves the pin or changes the forecast point.
struct LocationDetailSheet: View {
    enum Mode: Identifiable {
        case new(SavedLocation, chips: [String])
        case existing(SavedLocation)

        var id: UUID {
            switch self {
            case .new(let l, _), .existing(let l): l.id
            }
        }
    }

    let mode: Mode
    /// Called after a new location is saved (the Welcome chooser closes on it).
    var onSaved: (() -> Void)?

    @Environment(ForecastSession.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool
    @State private var probe: ForecastSession.PointProbe?
    @State private var probeFailed = false
    @State private var error: String?
    @State private var isSaving = false
    @State private var confirmDiscard = false
    @State private var confirmDelete = false

    private static let blue = Color(hex: "#4FA3D8")
    private static let red = Color(hex: "#FF453A")
    private static let ground = Color(hex: "#0B0E12")
    private static let clearPlate = Color(hex: "#3A424D")

    init(mode: Mode, onSaved: (() -> Void)? = nil) {
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case .new(let l, _): _name = State(initialValue: l.name)
        case .existing(let l): _name = State(initialValue: l.name)
        }
    }

    private var location: SavedLocation {
        switch mode {
        case .new(let l, _): l
        case .existing(let l): model.preferences.locations.first { $0.id == l.id } ?? l
        }
    }

    private var isNew: Bool { if case .new = mode { true } else { false } }
    private var original: String {
        switch mode {
        case .new(let l, _): l.name
        case .existing(let l): l.name
        }
    }

    private var clean: String { LocationName.normalize(name) }
    private var isDirty: Bool { clean != LocationName.normalize(original) }
    private var canSave: Bool { !clean.isEmpty && !isSaving }

    private var chips: [String] {
        let base: [String]
        switch mode {
        case .new(_, let chips): base = chips
        case .existing(let l): base = [l.suggestedName].compactMap { $0 }
        }
        return base.filter { $0.lowercased() != clean.lowercased() }.prefix(4).map { $0 }
    }

    private var duplicate: String? {
        let others = model.preferences.locations.filter { $0.id != location.id }.map(\.name)
        return LocationName.duplicateSuggestion(for: name, among: others)
    }

    private var cell: (lat: Double, lon: Double)? {
        if let lat = location.cellLat, let lon = location.cellLon { return (lat, lon) }
        if let probe { return (probe.cellLat, probe.cellLon) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            navRow
                .padding(.top, 14)
            VStack(alignment: .leading, spacing: 6) {
                Text("NAME")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.26)
                    .foregroundStyle(Tokens.inkSecondary(.dark))
                nameField
                helper
            }
            .padding(.top, 14)
            mapThumbnail
                .padding(.top, 16)
            tiles
                .padding(.top, 12)
            if !chips.isEmpty {
                chipRow
                    .padding(.top, 12)
            }
            if let error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.trustAmber(.dark))
                    .padding(.top, 10)
            }
            Spacer(minLength: 16)
            if !isNew, model.preferences.canDelete {
                Button { confirmDelete = true } label: {
                    Text("Delete Location")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Self.red)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Self.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.card(.dark))
        .environment(\.colorScheme, .dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Tokens.card(.dark))
        // SwiftUI cannot intercept a swipe to ask first, so a changed name blocks the swipe and
        // Cancel asks "Discard Changes?" instead.
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog("Discard Changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(location.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.delete(location.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            if isNew {
                // Select the whole suggestion once the field has focus, so typing replaces it.
                focused = true
                try? await Task.sleep(for: .milliseconds(450))
                selection = TextSelection(range: name.startIndex..<name.endIndex)
            }
            if cell == nil {
                switch await model.probe(location) {
                case .found(let p): probe = p
                case .outsideCoverage: error = HRRRCoverage.outsideText
                case .unavailable: probeFailed = true
                }
            }
        }
    }

    // MARK: Nav row

    private var navRow: some View {
        ZStack {
            Text(isNew ? "New Location" : location.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tokens.inkPrimary(.dark))
                .lineLimit(1)
                .padding(.horizontal, 80)
            HStack {
                Button("Cancel") { isDirty ? (confirmDiscard = true) : dismiss() }
                    .font(.system(size: 17))
                    .foregroundStyle(Self.blue)
                Spacer()
                Button { Task { await save() } } label: {
                    if isSaving { ProgressView().controlSize(.small) } else { Text(isNew ? "Save" : "Done") }
                }
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(canSave ? Self.blue : Tokens.inkDisabled(.dark))
                .disabled(!canSave)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 44)
    }

    // MARK: Name

    private var nameField: some View {
        HStack(spacing: 8) {
            TextField("Name this spot", text: $name, selection: $selection)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Tokens.inkPrimary(.dark))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { if canSave { Task { await save() } } }
                .onChange(of: name) { _, new in
                    if new.count > LocationName.maxLength { name = String(new.prefix(LocationName.maxLength)) }
                }
                .accessibilityLabel("Name")
            if !name.isEmpty {
                Button {
                    name = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Self.ground)
                        .frame(width: 28, height: 28)
                        .background(Self.clearPlate, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear name")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(Self.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .inset(by: 0.75)
                .stroke(focused ? Self.blue : Color.clear, lineWidth: 1.5)
        }
    }

    private var helper: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isNew
                 ? "Suggested from the map. Change it to what you call this spot; your name is never overwritten."
                 : "Renaming does not move the pin or change the forecast point.")
            if let duplicate {
                HStack(spacing: 6) {
                    Text("Another location has this name.")
                    Button("Use “\(duplicate)”") { name = duplicate }
                        .foregroundStyle(Self.blue)
                        .buttonStyle(.plain)
                }
            }
        }
        .font(.system(size: 13))
        .lineSpacing(2)
        .foregroundStyle(Tokens.inkSecondary(.dark))
    }

    // MARK: Map

    /// 150 pt, radius 12, non-interactive: the pin and the 3 km HRRR cell as a dashed square.
    private var mapThumbnail: some View {
        let pin = CLLocationCoordinate2D(latitude: location.lat, longitude: location.lon)
        let centre = cell.map { CLLocationCoordinate2D(latitude: ($0.lat + location.lat) / 2, longitude: ($0.lon + location.lon) / 2) } ?? pin
        return Map(initialPosition: .region(MKCoordinateRegion(center: centre, span: MKCoordinateSpan(latitudeDelta: 0.07, longitudeDelta: 0.07))),
                   interactionModes: []) {
            if let cell {
                MapPolygon(coordinates: Self.square(lat: cell.lat, lon: cell.lon, halfKm: 1.5))
                    .foregroundStyle(Self.blue.opacity(0.12))
                    .stroke(Self.blue.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                Annotation("", coordinate: Self.corner(lat: cell.lat, lon: cell.lon, halfKm: 1.5), anchor: .bottomLeading) {
                    Text("3 km HRRR cell")
                        .font(.system(size: 10))
                        .foregroundStyle(Tokens.inkSecondary(.dark))
                        .padding(.leading, 4)
                }
            }
            Annotation("", coordinate: pin, anchor: .bottom) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Self.ground, Self.blue)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityLabel("Map of the pin and its 3 km HRRR cell")
    }

    private static func offsets(lat: Double, halfKm: Double) -> (dLat: Double, dLon: Double) {
        (halfKm / 111.0, halfKm / (111.0 * cos(lat * .pi / 180)))
    }

    private static func square(lat: Double, lon: Double, halfKm: Double) -> [CLLocationCoordinate2D] {
        let d = offsets(lat: lat, halfKm: halfKm)
        return [(1, -1), (1, 1), (-1, 1), (-1, -1)].map {
            CLLocationCoordinate2D(latitude: lat + Double($0.0) * d.dLat, longitude: lon + Double($0.1) * d.dLon)
        }
    }

    private static func corner(lat: Double, lon: Double, halfKm: Double) -> CLLocationCoordinate2D {
        let d = offsets(lat: lat, halfKm: halfKm)
        return CLLocationCoordinate2D(latitude: lat + d.dLat, longitude: lon + d.dLon)
    }

    // MARK: Tiles and chips

    private var tiles: some View {
        HStack(spacing: 10) {
            tile("POSITION", location.coordinateText)
            tile("FORECAST POINT", forecastPointText)
        }
    }

    private var forecastPointText: String {
        if let cell { return ForecastPoint.text(pinLat: location.lat, pinLon: location.lon, cellLat: cell.lat, cellLon: cell.lon) }
        if error != nil { return "outside HRRR" }
        return probeFailed ? "nearest 3 km cell" : "finding…"
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Tokens.inkSecondary(.dark))
            Text(value)
                .font(.system(size: 15).monospacedDigit())
                .foregroundStyle(Tokens.inkPrimary(.dark))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.ground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var chipRow: some View {
        FlowLayout(spacing: 8) {
            Text("Suggestions:")
                .font(.system(size: 13))
                .foregroundStyle(Tokens.inkSecondary(.dark))
                .frame(height: 30)
            ForEach(chips, id: \.self) { chip in
                Button {
                    name = chip
                    focused = true
                    selection = TextSelection(range: name.endIndex..<name.endIndex)
                } label: {
                    Text(chip)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.inkBody(.dark))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Self.ground, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chip)
                .accessibilityHint("Uses this name")
            }
        }
    }

    // MARK: Save

    private func save() async {
        guard canSave else { return }
        if isNew {
            isSaving = true
            defer { isSaving = false }
            var row = location
            row.name = clean
            switch await model.tryAdd(row, probe: probe) {
            case .saved:
                dismiss()
                onSaved?()
            case .outsideCoverage:
                error = HRRRCoverage.outsideText
            case .full:
                error = "List full — delete a location first."
            }
        } else {
            model.rename(location.id, to: clean)
            dismiss()
        }
    }
}

/// Wrapping row for the suggestion chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
