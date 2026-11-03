import Testing
import Foundation
import SwiftData
@testable import MoneyCore

private func jakartaCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
    return cal
}

private func date(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

@MainActor
private struct Fixture {
    let container: ModelContainer
    let ctx: ModelContext
    let cal = jakartaCalendar()
    let p = UUID()
    let makan: MoneyCategory
    let siang: MoneyCategory
    let transport: MoneyCategory
    let gaji: MoneyCategory

    init() throws {
        container = try MoneySchema.makeContainer(inMemory: true)
        ctx = container.mainContext
        makan = MoneyCategory(profileID: p, name: "Makan", kind: .expense, emoji: "🍜")
        siang = MoneyCategory(profileID: p, name: "Siang", kind: .expense, emoji: "🍱", parent: makan)
        transport = MoneyCategory(profileID: p, name: "Transport", kind: .expense, emoji: "🚕")
        gaji = MoneyCategory(profileID: p, name: "Gaji", kind: .income, emoji: "💰")
        [makan, siang, transport, gaji].forEach { ctx.insert($0) }
    }

    func tx(_ type: TransactionType, _ amount: Decimal, _ day: Int, month: Int = 10, category: MoneyCategory? = nil, fee: Decimal = 0) -> MoneyTransaction {
        let t = MoneyTransaction(profileID: p, type: type, amount: amount, date: date(cal, 2026, month, day))
        t.category = category
        t.fee = fee
        ctx.insert(t)
        return t
    }
}

@MainActor @Test func breakdownGroupsByParent() throws {
    let f = try Fixture()
    let txs = [
        f.tx(.expense, 20_000, 1, category: f.makan),
        f.tx(.expense, 30_000, 2, category: f.siang),
        f.tx(.expense, 40_000, 3, category: f.transport),
    ]
    let rows = StatisticsCalculator.breakdown(txs, kind: .expense)
    #expect(rows.map(\.name) == ["Makan", "Transport"])
    #expect(rows[0].amount == 50_000)
    #expect(rows[0].id == f.makan.id)
    #expect(abs(rows[0].fraction - 50.0 / 90.0) < 1e-9)
    #expect(abs(rows.map(\.fraction).reduce(0, +) - 1) < 1e-9)

    let subs = StatisticsCalculator.subcategoryBreakdown(txs, parentID: f.makan.id, kind: .expense)
    #expect(subs.map(\.name) == ["Siang", "Makan"])
    #expect(subs.map(\.amount) == [30_000, 20_000])
    let list = StatisticsCalculator.transactions(txs, shareID: f.makan.id, kind: .expense)
    #expect(list.map(\.amount) == [30_000, 20_000])
}

@MainActor @Test func breakdownSkipsTransfer() throws {
    let f = try Fixture()
    let txs = [
        f.tx(.expense, 20_000, 1, category: f.makan),
        f.tx(.transfer, 500_000, 2),
        f.tx(.adjustment, 99_000, 3),
    ]
    let rows = StatisticsCalculator.breakdown(txs, kind: .expense)
    #expect(rows.count == 1)
    #expect(StatisticsCalculator.total(txs, kind: .expense) == 20_000)
    #expect(StatisticsCalculator.breakdown(txs, kind: .income).isEmpty)
}

@MainActor @Test func transferFeeAppearsAsRow() throws {
    let f = try Fixture()
    let txs = [
        f.tx(.expense, 20_000, 1, category: f.makan),
        f.tx(.transfer, 500_000, 2, fee: 2_500),
        f.tx(.transfer, 100_000, 3, fee: 1_500),
    ]
    let rows = StatisticsCalculator.breakdown(txs, kind: .expense)
    let fee = try #require(rows.first { $0.id == StatisticsCalculator.transferFeeID })
    #expect(fee.name == "Biaya transfer")
    #expect(fee.amount == 4_000)
    #expect(StatisticsCalculator.breakdown(txs, kind: .income).isEmpty)
    #expect(StatisticsCalculator.transactions(txs, shareID: StatisticsCalculator.transferFeeID, kind: .expense).count == 2)
}

@MainActor @Test func uncategorizedRow() throws {
    let f = try Fixture()
    let txs = [
        f.tx(.expense, 7_000, 1),
        f.tx(.income, 100_000, 2),
        f.tx(.income, 5_000, 3, category: f.gaji),
    ]
    let expense = StatisticsCalculator.breakdown(txs, kind: .expense)
    #expect(expense.count == 1)
    #expect(expense[0].id == nil)
    #expect(expense[0].name == "Tanpa kategori")
    let income = StatisticsCalculator.breakdown(txs, kind: .income)
    #expect(income.map(\.amount) == [100_000, 5_000])
    #expect(income[0].id == nil)
}

@MainActor @Test func expenseTotalMatchesMonthSummary() throws {
    let f = try Fixture()
    let txs = [
        f.tx(.expense, 20_000, 1, category: f.makan),
        f.tx(.expense, 30_000, 2, category: f.siang),
        f.tx(.expense, 5_000, 3),
        f.tx(.transfer, 500_000, 4, fee: 2_500),
        f.tx(.transfer, 500_000, 5),
        f.tx(.income, 300_000, 6, category: f.gaji),
        f.tx(.adjustment, 1_000, 7),
    ]
    let summary = TransactionSummary.month(txs)
    #expect(StatisticsCalculator.total(txs, kind: .expense) == summary.expense)
    #expect(StatisticsCalculator.total(txs, kind: .income) == summary.income)
    #expect(StatisticsCalculator.breakdown(txs, kind: .expense).map(\.amount).reduce(0, +) == summary.expense)
}

@MainActor @Test func trendSixMonths() throws {
    let f = try Fixture()
    let txs = [
        f.tx(.expense, 10_000, 5, month: 10, category: f.makan),
        f.tx(.expense, 5_000, 5, month: 10, category: f.siang),
        f.tx(.expense, 7_000, 20, month: 8, category: f.makan),
        f.tx(.expense, 9_000, 31, month: 5, category: f.makan), // di luar 6 bulan
        f.tx(.expense, 3_000, 5, month: 10, category: f.transport),
    ]
    let points = StatisticsCalculator.trend(
        txs, shareID: f.makan.id, kind: .expense, months: 6, endingAt: date(f.cal, 2026, 10, 15), calendar: f.cal)
    #expect(points.count == 6)
    #expect(points.first?.id == date(f.cal, 2026, 5, 1, 0))
    #expect(points.last?.id == date(f.cal, 2026, 10, 1, 0))
    #expect(points.map(\.amount) == [9_000, 0, 0, 7_000, 0, 15_000])
}
