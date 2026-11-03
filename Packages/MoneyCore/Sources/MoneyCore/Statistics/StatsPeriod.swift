import Foundation

public enum StatsPeriodKind: String, CaseIterable, Sendable {
    case weekly, monthly, yearly, range
}

public struct StatsPeriod: Equatable {
    public var kind: StatsPeriodKind
    /// Akhir bersifat eksklusif.
    public var interval: DateInterval

    public init(kind: StatsPeriodKind, interval: DateInterval) {
        self.kind = kind
        self.interval = interval
    }

    /// `.range` memberi bulan berjalan.
    public static func containing(_ date: Date, kind: StatsPeriodKind, calendar: Calendar) -> StatsPeriod {
        let component: Calendar.Component = switch kind {
        case .weekly: .weekOfYear
        case .monthly, .range: .month
        case .yearly: .year
        }
        let interval = calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 0)
        return StatsPeriod(kind: kind, interval: interval)
    }

    /// Inklusif sampai akhir hari `to`.
    public static func range(from: Date, to: Date, calendar: Calendar) -> StatsPeriod {
        let start = calendar.startOfDay(for: from)
        let lastDay = calendar.startOfDay(for: to)
        let end = calendar.date(byAdding: .day, value: 1, to: max(lastDay, start)) ?? lastDay
        return StatsPeriod(kind: .range, interval: DateInterval(start: start, end: end))
    }

    /// Geser `by` periode. `.range` bergeser sepanjang durasinya (dalam hari).
    public func shifted(by amount: Int, calendar: Calendar) -> StatsPeriod {
        switch kind {
        case .range:
            let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
            let start = calendar.date(byAdding: .day, value: days * amount, to: interval.start) ?? interval.start
            let end = calendar.date(byAdding: .day, value: days, to: start) ?? start
            return StatsPeriod(kind: .range, interval: DateInterval(start: start, end: end))
        case .weekly:
            return StatsPeriod.containing(shift(interval.start, .weekOfYear, amount, calendar), kind: kind, calendar: calendar)
        case .monthly:
            return StatsPeriod.containing(shift(interval.start, .month, amount, calendar), kind: kind, calendar: calendar)
        case .yearly:
            return StatsPeriod.containing(shift(interval.start, .year, amount, calendar), kind: kind, calendar: calendar)
        }
    }

    private func shift(_ date: Date, _ component: Calendar.Component, _ amount: Int, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: component, value: amount, to: date) ?? date
    }
}
