import Foundation
import SwiftData
import Testing
@testable import MoneyCore

@MainActor
private enum Keep {
    nonisolated(unsafe) static var containers: [ModelContainer] = []
    static func context() throws -> ModelContext {
        let container = try MoneySchema.makeContainer(inMemory: true)
        containers.append(container)
        return container.mainContext
    }
}

@MainActor
struct TransactionFilterTests {
    @MainActor private struct World {
        let context: ModelContext
        let pid = UUID()
        let food: MoneyCategory, lunch: MoneyCategory, salary: MoneyCategory
        let cash: AssetAccount, bank: AssetAccount
        var all: [MoneyTransaction] = []

        init() throws {
            context = try Keep.context()
            food = MoneyCategory(profileID: pid, name: "Makanan", kind: .expense)
            lunch = MoneyCategory(profileID: pid, name: "Makan Siang", kind: .expense, parent: food)
            salary = MoneyCategory(profileID: pid, name: "Gaji", kind: .income)
            cash = AssetAccount(profileID: pid, name: "Tunai", group: .cash)
            bank = AssetAccount(profileID: pid, name: "BCA", group: .bank)
            [food, lunch, salary].forEach(context.insert)
            [cash, bank].forEach(context.insert)

            func make(_ type: TransactionType, _ amount: Decimal, category: MoneyCategory?, asset: AssetAccount, to: AssetAccount? = nil,
                      note: String = "", detail: String = "") -> MoneyTransaction {
                let tx = MoneyTransaction(profileID: pid, type: type, amount: amount, date: .now)
                tx.category = category; tx.asset = asset; tx.toAsset = to; tx.note = note; tx.detail = detail
                context.insert(tx)
                return tx
            }
            all = [
                make(.expense, 25_000, category: lunch, asset: cash, note: "Nasi Padang", detail: "Dengan teman kantor"),
                make(.expense, 100_000, category: food, asset: bank, note: "Belanja"),
                make(.income, 5_000_000, category: salary, asset: bank, note: "Gaji Oktober"),
                make(.transfer, 50_000, category: nil, asset: bank, to: cash),
            ]
        }
    }

    @Test func emptyFilterMatchesEverything() throws {
        let w = try World()
        let filter = TransactionFilter()
        #expect(!filter.isActive)
        #expect(filter.activeCount == 0)
        #expect(filter.apply(w.all).count == 4)
    }

    @Test func typeFilter() throws {
        let w = try World()
        var filter = TransactionFilter()
        filter.types = [.income, .transfer]
        #expect(filter.apply(w.all).map(\.type).sorted { $0.rawValue < $1.rawValue } == [.income, .transfer])
        #expect(filter.activeCount == 1)
    }

    @Test func parentCategoryIncludesSubcategories() throws {
        let w = try World()
        var filter = TransactionFilter()
        filter.categoryIDs = [w.food.id]
        #expect(filter.apply(w.all).count == 2)
        filter.categoryIDs = [w.lunch.id]
        #expect(filter.apply(w.all).map(\.note) == ["Nasi Padang"])
    }

    @Test func categoryFilterExcludesTransfers() throws {
        let w = try World()
        var filter = TransactionFilter()
        filter.categoryIDs = [w.food.id, w.salary.id]
        #expect(filter.apply(w.all).allSatisfy { $0.type != .transfer })
    }

    @Test func assetFilterMatchesSourceOrTarget() throws {
        let w = try World()
        var filter = TransactionFilter()
        filter.assetIDs = [w.cash.id]
        // pengeluaran tunai + transfer bank → tunai
        #expect(filter.apply(w.all).count == 2)
    }

    @Test func amountRangeIsInclusive() throws {
        let w = try World()
        var filter = TransactionFilter()
        filter.minAmount = 25_000
        filter.maxAmount = 100_000
        #expect(filter.apply(w.all).map(\.amount).sorted() == [25_000, 50_000, 100_000])
        filter.minAmount = nil
        filter.maxAmount = 25_000
        #expect(filter.apply(w.all).count == 1)
        #expect(filter.activeCount == 1)
    }

    @Test func criteriaCombineWithAnd() throws {
        let w = try World()
        var filter = TransactionFilter()
        filter.types = [.expense]
        filter.assetIDs = [w.bank.id]
        filter.minAmount = 50_000
        #expect(filter.apply(w.all).map(\.note) == ["Belanja"])
        #expect(filter.activeCount == 3)
    }

