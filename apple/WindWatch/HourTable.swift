import SwiftUI
import WindCore

/// The collapsible table (HANDOFF §6.4d): a 52 pt disclosure row (`Hourly table` Semibold 17 ·
/// `45 hours · Wed 9am → Fri 5am` 13 secondary · chevron) on a `card` plate, radius 12, margin 12;
/// tapping expands `HourTable` in place with a spring. Collapsed by default; the state persists in
/// `@AppStorage("hourlyTableExpanded")`. At accessibility sizes the row is 60 pt with a 32 pt label
/// and no caption (`Phone-Table-LargeType.dc.html`).
struct HourTableDisclosure: View {
    static let storageKey = "hourlyTableExpanded"

    let forecast: Forecast
    let now: Date
    let tier: AgeTier
    var range: ChartRange = .hours48

    @AppStorage(HourTableDisclosure.storageKey) private var expanded = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var ax: Bool { typeSize.isAccessibilitySize }

    /// `45 hours · Wed 9am → Fri 5am`, or in 7 d `7 days · NBM after Fri 5am`.
    private var caption: String {
        range == .days7 ? Derivations.weekTableCaption(forecast: forecast, now: now) : Derivations.tableCaption(forecast: forecast, now: now)
    }

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.35, bounce: 0.15)) { expanded.toggle() }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Hourly table")
                        .font(.system(size: ax ? 32 : 17, weight: .semibold))
                        .foregroundStyle(Tokens.inkPrimary(scheme))
                    if !ax {
                        Text(caption)
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(Tokens.inkSecondary(scheme))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: ax ? 17 : 12, weight: .bold))
                    .foregroundStyle(Tokens.inkSecondary(scheme))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .frame(width: ax ? 20 : 14, height: ax ? 20 : 14)
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .frame(minHeight: ax ? 60 : 52)
            .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .accessibilityLabel("Hourly table, \(caption)")
        .accessibilityValue(expanded ? "expanded" : "collapsed")
        .accessibilityAddTraits(.isButton)
        if expanded {
            HourTable(forecast: forecast, now: now, tier: tier, range: range)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

/// HANDOFF §8.1 item 5 / `Phone-Main.dc.html`: columns `56 | 56 | 56 | 1fr | 36 | 40` (gap 8, 8 pt
/// inner padding), 44 pt rows, row rules in `card`, a sticky day header (`Wed · kn · gust · from
/// · B · °F`) at each day change. From AX1 the row reflows to two lines (`Phone-Table-LargeType`).
/// In 7 d (§12a) the HRRR hours run to the seam, then a one-line header (`NBM from Fri 6am ·
/// 3-hourly`) and 3-hour rows labelled by span with a small `NBM` tag. The temperature column
/// (§12b) follows Beaufort; it is hidden under 360 pt and when the payload has no temperature.
struct HourTable: View {
    let forecast: Forecast
    let now: Date
    let tier: AgeTier
    var range: ChartRange = .hours48

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(TemperatureUnit.storageKey, store: .windShared) private var unit: TemperatureUnit = .fahrenheit
    @State private var width: CGFloat = 402

    /// One table row: an HRRR hour, the NBM header, or an NBM block.
    private enum Row: Hashable {
        case hour(Int)
        case nbmHeader
        case block(Int)
    }

    private struct Day: Identifiable {
        let id: Date
        let name: String
        var rows: [Row]
    }

    private var days: [Day] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = forecast.timeZone
        let first = max(forecast.heroIndex(at: now) ?? 0, 0)
        var rows: [(Date, Row)] = (first..<forecast.hours.count).map { (forecast.date(ofHour: $0), .hour($0)) }
        if range == .days7, let e = forecast.extended {
            rows.append((e.from, .nbmHeader))
            rows += e.blocks.indices.map { (e.blocks[$0].start, .block($0)) }
        }
        var out: [Day] = []
        for (date, row) in rows {
            let day = cal.startOfDay(for: date)
            if out.last?.id == day {
                out[out.count - 1].rows.append(row)
            } else {
                out.append(Day(id: day, name: TimeFormat.weekdayShort(date, tz: forecast.timeZone), rows: [row]))
            }
        }
        return out
    }

    private var numberInk: Color { Tokens.numberInk(scheme, tier: tier) }
    private var reflow: Bool { typeSize.isAccessibilitySize }
    /// The `°F` column: only with temperature data, and not under 360 pt (§12b).
    private var showsTemp: Bool { width >= 360 && forecast.hours.contains { $0.tempC != nil } }

    var body: some View {
        ForEach(days) { day in
            Section {
                ForEach(day.rows, id: \.self) { row in
                    switch row {
                    case .hour(let i):
                        self.row(date: forecast.date(ofHour: i), span: 1, hour: forecast.hours[i], nbm: false)
                            .overlay(alignment: .bottom) { rule }
                    case .nbmHeader:
                        nbmHeader
                    case .block(let b):
                        if let block = forecast.extended?.blocks[b] {
                            self.row(date: block.start, span: block.hours, hour: block.wind, nbm: true)
                                .overlay(alignment: .bottom) { rule }
                        }
                    }
                }
            } header: {
                // AX rows carry `Wed 21:00` themselves; no day header (`Phone-Table-LargeType`).
                if !reflow { header(day) }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityLabel("Hourly forecast table")
    }

    private var rule: some View {
        Rectangle()
            .fill(Tokens.card(scheme))
            .frame(height: 1)
    }

    /// `NBM from Fri 6am · 3-hourly`: 12 Semibold in the NBM blue over a hairline (§12a).
    @ViewBuilder
    private var nbmHeader: some View {
        if let text = Derivations.nbmTableHeader(forecast: forecast) {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.nbmLabel(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .overlay(alignment: .top) {
                    Rectangle().fill(Tokens.hairline(scheme)).frame(height: 1)
                }
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func header(_ day: Day) -> some View {
        HStack(spacing: 8) {
            Text(day.name).frame(width: reflow ? nil : 56, alignment: .leading)
            if !reflow {
                Text("kn").frame(width: 56, alignment: .trailing)
                Text("gust").frame(width: 56, alignment: .trailing)
                Text("from").padding(.leading, 10).frame(maxWidth: .infinity, alignment: .leading)
                Text("B").frame(width: 36, alignment: .trailing)
                if showsTemp { Text(unit.symbol).frame(width: 40, alignment: .trailing) }
            } else {
                Spacer()
            }
        }
        .font(Tokens.tableHeaderFont)
        .foregroundStyle(Tokens.inkSecondary(scheme))
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .background(Tokens.ground(scheme))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Tokens.hairline(scheme)).frame(height: 1)
        }
    }

    /// `13:00`, or a block's 24-hour span `12–15` (the table stays 24-hour, §6.4a).
    private func timeText(_ date: Date, span: Int) -> String {
        guard span > 1 else { return TimeFormat.hhmm(date, tz: forecast.timeZone) }
        return TimeFormat.hh(date, tz: forecast.timeZone) + "–" + TimeFormat.hh(date.addingTimeInterval(TimeInterval(span) * 3600), tz: forecast.timeZone)
    }

    private var nbmTag: some View {
        Text("NBM")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Tokens.nbmLabel(scheme))
    }

    @ViewBuilder
    private func row(date: Date, span: Int, hour h: Forecast.Hour, nbm: Bool) -> some View {
        let step = Beaufort.step(kn: h.kn)
        if reflow {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(TimeFormat.weekdayShort(date, tz: forecast.timeZone) + " " + timeText(date, span: span))
                        .font(.system(.body, weight: .medium).monospacedDigit())
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                    if nbm { nbmTag }
                    Spacer()
                    Text("\(step)")
                        .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.black)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 44)
                        .background(Beaufort.color(step: step, scheme: scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .oldStateDesaturation(tier)
                        .accessibilityLabel("Beaufort \(step)")
                }
                HStack(spacing: 14) {
                    Text("\(h.kn) kn")
                        .font(.system(.body, design: .rounded, weight: .heavy).monospacedDigit())
                        .foregroundStyle(numberInk)
                    Text("G \(h.gust)")
                        .font(.system(.body, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Tokens.inkBody(scheme))
                    Spacer()
                    HStack(spacing: 8) {
                        ArrowView(dirFrom: h.dirFrom, size: 18, color: numberInk)
                        Text(Compass.label(from: h.dirFrom))
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(numberInk)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rowLabel(h, date, span: span, nbm: nbm))
        } else {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(timeText(date, span: span))
                        .font(.system(.body).monospacedDigit())
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if nbm { nbmTag }
                }
                .frame(width: 56, alignment: .leading)
                Text("\(h.kn)")
                    .font(.system(.body, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(numberInk)
                    .frame(width: 56, alignment: .trailing)
                Text("\(h.gust)")
                    .font(.system(.body).monospacedDigit())
                    .foregroundStyle(Tokens.inkBody(scheme))
                    .frame(width: 56, alignment: .trailing)
                HStack(spacing: 8) {
                    ArrowView(dirFrom: h.dirFrom, size: 14, color: numberInk)
                    Text(Compass.label(from: h.dirFrom))
                        .font(.system(.body))
                        .foregroundStyle(numberInk)
                }
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                BeaufortChip(step: step, scheme: scheme)
                    .oldStateDesaturation(tier)
                    .frame(width: 36, alignment: .trailing)
                if showsTemp {
                    Text(h.tempC.map { "\(unit.degrees(celsius: $0))°" } ?? "—")
                        .font(.system(.body).monospacedDigit())
                        .foregroundStyle(Tokens.inkBody(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rowLabel(h, date, span: span, nbm: nbm))
        }
    }

    private func rowLabel(_ h: Forecast.Hour, _ date: Date, span: Int, nbm: Bool) -> String {
        let when = TimeFormat.weekdayShort(date, tz: forecast.timeZone) + " " + timeText(date, span: span).replacingOccurrences(of: "–", with: " to ")
        var text = "\(when)\(nbm ? ", NBM" : ""), \(h.kn) knots, gusting \(h.gust), \(Compass.spokenFromText(dirFrom: h.dirFrom)), \(h.dirFrom) degrees, Beaufort \(Beaufort.step(kn: h.kn))"
        if let t = h.tempC { text += ", " + unit.spoken(celsius: t) }
        return text
    }
}
