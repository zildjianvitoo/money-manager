import Testing
import Foundation
import SwiftData
@testable import MoneyCore

private func jakartaCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
    return cal
}

private func date(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@MainActor @Test func monthSummaryRules() throws {
    let container = try MoneySchema.makeContainer(inMemory: true)
    let ctx = container.mainContext
    let cal = jakartaCalendar()
    let p = UUID()
    let d = date(cal, 2026, 10, 15)
    let transfer = MoneyTransaction(profileID: p, type: .transfer, amount: 50_000, date: d)
    transfer.fee = 2_500
    let txs = [
        MoneyTransaction(profileID: p, type: .income, amount: 100_000, date: d),
        MoneyTransaction(profileID: p, type: .expense, amount: 19_000, date: d),
        MoneyTransaction(profileID: p, type: .expense, amount: 23_500, date: d),
        transfer,
        MoneyTransaction(profileID: p, type: .adjustment, amount: 10_000, date: d),
    ]
    txs.forEach { ctx.insert($0) }
    let summary = TransactionSummary.month(txs)
    #expect(summary.income == 100_000)
    #expect(summary.expense == 45_000)
    #expect(summary.total == 55_000)
}

@MainActor @Test func daySectionsGroupAndSort() throws {
    let container = try MoneySchema.makeContainer(inMemory: true)
    let ctx = container.mainContext
    let cal = jakartaCalendar()
    let p = UUID()
    let t29 = MoneyTransaction(profileID: p, type: .expense, amount: 5_000, date: date(cal, 2026, 10, 29, 9))
    let t30a = MoneyTransaction(profileID: p, type: .expense, amount: 10_000, date: date(cal, 2026, 10, 30, 8))
    let t30b = MoneyTransaction(profileID: p, type: .income, amount: 40_000, date: date(cal, 2026, 10, 30, 18))
    let txs = [t29, t30a, t30b]
    txs.forEach { ctx.insert($0) }

    let sections = TransactionSummary.daySections(txs, calendar: cal)
    #expect(sections.count == 2)
    #expect(sections[0].id == cal.startOfDay(for: date(cal, 2026, 10, 30)))
    #expect(sections[1].id == cal.startOfDay(for: date(cal, 2026, 10, 29)))
    #expect(sections[0].transactions.count == 2)
    #expect(sections[0].transactions[0] === t30b)
    #expect(sections[0].transactions[1] === t30a)
    #expect(sections[0].income == 40_000)
    #expect(sections[0].expense == 10_000)
    #expect(sections[1].transactions.count == 1)
    #expect(sections[1].expense == 5_000)
    #expect(sections[1].income == 0)
}

@MainActor @Test func monthBoundary() throws {
    let container = try MoneySchema.makeContainer(inMemory: true)
    let ctx = container.mainContext
    let cal = jakartaCalendar()
    let p = UUID()
    let lastOfOct = MoneyTransaction(profileID: p, type: .expense, amount: 1_000, date: date(cal, 2026, 10, 31, 23, 59))
    let firstOfNov = MoneyTransaction(profileID: p, type: .expense, amount: 2_000, date: date(cal, 2026, 11, 1, 0, 0))
    ctx.insert(lastOfOct); ctx.insert(firstOfNov)

    let interval = TransactionQueries.monthInterval(containing: date(cal, 2026, 10, 15), calendar: cal)
    #expect(interval.start == date(cal, 2026, 10, 1, 0, 0))
    #expect(interval.end == date(cal, 2026, 11, 1, 0, 0))
    // Akhir interval eksklusif (DateInterval.contains sendiri inklusif), sama dengan predikat descriptor.
    func inMonth(_ d: Date) -> Bool { d >= interval.start && d < interval.end }
    #expect(inMonth(lastOfOct.date))
    #expect(!inMonth(firstOfNov.date))

    let sections = TransactionSummary.daySections([lastOfOct, firstOfNov], calendar: cal)
    #expect(sections.count == 2)
    #expect(sections[0].transactions.first === firstOfNov)
    #expect(sections[1].transactions.first === lastOfOct)
}

@MainActor @Test func descriptorFiltersProfileAndMonth() throws {
    let container = try MoneySchema.makeContainer(inMemory: true)
    let ctx = container.mainContext
    let cal = jakartaCalendar()
    let mine = UUID(), other = UUID()
    let early = MoneyTransaction(profileID: mine, type: .expense, amount: 1, date: date(cal, 2026, 10, 2))
    let late = MoneyTransaction(profileID: mine, type: .expense, amount: 2, date: date(cal, 2026, 10, 20))
    let boundary = MoneyTransaction(profileID: mine, type: .expense, amount: 3, date: date(cal, 2026, 11, 1, 0, 0))
    let otherMonth = MoneyTransaction(profileID: mine, type: .expense, amount: 4, date: date(cal, 2026, 9, 30))
    let otherProfile = MoneyTransaction(profileID: other, type: .expense, amount: 5, date: date(cal, 2026, 10, 10))
    [early, late, boundary, otherMonth, otherProfile].forEach { ctx.insert($0) }
    try ctx.save()

    let interval = TransactionQueries.monthInterval(containing: date(cal, 2026, 10, 15), calendar: cal)
    let fetched = try ctx.fetch(TransactionQueries.descriptor(profileID: mine, interval: interval))
    #expect(fetched.count == 2)
    #expect(fetched[0] === late)
    #expect(fetched[1] === early)
}
