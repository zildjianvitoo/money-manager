import Testing
import Foundation
@testable import MoneyCore

private func jakartaCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
    return cal
}

private func date(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Test func periodWeeklyCrossesMonth() {
    let cal = jakartaCalendar()
    // Rabu 29 Okt 2026; minggu Minggu 25 Okt - Sabtu 31 Okt. Kamis 1 Okt 2026 -> minggu 27 Sep - 3 Okt.
    let p = StatsPeriod.containing(date(cal, 2026, 10, 1), kind: .weekly, calendar: cal)
    #expect(p.interval.start == date(cal, 2026, 9, 27, 0))
    #expect(p.interval.end == date(cal, 2026, 10, 4, 0))
    #expect(p.interval.start <= date(cal, 2026, 9, 30) && date(cal, 2026, 10, 2) < p.interval.end)
}

@Test func periodYearlyBoundary() {
    let cal = jakartaCalendar()
    let p = StatsPeriod.containing(date(cal, 2026, 12, 31, 23, 59), kind: .yearly, calendar: cal)
    #expect(p.interval.start == date(cal, 2026, 1, 1, 0))
    #expect(p.interval.end == date(cal, 2027, 1, 1, 0))
    #expect(!(p.interval.start <= date(cal, 2027, 1, 1, 0) && date(cal, 2027, 1, 1, 0) < p.interval.end))
}

@Test func periodShift() {
    let cal = jakartaCalendar()
    let jan = StatsPeriod.containing(date(cal, 2026, 1, 15), kind: .monthly, calendar: cal)
    let dec = jan.shifted(by: -1, calendar: cal)
    #expect(dec.interval.start == date(cal, 2025, 12, 1, 0))
    #expect(dec.interval.end == date(cal, 2026, 1, 1, 0))
    #expect(dec.shifted(by: 1, calendar: cal) == jan)

    let week = StatsPeriod.containing(date(cal, 2026, 11, 3), kind: .weekly, calendar: cal)
    #expect(week.shifted(by: 1, calendar: cal).interval.start == week.interval.end)

    let year = StatsPeriod.containing(date(cal, 2026, 5, 3), kind: .yearly, calendar: cal)
    #expect(year.shifted(by: -1, calendar: cal).interval.start == date(cal, 2025, 1, 1, 0))

    let range = StatsPeriod.range(from: date(cal, 2026, 10, 1), to: date(cal, 2026, 10, 10), calendar: cal)
    let next = range.shifted(by: 1, calendar: cal)
    #expect(next.interval.start == date(cal, 2026, 10, 11, 0))
    #expect(next.interval.end == date(cal, 2026, 10, 21, 0))
    #expect(next.kind == .range)
}

@Test func rangeInclusiveEnd() {
    let cal = jakartaCalendar()
    let p = StatsPeriod.range(from: date(cal, 2026, 10, 1, 15), to: date(cal, 2026, 10, 10, 3), calendar: cal)
    #expect(p.interval.start == date(cal, 2026, 10, 1, 0))
    #expect(p.interval.end == date(cal, 2026, 10, 11, 0))
}

@Test func rangeDefaultsToCurrentMonth() {
    let cal = jakartaCalendar()
    let p = StatsPeriod.containing(date(cal, 2026, 11, 3), kind: .range, calendar: cal)
    #expect(p.kind == .range)
    #expect(p.interval.start == date(cal, 2026, 11, 1, 0))
    #expect(p.interval.end == date(cal, 2026, 12, 1, 0))
}
