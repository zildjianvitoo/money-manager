import Testing
import Foundation
@testable import MoneyCore

private func jakartaCalendar(firstWeekday: Int = 1) -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
    cal.firstWeekday = firstWeekday
    return cal
}

private func date(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

@Test func weeksNovember2026() {
    let cal = jakartaCalendar()
    let weeks = CalendarGrid.weeks(for: date(cal, 2026, 11, 15), calendar: cal)
    #expect(weeks.allSatisfy { $0.count == 7 })
    #expect(weeks[0][0] == cal.startOfDay(for: date(cal, 2026, 11, 1)))
    #expect(weeks.flatMap { $0 }.compactMap { $0 }.count == 30)
    #expect(weeks.count == 5)
}

@Test func weeksRespectFirstWeekday() {
    let cal = jakartaCalendar(firstWeekday: 2)
    let weeks = CalendarGrid.weeks(for: date(cal, 2026, 11, 15), calendar: cal)
    #expect(weeks[0][0] == nil)
    #expect(weeks[0][6] == cal.startOfDay(for: date(cal, 2026, 11, 1)))
    #expect(weeks.flatMap { $0 }.compactMap { $0 }.count == 30)
    #expect(CalendarGrid.weekdaySymbols(calendar: cal).count == 7)
}

@Test func weeksFebruaryLeapYear() {
    let cal = jakartaCalendar()
    let weeks = CalendarGrid.weeks(for: date(cal, 2028, 2, 10), calendar: cal)
    #expect(weeks.flatMap { $0 }.compactMap { $0 }.count == 29)
}

@Test func weekdaySymbolsStartAtFirstWeekday() {
    let sunday = CalendarGrid.weekdaySymbols(calendar: jakartaCalendar(firstWeekday: 1))
    let monday = CalendarGrid.weekdaySymbols(calendar: jakartaCalendar(firstWeekday: 2))
    #expect(monday.first == sunday[1])
    #expect(monday.last == sunday[0])
    #expect(sunday.first == "Min")
    #expect(monday.first == "Sen")
}
