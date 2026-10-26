import MapKit
import SwiftUI
import WindCore

/// What the naming sheet is for: a pin not yet saved, or a row's ⓘ.
enum LocationSheetItem: Identifiable, Equatable {
    case new(LocationDraft)
    case existing(UUID)

    var id: String {
        switch self {
        case .new(let draft): "new-\(draft.id)"
        case .existing(let id): "existing-\(id)"
        }
    }
}

/// HANDOFF §8.3 naming sheet / `Phone-Location-Edit.dc.html` (location-naming §3): Cancel ·
/// title · Save/Done; NAME field (pre-filled, focused and selected for a new pin); helper; map
/// thumbnail with the pin and its 3 km HRRR cell; POSITION / FORECAST POINT tiles; suggestion
/// chips; `Delete Location` for an existing row unless it is the last one. The name is stored
/// normalised and verbatim; nothing here moves the pin.
struct LocationSheet: View {
    let item: LocationSheetItem
    /// Called after a new pin is saved (the Welcome chooser closes on it).
    var onSaved: (() -> Void)?

    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var original = ""
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmDiscard = false
    @State private var confirmDelete = false

    private static let blue = Color(hex: "#4FA3D8")
    private static let red = Color(hex: "#FF453A")

    private var isNew: Bool { if case .new = item { true } else { false } }

    /// The row being edited, or the draft as a location.
    private var subject: SavedLocation? {
        switch item {
        case .new(let draft): draft.location
        case .existing(let id): model.preferences.location(id: id)
        }
    }

    private var isDirty: Bool { name != original }
    private var canSave: Bool { LocationName.isValid(name) && !isSaving }

    private var duplicate: String? {
        let others = model.preferences.locations.filter { $0.id != subject?.id }.map(\.name)
        return LocationName.duplicateSuggestion(for: name, existing: others)
    }

    private var chips: [String] {
        let current = LocationName.normalize(name).lowercased()
        return (subject?.suggestedNames ?? []).filter { $0.lowercased() != current }.prefix(GeocodedNames.maxChips).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            navRow
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    nameField
                    helper
                    if let subject {
                        CellThumbnail(lat: subject.lat, lon: subject.lon)
                            .padding(.top, 16)
                        tiles(subject)
                            .padding(.top, 16)
                    }
                    if !chips.isEmpty {
                        suggestions.padding(.top, 14)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            if !isNew, model.preferences.canDelete {
                deleteButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(Tokens.card(scheme))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Tokens.card(scheme))
        .interactiveDismissDisabled(isDirty)
        .onAppear(perform: start)
        .confirmationDialog("Discard Changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .confirmationDialog("Delete \u{201C}\(subject?.name ?? "")\u{201D}?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if case .existing(let id) = item { model.deleteLocation(id) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func start() {
        guard original.isEmpty, name.isEmpty else { return }
        switch item {
        case .new(let draft):
            name = draft.suggestion ?? ""
            original = name
            // Focus with the whole suggestion selected, so typing replaces it.
            Task { @MainActor in
                focused = true
                try? await Task.sleep(for: .milliseconds(350))
                selection = TextSelection(range: name.startIndex..<name.endIndex)
            }
        case .existing(let id):
            name = model.preferences.location(id: id)?.name ?? ""
            original = name
        }
    }

    // MARK: Nav row

    private var navRow: some View {
        HStack {
            Button("Cancel") {
                if isDirty { confirmDiscard = true } else { dismiss() }
            }
            .font(.system(size: 17))
            .foregroundStyle(Self.blue)
            Spacer(minLength: 8)
            Text(isNew ? "New Location" : (subject?.name ?? ""))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tokens.inkPrimary(scheme))
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(isNew ? "Save" : "Done") { Task { await save() } }
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(canSave ? Self.blue : Tokens.inkDisabled(scheme))
                .disabled(!canSave)
        }
        .buttonStyle(.plain)
        .frame(height: 44)
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    // MARK: Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NAME")
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.26)
                .foregroundStyle(Tokens.inkSecondary(scheme))
            HStack(spacing: 8) {
                TextField(text: $name, selection: $selection, prompt: Text(LocationName.placeholder).foregroundStyle(Tokens.inkDisabled(scheme))) {
                    Text("Name")
                }
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Tokens.inkPrimary(scheme))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { if canSave { Task { await save() } } }
                .onChange(of: name) { _, new in
                    let clamped = LocationName.clamp(new)
                    if clamped != new { name = clamped }
                }
                .accessibilityLabel("Name")
                if !name.isEmpty {
                    Button {
                        name = ""
                        focused = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Tokens.ground(scheme))
                            .frame(width: 28, height: 28)
                            .background(Color(hex: "#3A424D"), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear name")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
            .background(Tokens.ground(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Self.blue, lineWidth: 1.5)
                    .opacity(focused ? 1 : 0)
            }
        }
    }

    @ViewBuilder
    private var helper: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isNew
                 ? "Suggested from the map. Change it to what you call this spot; your name is never overwritten."
                 : "Renaming does not move the pin or change the forecast point.")
            if let duplicate {
                // Suggested, never blocking: Save stays enabled.
                Button {
                    name = duplicate
                } label: {
                    Text("Already in your list. Use \u{201C}\(duplicate)\u{201D}?")
                        .foregroundStyle(Self.blue)
                }
                .buttonStyle(.plain)
            }
            if let error {
                Text(error).foregroundStyle(Tokens.trustAmber(scheme))
            }
        }
        .font(.system(size: 13))
        .lineSpacing(3)
        .foregroundStyle(Tokens.inkSecondary(scheme))
        .padding(.top, 8)
    }

