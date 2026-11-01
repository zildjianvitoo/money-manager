import Foundation
import SwiftData
import Testing
@testable import MoneyCore

@MainActor
struct NoteSuggesterTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }

    @discardableResult
    private func add(
        _ ctx: ModelContext, profileID: UUID, note: String, daysAgo days: Int = 1,
        category: MoneyCategory? = nil, type: TransactionType = .expense
    ) -> MoneyTransaction {
        let t = MoneyTransaction(profileID: profileID, type: type, amount: 10_000, date: daysAgo(days))
        t.note = note
        t.category = category
        ctx.insert(t)
        return t
    }

    private func suggester(_ ctx: ModelContext, _ profileID: UUID) -> NoteSuggester {
        NoteSuggester(context: ctx, profileID: profileID)
    }

    @Test func suggestsByFrequency() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let pid = UUID()
        add(ctx, profileID: pid, note: "makan siang", daysAgo: 1)
        for i in 2...4 { add(ctx, profileID: pid, note: "makan malam", daysAgo: i) }
        add(ctx, profileID: pid, note: "bensin", daysAgo: 1)
        try ctx.save()

        let result = try suggester(ctx, pid).suggestions(prefix: "mak", categoryID: nil, now: now)
        #expect(result == ["makan malam", "makan siang"])
    }

    @Test func filtersByCategory() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let pid = UUID()
        let food = MoneyCategory(profileID: pid, name: "Makan", kind: .expense)
        let fuel = MoneyCategory(profileID: pid, name: "Transport", kind: .expense)
        ctx.insert(food)
        ctx.insert(fuel)
        add(ctx, profileID: pid, note: "makan siang", category: food)
        add(ctx, profileID: pid, note: "makan bensin", category: fuel)
        add(ctx, profileID: pid, note: "makan tanpa kategori")
        try ctx.save()

        let result = try suggester(ctx, pid).suggestions(prefix: "makan", categoryID: food.id, now: now)
        #expect(result == ["makan siang"])
    }

    @Test func suggestionsAreProfileScoped() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let pid = UUID()
        let other = UUID()
        add(ctx, profileID: pid, note: "makan siang")
        for _ in 0..<5 { add(ctx, profileID: other, note: "makan rahasia") }
        try ctx.save()

        let result = try suggester(ctx, pid).suggestions(prefix: "", categoryID: nil, now: now)
        #expect(result == ["makan siang"])
    }

    @Test func ignoresOlderThan180Days() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let pid = UUID()
        add(ctx, profileID: pid, note: "makan lama", daysAgo: 181)
        add(ctx, profileID: pid, note: "makan batas", daysAgo: 179)
        try ctx.save()

        let result = try suggester(ctx, pid).suggestions(prefix: "makan", categoryID: nil, now: now)
        #expect(result == ["makan batas"])
    }

    @Test func emptyPrefixReturnsMostFrequent() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let pid = UUID()
        add(ctx, profileID: pid, note: "kopi", daysAgo: 5)
        for i in 1...3 { add(ctx, profileID: pid, note: "parkir", daysAgo: i) }
        for i in 1...2 { add(ctx, profileID: pid, note: "bensin", daysAgo: i) }
        add(ctx, profileID: pid, note: "   ")
        add(ctx, profileID: pid, note: "")
        try ctx.save()

        let s = suggester(ctx, pid)
        #expect(try s.suggestions(prefix: "", categoryID: nil, limit: 2, now: now) == ["parkir", "bensin"])
        #expect(try s.suggestions(prefix: "", categoryID: nil, now: now) == ["parkir", "bensin", "kopi"])
    }

    @Test func diacriticInsensitiveMatch() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let pid = UUID()
        add(ctx, profileID: pid, note: "Kafé latte")
        try ctx.save()

        let s = suggester(ctx, pid)
        #expect(try s.suggestions(prefix: "kafe", categoryID: nil, now: now) == ["Kafé latte"])
        #expect(try s.suggestions(prefix: "KAFÉ", categoryID: nil, now: now) == ["Kafé latte"])
    }

    @Test func uniquifiesCaseInsensitivelyKeepingMostRecentSpelling() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let pid = UUID()
        add(ctx, profileID: pid, note: "makan siang", daysAgo: 10)
        add(ctx, profileID: pid, note: "  Makan Siang  ", daysAgo: 2)
        add(ctx, profileID: pid, note: "MAKAN SIANG", daysAgo: 20)
        try ctx.save()

        let result = try suggester(ctx, pid).suggestions(prefix: "mak", categoryID: nil, now: now)
        #expect(result == ["Makan Siang"])
    }

    @Test func tiesBreakByRecencyThenAlphabetical() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let pid = UUID()
        add(ctx, profileID: pid, note: "b lama", daysAgo: 9)
        add(ctx, profileID: pid, note: "c baru", daysAgo: 1)
        add(ctx, profileID: pid, note: "a sama", daysAgo: 5)
        add(ctx, profileID: pid, note: "b sama", daysAgo: 5)
        try ctx.save()

        let result = try suggester(ctx, pid).suggestions(prefix: "", categoryID: nil, now: now)
        #expect(result == ["c baru", "a sama", "b sama", "b lama"])
    }

    @Test func nonPositiveLimitReturnsEmpty() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let pid = UUID()
        add(ctx, profileID: pid, note: "makan")
        try ctx.save()

        let s = suggester(ctx, pid)
        #expect(try s.suggestions(prefix: "", categoryID: nil, limit: 0, now: now).isEmpty)
        #expect(try s.suggestions(prefix: "", categoryID: nil, limit: -1, now: now).isEmpty)
    }

    @Test func includesTransferNotesOnlyWhenNoCategoryFilter() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let pid = UUID()
        let food = MoneyCategory(profileID: pid, name: "Makan", kind: .expense)
        ctx.insert(food)
        add(ctx, profileID: pid, note: "tarik tunai", type: .transfer)
        add(ctx, profileID: pid, note: "", type: .transfer)
        try ctx.save()

        let s = suggester(ctx, pid)
        #expect(try s.suggestions(prefix: "", categoryID: nil, now: now) == ["tarik tunai"])
        #expect(try s.suggestions(prefix: "", categoryID: food.id, now: now).isEmpty)
    }
}