    @Test func searchMatchesNoteAndDetailIgnoringCaseAndAccents() throws {
        let w = try World()
        #expect(TransactionSearch.search(w.all, query: "padang").count == 1)
        #expect(TransactionSearch.search(w.all, query: "KANTOR").count == 1)
        #expect(TransactionSearch.search(w.all, query: "gaji oktober").count == 1)
        #expect(TransactionSearch.search(w.all, query: "oktober gaji").count == 1)
        #expect(TransactionSearch.search(w.all, query: "padang bank").isEmpty)
        #expect(TransactionSearch.search(w.all, query: "   ").isEmpty)
        #expect(TransactionSearch.search(w.all, query: "").isEmpty)
    }

    @Test func searchIgnoresAccents() throws {
        let w = try World()
        w.all[1].note = "Café du coin"
        #expect(TransactionSearch.search(w.all, query: "cafe").count == 1)
    }
}

@MainActor
struct FavoriteServiceTests {
    private func world() throws -> (FavoriteService, ModelContext, UUID, MoneyCategory, AssetAccount) {
        let context = try Keep.context()
        let pid = UUID()
        let category = MoneyCategory(profileID: pid, name: "Makanan", kind: .expense)
        let asset = AssetAccount(profileID: pid, name: "Tunai", group: .cash)
        context.insert(category)
        context.insert(asset)
        try context.save()
        return (FavoriteService(context: context, profileID: pid), context, pid, category, asset)
    }

    private func draft(_ category: MoneyCategory, _ asset: AssetAccount, amount: Decimal = 30_000) -> TransactionDraft {
        var d = TransactionDraft(type: .expense, date: .now)
        d.categoryID = category.id
        d.assetID = asset.id
        d.note = "makan malam"
        d.amount = amount
        return d
    }

    @Test func createWithAndWithoutAmount() throws {
        let (service, _, _, category, asset) = try world()
        let withAmount = try service.create(name: "Makan malam", from: draft(category, asset), includeAmount: true)
        let withoutAmount = try service.create(name: "Makan lagi", from: draft(category, asset), includeAmount: false)
        #expect(withAmount.amount == 30_000)
        #expect(withoutAmount.amount == nil)
        #expect(try service.favorites().map(\.name) == ["Makan malam", "Makan lagi"])
    }

    @Test func rejectsEmptyNameAndAdjustment() throws {
        let (service, _, _, category, asset) = try world()
        #expect(throws: FavoriteServiceError.emptyName) {
            try service.create(name: "  ", from: draft(category, asset), includeAmount: true)
        }
        var adjustment = draft(category, asset)
        adjustment.type = .adjustment
        #expect(throws: FavoriteServiceError.unsupportedType) {
            try service.create(name: "x", from: adjustment, includeAmount: true)
        }
    }

    @Test func applyFillsDraftButKeepsDateAndKeepsAmountWhenTemplateHasNone() throws {
        let (service, _, _, category, asset) = try world()
        let fav = try service.create(name: "Makan", from: draft(category, asset), includeAmount: false)

        let date = Date(timeIntervalSince1970: 1_000)
        var target = TransactionDraft(type: .income, date: date)
        target.amount = 7_000
        try service.apply(fav, to: &target)
        #expect(target.type == .expense)
        #expect(target.categoryID == category.id)
        #expect(target.assetID == asset.id)
        #expect(target.note == "makan malam")
        #expect(target.amount == 7_000)
        #expect(target.date == date)
    }

    @Test func applyDropsDeletedCategoryAndAsset() throws {
        let (service, context, _, category, asset) = try world()
        let fav = try service.create(name: "Makan", from: draft(category, asset), includeAmount: true)
        context.delete(category)
        context.delete(asset)
        try context.save()

        var target = TransactionDraft(type: .expense, date: .now)
        try service.apply(fav, to: &target)
        #expect(target.categoryID == nil)
        #expect(target.assetID == nil)
        #expect(target.amount == 30_000)
    }

    @Test func favoritesAreIsolatedPerProfile() throws {
        let (service, context, _, category, asset) = try world()
        let fav = try service.create(name: "Makan", from: draft(category, asset), includeAmount: true)

        let other = FavoriteService(context: context, profileID: UUID())
        #expect(try other.favorites().isEmpty)
        #expect(throws: FavoriteServiceError.foreignFavorite) { try other.delete(fav) }
        var d = TransactionDraft(type: .expense, date: .now)
        #expect(throws: FavoriteServiceError.foreignFavorite) { try other.apply(fav, to: &d) }
    }

    @Test func deleteRemovesFavorite() throws {
        let (service, _, _, category, asset) = try world()
        let fav = try service.create(name: "Makan", from: draft(category, asset), includeAmount: true)
        try service.delete(fav)
        #expect(try service.favorites().isEmpty)
    }
}