    // MARK: Tiles and chips

    private func tiles(_ location: SavedLocation) -> some View {
        HStack(spacing: 10) {
            tile("POSITION", location.coordinateText)
            tile("FORECAST POINT", HRRRCoverage.forecastPointText(lat: location.lat, lon: location.lon) ?? "Outside HRRR")
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Tokens.inkSecondary(scheme))
            Text(value)
                .font(.system(size: 15).monospacedDigit())
                .foregroundStyle(Tokens.inkPrimary(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.ground(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var suggestions: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            Text("Suggestions:")
                .font(.system(size: 13))
                .foregroundStyle(Tokens.inkSecondary(scheme))
                .frame(height: 28)
            ForEach(chips, id: \.self) { chip in
                Button {
                    name = chip
                    focused = true
                } label: {
                    Text(chip)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.inkBody(scheme))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Tokens.ground(scheme), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var deleteButton: some View {
        Button { confirmDelete = true } label: {
            Text("Delete Location")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Self.red)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Self.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Save

    private func save() async {
        guard canSave else { return }
        switch item {
        case .existing(let id):
            if isDirty { model.renameLocation(id, to: name) }
            dismiss()
        case .new(let draft):
            var location = draft.location
            location.name = LocationName.normalize(name)
            isSaving = true
            defer { isSaving = false }
            switch await model.tryAddLocation(location) {
            case .saved:
                dismiss()
                onSaved?()
            case .outsideCoverage:
                error = HRRRCoverage.outsideText
            case .full:
                error = "List full (\(LocationSettings.Preferences.maxCount)). Delete one to add a new pin."
            }
        }
    }
}

/// Non-interactive map: the pin and the dashed 3 km HRRR cell it resolves to, captioned.
struct CellThumbnail: View {
    let lat: Double
    let lon: Double

    private static let blue = Color(hex: "#4FA3D8")

    var body: some View {
        let pin = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let cell = HRRRCoverage.cell(lat: lat, lon: lon)
        let centre = cell.map { CLLocationCoordinate2D(latitude: ($0.lat + lat) / 2, longitude: ($0.lon + lon) / 2) } ?? pin
        Map(initialPosition: .region(MKCoordinateRegion(center: centre, latitudinalMeters: 9000, longitudinalMeters: 9000)),
            interactionModes: []) {
            if let cell {
                MapPolygon(coordinates: cell.corners.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                    .foregroundStyle(Self.blue.opacity(0.12))
                    .stroke(Self.blue.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                if let ne = cell.corners.dropFirst(2).first {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: ne.lat, longitude: ne.lon), anchor: .bottomLeading) {
                        Text("3 km HRRR cell")
                            .font(.system(size: 10))
                            .foregroundStyle(Tokens.inkSecondary(.dark))
                            .padding(.leading, 6)
                            .fixedSize()
                    }
                }
            }
            Annotation("", coordinate: pin, anchor: .bottom) {
                LocationPinGlyph(selected: true)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Map of the pin and its 3 kilometre HRRR cell")
    }
}

/// Lays children left to right, wrapping to a new line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(width: width, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            for (index, x) in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
            }
        }
    }

    private struct Row { var items: [(Int, CGFloat)] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.items.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row(y: row.y + row.height + lineSpacing)
            }
            row.items.append((index, row.items.isEmpty ? 0 : row.width + spacing))
            row.width = row.items.count == 1 ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
