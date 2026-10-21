import SwiftUI
import WindCore

/// HANDOFF §8.1 item 5: columns `56 | 56 | 56 | 1fr | 36`, 44 pt rows, hairlines, a sticky day
/// header at each day change. From AX1 the row reflows to two lines.
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
                                .fill(Tokens.hairline(scheme))
                                .frame(height: 1)
                        }
                }
            } header: {
                header(day)
            }
        }
        .accessibilityLabel("Hourly forecast table")
    }

    private func header(_ day: Day) -> some View {
        HStack(spacing: 0) {
            Text(day.name).frame(width: reflow ? nil : 56, alignment: .leading)
            if !reflow {
                Text("kn").frame(width: 56, alignment: .leading)
                Text("gust").frame(width: 56, alignment: .leading)
                Text("from").frame(maxWidth: .infinity, alignment: .leading)
                Text("Bft").frame(width: 36, alignment: .trailing)
            } else {
                Spacer()
            }
        }
        .font(Tokens.tableHeaderFont)
        .foregroundStyle(Tokens.inkSecondary(scheme))
        .frame(minHeight: 28)
        .background(Tokens.ground(scheme))
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
                        .font(.system(.body, design: .default, weight: .regular).monospacedDigit())
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                    Spacer()
                    BeaufortChip(step: step, scheme: scheme)
                }
                HStack(spacing: 12) {
                    Text("\(h.kn) kn")
                        .font(.system(.body, design: .rounded, weight: .bold).monospacedDigit())
                        .foregroundStyle(numberInk)
                    Text("G \(h.gust)")
                        .font(.system(.body).monospacedDigit())
                        .foregroundStyle(Tokens.inkBody(scheme))
                    HStack(spacing: 4) {
                        ArrowView(dirFrom: h.dirFrom, size: 14, color: numberInk)
                        Text(Compass.label(from: h.dirFrom))
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(numberInk)
                    }
                }
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rowLabel(h, date))
        } else {
            HStack(spacing: 0) {
                Text(TimeFormat.hhmm(date, tz: forecast.timeZone))
                    .font(.system(.body).monospacedDigit())
                    .foregroundStyle(Tokens.inkSecondary(scheme))
                    .frame(width: 56, alignment: .leading)
                Text("\(h.kn)")
                    .font(.system(.body, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(numberInk)
                    .frame(width: 56, alignment: .leading)
                Text("\(h.gust)")
                    .font(.system(.body).monospacedDigit())
                    .foregroundStyle(Tokens.inkBody(scheme))
                    .frame(width: 56, alignment: .leading)
                HStack(spacing: 6) {
                    ArrowView(dirFrom: h.dirFrom, size: 14, color: numberInk)
                    Text(Compass.fromText(dirFrom: h.dirFrom))
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(numberInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                BeaufortChip(step: step, scheme: scheme)
                    .oldStateDesaturation(tier)
                    .frame(width: 36, alignment: .trailing)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rowLabel(h, date))
        }
    }

    private func rowLabel(_ h: Forecast.Hour, _ date: Date) -> String {
        "\(TimeFormat.weekdayHHMM(date, tz: forecast.timeZone)), \(h.kn) knots, gusting \(h.gust), \(Compass.spokenFromText(dirFrom: h.dirFrom)), Beaufort \(Beaufort.step(kn: h.kn))"
    }
}
