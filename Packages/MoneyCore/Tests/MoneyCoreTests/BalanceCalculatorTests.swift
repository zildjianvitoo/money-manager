import Foundation
import SwiftData
import Testing
@testable import MoneyCore

@MainActor
struct BalanceCalculatorTests {
    private let pid = UUID()

    private func tx(
        _ type: TransactionType, _ amount: Decimal, asset: AssetAccount?, to: AssetAccount? = nil,
        fee: Decimal = 0, at seconds: TimeInterval = 1_000_000, created: TimeInterval = 0
    ) -> MoneyTransaction {
        let t = MoneyTransaction(profileID: pid, type: type, amount: amount, date: Date(timeIntervalSince1970: seconds))
        t.asset = asset
        t.toAsset = to
        t.fee = fee
        t.createdAt = Date(timeIntervalSince1970: created)
        return t
    }

    @Test func balanceRules() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let bank = AssetAccount(profileID: pid, name: "BCA", group: .bank, initialBalance: 1_000_000)
        let cash = AssetAccount(profileID: pid, name: "Tunai", group: .cash)
        let other = AssetAccount(profileID: pid, name: "Lain", group: .other)
        ctx.insert(bank); ctx.insert(cash); ctx.insert(other)
        let txs = [
            tx(.income, 500_000, asset: bank),
            tx(.expense, 19_000, asset: bank),
            tx(.transfer, 200_000, asset: bank, to: cash, fee: 2_500),
            tx(.transfer, 50_000, asset: cash, to: bank),
            tx(.adjustment, -8_500, asset: bank),
            tx(.expense, 777, asset: other),  // bukan milik bank: diabaikan
        ]
        txs.forEach(ctx.insert)
        try ctx.save()
        #expect(BalanceCalculator.balance(of: bank, transactions: txs) == 1_320_000)
        // Cash: +200.000 masuk, −50.000 keluar.
        #expect(BalanceCalculator.balance(of: cash, transactions: txs) == 150_000)
    }

    @Test func netWorthSplitsLiabilities() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let bank = AssetAccount(profileID: pid, name: "Bank", group: .bank, initialBalance: 1_000_000)
        let card = AssetAccount(profileID: pid, name: "Kartu", group: .creditCard, initialBalance: -300_000)
        let hidden = AssetAccount(profileID: pid, name: "Luar", group: .other, initialBalance: 999)
        hidden.includeInTotal = false
        let zero = AssetAccount(profileID: pid, name: "Nol", group: .cash)
        [bank, card, hidden, zero].forEach(ctx.insert)
        try ctx.save()
        let nw = BalanceCalculator.netWorth(assets: [bank, card, hidden, zero], transactions: [])
        #expect(nw.assets == 1_000_000)
        #expect(nw.liabilities == -300_000)
        #expect(nw.total == 700_000)
    }

    @Test func netWorthIncludesArchivedAssets() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let bank = AssetAccount(profileID: pid, name: "Bank", group: .bank, initialBalance: 100)
        bank.isArchived = true
        ctx.insert(bank)
        try ctx.save()
        #expect(BalanceCalculator.netWorth(assets: [bank], transactions: []).assets == 100)
    }

    @Test func runningBalancesAscending() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let bank = AssetAccount(profileID: pid, name: "BCA", group: .bank, initialBalance: 1_000)
        let cash = AssetAccount(profileID: pid, name: "Tunai", group: .cash)
        ctx.insert(bank); ctx.insert(cash)
        let late = tx(.expense, 300, asset: bank, at: 3_000)
        let early = tx(.income, 500, asset: bank, at: 1_000)
        let sameDayB = tx(.transfer, 100, asset: bank, to: cash, fee: 10, at: 2_000, created: 2)
        let sameDayA = tx(.adjustment, -50, asset: bank, at: 2_000, created: 1)
        let incoming = tx(.transfer, 40, asset: cash, to: bank, at: 4_000)
        let unrelated = tx(.expense, 9, asset: cash, at: 1_500)
        let all = [late, sameDayB, unrelated, early, incoming, sameDayA]
        all.forEach(ctx.insert)
        try ctx.save()

        let rows = BalanceCalculator.runningBalances(of: bank, transactions: all)
        let ids: [UUID] = rows.map { $0.transaction.id }
        let expectedIDs: [UUID] = [early.id, sameDayA.id, sameDayB.id, late.id, incoming.id]
        #expect(ids == expectedIDs)
        let balances: [Decimal] = rows.map { $0.balanceAfter }
        let expectedBalances: [Decimal] = [1_500, 1_450, 1_340, 1_040, 1_080]
        #expect(balances == expectedBalances)
    }
}
