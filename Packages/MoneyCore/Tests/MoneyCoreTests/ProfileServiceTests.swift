import Foundation
import SwiftData
import Testing
@testable import MoneyCore
import class MoneyCore.Category

@MainActor
struct ProfileServiceTests {
    private func makeStore() -> ProfileStore {
        ProfileStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    private func categories(_ ctx: ModelContext, _ id: UUID, kind: CategoryKind? = nil) throws -> [Category] {
        let all = try ctx.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.profileID == id }))
        guard let kind else { return all }
        return all.filter { $0.kind == kind && $0.parent == nil }
    }

    private func assets(_ ctx: ModelContext, _ id: UUID) throws -> [AssetAccount] {
        try ctx.fetch(FetchDescriptor<AssetAccount>(predicate: #Predicate { $0.profileID == id }))
    }

    private func transactions(_ ctx: ModelContext, _ id: UUID) throws -> [MoneyTransaction] {
        try ctx.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.profileID == id }))
    }

    @Test func bootstrapCreatesPribadiOnce() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let service = ProfileService(context: ctx)
        let store = makeStore()

        let first = try service.bootstrap(store: store)
        let second = try service.bootstrap(store: store)

        let profiles = try service.profiles()
        #expect(profiles.count == 1)
        #expect(profiles[0].name == "Pribadi")
        #expect(first.id == second.id)
        #expect(try categories(ctx, first.id, kind: .expense).count == 12)
        #expect(try categories(ctx, first.id, kind: .income).count == 5)
        let accounts = try assets(ctx, first.id)
        #expect(accounts.count == 1)
        #expect(accounts[0].name == "Tunai")
        #expect(accounts[0].group == .cash)
        #expect(accounts[0].initialBalanceMinor == 0)
        #expect(store.activeProfileID == first.id)
    }

    @Test func bootstrapClearsDanglingPrevious() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let service = ProfileService(context: container.mainContext)
        let store = makeStore()
        let ghostA = UUID(), ghostB = UUID()
        store.switchTo(ghostA)
        store.switchTo(ghostB)   // active = ghostB, previous = ghostA, both dangling

        let profile = try service.bootstrap(store: store)

        #expect(store.activeProfileID == profile.id)
        #expect(store.previousProfileID == nil)
    }

    @Test func defaultCategoriesFollowCatalogOrder() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let profile = try ProfileService(context: ctx).bootstrap(store: makeStore())
        let expense = try categories(ctx, profile.id, kind: .expense).sorted { $0.sortOrder < $1.sortOrder }
        #expect(expense.map(\.sortOrder) == Array(0..<12))
        #expect(expense.map(\.name) == DefaultCatalog.expense.map(\.name))
        #expect(expense.map(\.emoji) == DefaultCatalog.expense.map(\.emoji))
        #expect(DefaultCatalog.income.count == 5)
    }

    @Test func createProfileWithCopiedCategories() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let service = ProfileService(context: ctx)
        let a = try service.bootstrap(store: makeStore())
        let food = try #require(try categories(ctx, a.id, kind: .expense).first { $0.name == "Makanan" })
        let lunch = Category(profileID: a.id, name: "Makan siang", kind: .expense, emoji: "🥗", parent: food)
        lunch.sortOrder = 3
        ctx.insert(lunch)
        let hiddenSource = try #require(try categories(ctx, a.id, kind: .expense).first { $0.name == "Pakaian" })
        hiddenSource.isHidden = true
        try ctx.save()

        let b = try service.createProfile(name: "Bisnis", emoji: "💼", colorHex: "#112233", copyCategoriesFrom: a.id)

        #expect(b.id != a.id)
        let copied = try categories(ctx, b.id)
        #expect(copied.count == 12 + 5 + 1)
        let copiedFood = try #require(copied.first { $0.name == "Makanan" })
        #expect(copiedFood.id != food.id)
        #expect(copiedFood.profileID == b.id)
        #expect(copiedFood.emoji == "🍜")
        #expect(copiedFood.kind == .expense)
        let copiedLunch = try #require(copied.first { $0.name == "Makan siang" })
        #expect(copiedLunch.id != lunch.id)
        #expect(copiedLunch.profileID == b.id)
        #expect(copiedLunch.parent === copiedFood)
        #expect(copiedLunch.emoji == "🥗")
        #expect(copiedLunch.sortOrder == 3)
        #expect(copiedFood.children?.count == 1)
        #expect(try #require(copied.first { $0.name == "Pakaian" }).isHidden)
        // Original untouched
        #expect(food.children?.count == 1)
        #expect(try categories(ctx, a.id).count == 18)
        // Tunai created, nothing else copied
        let accounts = try assets(ctx, b.id)
        #expect(accounts.map(\.name) == ["Tunai"])
        #expect(accounts[0].group == .cash)
        #expect(try transactions(ctx, b.id).isEmpty)
    }

    @Test func createProfileWithoutCopySeedsDefaultsAndSortOrder() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let service = ProfileService(context: ctx)
        let a = try service.bootstrap(store: makeStore())
        let b = try service.createProfile(name: "  Keluarga ", emoji: "🏡", colorHex: "#00FF00", copyCategoriesFrom: nil)
        #expect(b.name == "Keluarga")
        #expect(b.sortOrder == a.sortOrder + 1)
        #expect(try categories(ctx, b.id, kind: .expense).count == 12)
        #expect(try categories(ctx, b.id, kind: .income).count == 5)
        #expect(try assets(ctx, b.id).count == 1)
    }

    @Test func profileIsolation() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let service = ProfileService(context: ctx)
        let a = try service.bootstrap(store: makeStore())
        let b = try service.createProfile(name: "B", emoji: "🅱️", colorHex: "#000000", copyCategoriesFrom: nil)
        for p in [a, b] {
            ctx.insert(MoneyTransaction(profileID: p.id, type: .expense, amount: 1000, date: .now))
        }
        try ctx.save()

        let aID = a.id, bID = b.id
        #expect(try transactions(ctx, aID).allSatisfy { $0.profileID == aID })
        #expect(try assets(ctx, aID).allSatisfy { $0.profileID == aID })
        #expect(try categories(ctx, aID).allSatisfy { $0.profileID == aID })
        #expect(try transactions(ctx, aID).count == 1)
        #expect(try transactions(ctx, bID).count == 1)
        #expect(try assets(ctx, bID).count == 1)
        #expect(try categories(ctx, bID).count == 17)
    }

    @Test func deleteProfileRemovesAllData() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let service = ProfileService(context: ctx)
        let store = makeStore()
        let a = try service.bootstrap(store: store)
        let b = try service.createProfile(name: "B", emoji: "🅱️", colorHex: "#000000", copyCategoriesFrom: nil)
        let bFood = try #require(try categories(ctx, b.id, kind: .expense).first)
        ctx.insert(Category(profileID: b.id, name: "Sub", kind: .expense, parent: bFood))
        let bAsset = try #require(try assets(ctx, b.id).first)
        let tx = MoneyTransaction(profileID: b.id, type: .expense, amount: 500, date: .now)
        tx.asset = bAsset
        tx.category = bFood
        ctx.insert(tx)
        ctx.insert(MoneyTransaction(profileID: a.id, type: .income, amount: 700, date: .now))
        try ctx.save()
        store.switchTo(b.id)
        let aID = a.id, bID = b.id

        try service.deleteProfile(bID, store: store)

        #expect(try transactions(ctx, bID).isEmpty)
        #expect(try assets(ctx, bID).isEmpty)
        #expect(try categories(ctx, bID).isEmpty)
        #expect(try service.profiles().map(\.id) == [aID])
        #expect(store.activeProfileID == aID)
        // Other profile's data survives
        #expect(try transactions(ctx, aID).count == 1)
        #expect(try categories(ctx, aID).count == 17)
        #expect(try assets(ctx, aID).count == 1)
    }

    @Test func cannotDeleteLastProfile() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let service = ProfileService(context: container.mainContext)
        let store = makeStore()
        let a = try service.bootstrap(store: store)
        #expect(throws: ProfileServiceError.lastProfile) {
            try service.deleteProfile(a.id, store: store)
        }
        #expect(try service.profiles().count == 1)
    }

    @Test func emptyNameRejected() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let service = ProfileService(context: container.mainContext)
        let a = try service.bootstrap(store: makeStore())
        #expect(throws: ProfileServiceError.emptyName) {
            _ = try service.createProfile(name: "  ", emoji: "🙂", colorHex: "#FFFFFF", copyCategoriesFrom: nil)
        }
        #expect(throws: ProfileServiceError.emptyName) {
            try service.update(a, name: "  ", emoji: "🙂", colorHex: "#FFFFFF")
        }
        #expect(try service.profiles().count == 1)
        #expect(a.name == "Pribadi")
    }

    @Test func updateTrimsAndSaves() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let service = ProfileService(context: container.mainContext)
        let a = try service.bootstrap(store: makeStore())
        try service.update(a, name: " Pribadi 2 ", emoji: "😎", colorHex: "#ABCDEF")
        #expect(a.name == "Pribadi 2")
        #expect(a.emoji == "😎")
        #expect(a.colorHex == "#ABCDEF")
    }

    @Test func moveReordersProfiles() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let service = ProfileService(context: container.mainContext)
        _ = try service.bootstrap(store: makeStore())
        _ = try service.createProfile(name: "B", emoji: "🙂", colorHex: "#000000", copyCategoriesFrom: nil)
        _ = try service.createProfile(name: "C", emoji: "🙂", colorHex: "#000000", copyCategoriesFrom: nil)
        #expect(try service.profiles().map(\.name) == ["Pribadi", "B", "C"])

        try service.move(from: IndexSet(integer: 2), to: 0)

        #expect(try service.profiles().map(\.name) == ["C", "Pribadi", "B"])
        #expect(try service.profiles().map(\.sortOrder) == [0, 1, 2])
    }
}
