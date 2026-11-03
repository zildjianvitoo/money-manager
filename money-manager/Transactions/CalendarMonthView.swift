import SwiftUI
import MoneyCore

/// Short amounts for calendar cells, id_ID style without "Rp": `850rb`, `1,2jt`, `15jt`.
enum CompactAmount {
    private static let units: [(divisor: Double, suffix: String)] = [
        (1_000, "rb"), (1_000_000, "jt"), (1_000_000_000, "M"), (1_000_000_000_000, "T"),
    ]

    static func string(_ amount: Decimal) -> String {
        let value = abs(NSDecimalNumber(decimal: amount).doubleValue)
        let sign = amount < 0 ? "-" : ""
        guard let index = units.lastIndex(where: { value >= $0.divisor }) else {
            return sign + String(Int(value.rounded()))
        }
        var unit = index
        var scaled = roundedToTenth(value / units[unit].divisor)
        // 999,96rb rounds to 1000rb; show 1jt instead.
        if scaled >= 1000, unit + 1 < units.count {
            unit += 1
            scaled = roundedToTenth(value / units[unit].divisor)
        }
        let number = scaled == scaled.rounded()
            ? String(Int(scaled))
            : String(format: "%.1f", scaled).replacing(".", with: ",")
        return sign + number + units[unit].suffix
    }

    private static func roundedToTenth(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

/// "Kalender" grid: weekday header and one tappable cell per day with short income/expense.
struct CalendarMonthView: View {
    let month: Date
    let dayTotals: [Date: DayTotals]
    @Binding var selectedDay: Date?

    private let calendar = Calendar.current

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    var body: some View {
        let weeks = CalendarGrid.weeks(for: month, calendar: calendar)
        VStack(spacing: 0) {
            weekdayHeader
            ForEach(weeks.indices, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        if let day = weeks[row][column] {
                            cell(for: day)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 56)
                        }
                    }
                }
            }
        }
        // Dense grid: capped so amounts keep fitting; the list below still scales.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .padding(.horizontal, 8)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(CalendarGrid.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { offset, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(weekdayColor(offset: offset))
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
        }
        .accessibilityHidden(true)
    }

    private func weekdayColor(offset: Int) -> Color {
        // Header order follows `firstWeekday`; map back to the 1...7 weekday number.
        let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
        switch weekday {
        case 1: return .red
        case 7: return .blue
        default: return .secondary
        }
    }

    private func cell(for day: Date) -> some View {
        let start = calendar.startOfDay(for: day)
        let totals = dayTotals[start]
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: start) } ?? false
        let isToday = calendar.isDateInToday(start)
        return Button {
            selectedDay = isSelected ? nil : start
        } label: {
            VStack(spacing: 1) {
                Text(String(calendar.component(.day, from: start)))
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.white : Color.primary)
                    .frame(minWidth: 26, minHeight: 26)
                    .background(isToday ? Color.accentColor : Color.clear, in: Circle())
                amountText(totals?.income, color: .blue)
                amountText(totals?.expense, color: .red)
            }
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: start, totals: totals))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Always one line tall so rows keep the same height.
    private func amountText(_ amount: Decimal?, color: Color) -> some View {
        Text(amount.flatMap { $0 == 0 ? nil : CompactAmount.string($0) } ?? " ")
            .font(.caption2.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func accessibilityLabel(for day: Date, totals: DayTotals?) -> String {
        var parts = [Self.dayFormatter.string(from: day)]
        if let totals, totals.income != 0 { parts.append("pendapatan \(MoneyFormatter.string(totals.income))") }
        if let totals, totals.expense != 0 { parts.append("pengeluaran \(MoneyFormatter.string(totals.expense))") }
        if parts.count == 1 { parts.append("tidak ada transaksi") }
        return parts.joined(separator: ", ")
    }
}
