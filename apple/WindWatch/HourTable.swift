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

    @AppStorage(HourTableDisclosure.storageKey) private var expanded = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var ax: Bool { typeSize.isAccessibilitySize }

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
                        Text(Derivations.tableCaption(forecast: forecast, now: now))
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
        .accessibilityLabel("Hourly table, \(Derivations.tableCaption(forecast: forecast, now: now))")
        .accessibilityValue(expanded ? "expanded" : "collapsed")
        .accessibilityAddTraits(.isButton)
        if expanded {
            HourTable(forecast: forecast, now: now, tier: tier)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

/// HANDOFF §8.1 item 5 / `Phone-Main.dc.html`: columns `56 | 56 | 56 | 1fr | 36` (gap 8, 8 pt
/// inner padding), 44 pt rows, row rules in `card`, a sticky day header (`Wed · kn · gust · from
/// · B`) at each day change. From AX1 the row reflows to two lines (`Phone-Table-LargeType`).
struct HourTable: View {
    let forecast: Forecast
    let now: Date
    let tier: AgeTier

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Day: Identifiable {
        let id: Date
        let name: String
        let indices: [Int]
    }

    private var days: [Day] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = forecast.timeZone
        let first = max(forecast.heroIndex(at: now) ?? 0, 0)
        var out: [Day] = []
        for i in first..<forecast.hours.count {
            let date = forecast.date(ofHour: i)
            let day = cal.startOfDay(for: date)
            if out.last?.id == day {
                out[out.count - 1] = Day(id: day, name: out[out.count - 1].name, indices: out[out.count - 1].indices + [i])
            } else {
                out.append(Day(id: day, name: TimeFormat.weekdayShort(date, tz: forecast.timeZone), indices: [i]))
            }
        }
        return out
    }

    private var numberInk: Color { Tokens.numberInk(scheme, tier: tier) }
    private var reflow: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        ForEach(days) { day in
            Section {
                ForEach(day.indices, id: \.self) { i in
                    row(index: i)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Tokens.card(scheme))
                                .frame(height: 1)
                        }
                }
            } header: {
                // AX rows carry `Wed 21:00` themselves; no day header (`Phone-Table-LargeType`).
                if !reflow { header(day) }
            }
        }
        .accessibilityLabel("Hourly forecast table")
    }

    private func header(_ day: Day) -> some View {
        HStack(spacing: 8) {
            Text(day.name).frame(width: reflow ? nil : 56, alignment: .leading)
            if !reflow {
                Text("kn").frame(width: 56, alignment: .trailing)
                Text("gust").frame(width: 56, alignment: .trailing)
                Text("from").padding(.leading, 10).frame(maxWidth: .infinity, alignment: .leading)
                Text("B").frame(width: 36, alignment: .trailing)
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

    @ViewBuilder
    private func row(index i: Int) -> some View {
        let h = forecast.hours[i]
        let date = forecast.date(ofHour: i)
        let step = Beaufort.step(kn: h.kn)
        if reflow {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(TimeFormat.weekdayHHMM(date, tz: forecast.timeZone))
                        .font(.system(.body, weight: .medium).monospacedDigit())
                        .foregroundStyle(Tokens.inkSecondary(scheme))
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
            .accessibilityLabel(rowLabel(h, date))
        } else {
            HStack(spacing: 8) {
                Text(TimeFormat.hhmm(date, tz: forecast.timeZone))
                    .font(.system(.body).monospacedDigit())
                    .foregroundStyle(Tokens.inkSecondary(scheme))
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
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rowLabel(h, date))
        }
    }

    private func rowLabel(_ h: Forecast.Hour, _ date: Date) -> String {
        "\(TimeFormat.weekdayHHMM(date, tz: forecast.timeZone)), \(h.kn) knots, gusting \(h.gust), \(Compass.spokenFromText(dirFrom: h.dirFrom)), Beaufort \(Beaufort.step(kn: h.kn))"
    }
}
