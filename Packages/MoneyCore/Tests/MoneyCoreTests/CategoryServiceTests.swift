import Foundation
import SwiftData
import Testing
@testable import MoneyCore

@MainActor
struct CategoryServiceTests {
    @MainActor private struct Fixture {
        let container: ModelContainer
        let profileID: UUID
        let service: CategoryService
        var context: ModelContext { container.mainContext }

        func allCategories() throws -> [MoneyCategory] {
            let pid = profileID
            return try context.fetch(FetchDescriptor<MoneyCategory>(predicate: #Predicate { $0.profileID == pid }))
        }

        func allTransactions() throws -> [MoneyTransaction] {
            let pid = profileID
            return try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.profileID == pid }))
        }

        @discardableResult
        func addTransactions(_ count: Int, to category: MoneyCategory) throws -> [MoneyTransaction] {
            let txs = (0..<count).map { _ -> MoneyTransaction in
                let tx = MoneyTransaction(profileID: profileID, type: category.kind == .income ? .income : .expense,
                                          amount: 1_000, date: .now)
                tx.category = category
                context.insert(tx)
                return tx
            }
            try context.save()
            return txs
        }
    }

    private func makeFixture() throws -> Fixture {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let pid = UUID()
        return Fixture(
            container: container, profileID: pid,
            service: CategoryService(context: container.mainContext, profileID: pid)
        )
    }

    @Test func createSubcategory() throws {
        let f = try makeFixture()
        let food = try f.service.create(name: "  Makanan ", emoji: "🍜", kind: .expense, parent: nil)
        let lunch = try f.service.create(name: "Makan siang", emoji: "🍱", kind: .expense, parent: food)

        #expect(food.name == "Makanan")
        #expect(lunch.parent?.id == food.id)
        #expect(food.children?.map(\.id) == [lunch.id])
        #expect(try f.service.topLevel(kind: .expense, includeHidden: true).map(\.name) == ["Makanan"])
    }

    @Test func createRejectsEmptyName() throws {
        let f = try makeFixture()
        #expect(throws: CategoryServiceError.emptyName) {
            try f.service.create(name: "   ", emoji: "", kind: .expense, parent: nil)
        }
    }

    @Test func rejectsThirdLevel() throws {
        let f = try makeFixture()
        let food = try f.service.create(name: "Makanan", emoji: "", kind: .expense, parent: nil)
        let lunch = try f.service.create(name: "Makan siang", emoji: "", kind: .expense, parent: food)
        #expect(throws: CategoryServiceError.nestingTooDeep) {
            try f.service.create(name: "Warteg", emoji: "", kind: .expense, parent: lunch)
        }
    }

    @Test func createRejectsKindMismatch() throws {
        let f = try makeFixture()
        let food = try f.service.create(name: "Makanan", emoji: "", kind: .expense, parent: nil)
        #expect(throws: CategoryServiceError.kindMismatch) {
            try f.service.create(name: "Bonus", emoji: "", kind: .income, parent: food)
        }
    }

    @Test func createAssignsIncreasingSortOrderPerSiblingGroup() throws {
        let f = try makeFixture()
        let a = try f.service.create(name: "A", emoji: "", kind: .expense, parent: nil)
        let b = try f.service.create(name: "B", emoji: "", kind: .expense, parent: nil)
        let income = try f.service.create(name: "Gaji", emoji: "", kind: .income, parent: nil)
        let child = try f.service.create(name: "Anak", emoji: "", kind: .expense, parent: a)
        #expect(a.sortOrder == 0)
        #expect(b.sortOrder == 1)
        #expect(income.sortOrder == 0)
        #expect(child.sortOrder == 0)
    }

    @Test func renameTrimsAndRejectsEmpty() throws {
        let f = try makeFixture()
        let c = try f.service.create(name: "Makanan", emoji: "🍜", kind: .expense, parent: nil)
        try f.service.rename(c, name: " Kuliner ", emoji: "🍔")
        #expect(c.name == "Kuliner")
        #expect(c.emoji == "🍔")
        #expect(throws: CategoryServiceError.emptyName) {
            try f.service.rename(c, name: "  ", emoji: "🍔")
        }
        #expect(c.name == "Kuliner")
    }

    @Test func topLevelFiltersHiddenKindAndSortsByOrderThenName() throws {
        let f = try makeFixture()
        let b = try f.service.create(name: "B", emoji: "", kind: .expense, parent: nil)
        let a = try f.service.create(name: "A", emoji: "", kind: .expense, parent: nil)
        _ = try f.service.create(name: "Gaji", emoji: "", kind: .income, parent: nil)
        _ = try f.service.create(name: "Anak", emoji: "", kind: .expense, parent: a)
        try f.service.setHidden(b, true)

        #expect(try f.service.topLevel(kind: .expense, includeHidden: false).map(\.name) == ["A"])
        #expect(try f.service.topLevel(kind: .expense, includeHidden: true).map(\.name) == ["B", "A"])

        a.sortOrder = 0
        b.sortOrder = 0
        #expect(try f.service.topLevel(kind: .expense, includeHidden: true).map(\.name) == ["A", "B"])
    }

    @Test func reorderRewritesSortOrder() throws {
        let f = try makeFixture()
        for name in ["A", "B", "C", "D"] {
            _ = try f.service.create(name: name, emoji: "", kind: .expense, parent: nil)
        }
        try f.service.move(kind: .expense, parent: nil, from: IndexSet(integer: 2), to: 0)
        let list = try f.service.topLevel(kind: .expense, includeHidden: true)
        #expect(list.map(\.name) == ["C", "A", "B", "D"])
        #expect(list.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test func reorderSubcategoriesAndMoveDown() throws {
        let f = try makeFixture()
        let p = try f.service.create(name: "P", emoji: "", kind: .expense, parent: nil)
        let kids = try ["x", "y", "z"].map { try f.service.create(name: $0, emoji: "", kind: .expense, parent: p) }
        // Array.move(fromOffsets: [0], toOffset: 3) -> [y, z, x]
        try f.service.move(kind: .expense, parent: p, from: IndexSet(integer: 0), to: 3)
        let ordered = (p.children ?? []).sorted { $0.sortOrder < $1.sortOrder }
        #expect(ordered.map(\.name) == ["y", "z", "x"])
        #expect(ordered.map(\.sortOrder) == [0, 1, 2])
        #expect(kids.count == 3)
    }

    @Test func setHiddenTogglesFlag() throws {
        let f = try makeFixture()
        let c = try f.service.create(name: "A", emoji: "", kind: .expense, parent: nil)
        try f.service.setHidden(c, true)
        #expect(c.isHidden)
        try f.service.setHidden(c, false)
        #expect(!c.isHidden)
    }

    @Test func usageCountIncludesSubcategoryTransactions() throws {
        let f = try makeFixture()
        let food = try f.service.create(name: "Makanan", emoji: "", kind: .expense, parent: nil)
        let lunch = try f.service.create(name: "Makan siang", emoji: "", kind: .expense, parent: food)
        let other = try f.service.create(name: "Lainnya", emoji: "", kind: .expense, parent: nil)
        try f.addTransactions(2, to: food)
        try f.addTransactions(3, to: lunch)
        try f.addTransactions(4, to: other)

        #expect(try f.service.usageCount(food) == 5)
        #expect(try f.service.usageCount(lunch) == 3)
        #expect(try f.service.usageCount(other) == 4)
    }

    @Test func deleteUsedRequiresReplacement() throws {
        let f = try makeFixture()
        let food = try f.service.create(name: "Makanan", emoji: "", kind: .expense, parent: nil)
        try f.addTransactions(1, to: food)
        #expect(throws: CategoryServiceError.replacementInvalid) {
            try f.service.delete(food, replacement: nil)
        }
        #expect(try f.allCategories().count == 1)
    }

    @Test func deleteUnusedWithoutReplacement() throws {
        let f = try makeFixture()
        let food = try f.service.create(name: "Makanan", emoji: "", kind: .expense, parent: nil)
        _ = try f.service.create(name: "Makan siang", emoji: "", kind: .expense, parent: food)
        try f.service.delete(food, replacement: nil)
        #expect(try f.allCategories().isEmpty)
    }

    @Test func deleteParentMovesSubcategoryTransactions() throws {
        let f = try makeFixture()
        let food = try f.service.create(name: "Makanan", emoji: "", kind: .expense, parent: nil)
        let lunch = try f.service.create(name: "Makan siang", emoji: "", kind: .expense, parent: food)
        let other = try f.service.create(name: "Lainnya", emoji: "", kind: .expense, parent: nil)
        try f.addTransactions(2, to: food)
        try f.addTransactions(3, to: lunch)

        try f.service.delete(food, replacement: other)

        let cats = try f.allCategories()
        #expect(cats.map(\.name) == ["Lainnya"])
        let txs = try f.allTransactions()
        #expect(txs.count == 5)
        #expect(txs.allSatisfy { $0.category != nil })
        #expect(try f.service.usageCount(other) == 5)
        #expect(other.transactions?.count == 5)
    }

    @Test func deleteSubcategoryKeepsParent() throws {
        let f = try makeFixture()
        let food = try f.service.create(name: "Makanan", emoji: "", kind: .expense, parent: nil)
        let lunch = try f.service.create(name: "Makan siang", emoji: "", kind: .expense, parent: food)
        try f.addTransactions(3, to: lunch)
        try f.service.delete(lunch, replacement: food)
        #expect(try f.allCategories().map(\.name) == ["Makanan"])
        #expect(try f.service.usageCount(food) == 3)
    }

    @Test func replacementMustMatchKindAndProfile() throws {
        let f = try makeFixture()
        let food = try f.service.create(name: "Makanan", emoji: "", kind: .expense, parent: nil)
        let lunch = try f.service.create(name: "Makan siang", emoji: "", kind: .expense, parent: food)
        let salary = try f.service.create(name: "Gaji", emoji: "", kind: .income, parent: nil)
        let foreign = MoneyCategory(profileID: UUID(), name: "Asing", kind: .expense)
        f.context.insert(foreign)
        try f.context.save()
        try f.addTransactions(1, to: food)

        for bad in [salary, foreign, food, lunch] {
            #expect(throws: CategoryServiceError.replacementInvalid) {
                try f.service.delete(food, replacement: bad)
            }
        }
        #expect(try f.allCategories().count == 3)
        #expect(try f.service.usageCount(food) == 1)
    }

    @Test func hiddenCategoryCanBeReplacement() throws {
        let f = try makeFixture()
        let food = try f.service.create(name: "Makanan", emoji: "", kind: .expense, parent: nil)
        let other = try f.service.create(name: "Lainnya", emoji: "", kind: .expense, parent: nil)
        try f.service.setHidden(other, true)
        try f.addTransactions(2, to: food)
        try f.service.delete(food, replacement: other)
        #expect(try f.service.usageCount(other) == 2)
    }

    @Test func foreignCategoryRejected() throws {
        let f = try makeFixture()
        let foreign = MoneyCategory(profileID: UUID(), name: "Asing", kind: .expense)
        f.context.insert(foreign)
        let mine = try f.service.create(name: "Milik", emoji: "", kind: .expense, parent: nil)

        #expect(throws: CategoryServiceError.foreignCategory) {
            try f.service.create(name: "X", emoji: "", kind: .expense, parent: foreign)
        }
        #expect(throws: CategoryServiceError.foreignCategory) { try f.service.rename(foreign, name: "Y", emoji: "") }
        #expect(throws: CategoryServiceError.foreignCategory) { try f.service.setHidden(foreign, true) }
        #expect(throws: CategoryServiceError.foreignCategory) { _ = try f.service.usageCount(foreign) }
        #expect(throws: CategoryServiceError.foreignCategory) { try f.service.delete(foreign, replacement: mine) }
        #expect(throws: CategoryServiceError.foreignCategory) {
            try f.service.move(kind: .expense, parent: foreign, from: IndexSet(integer: 0), to: 1)
        }
        #expect(foreign.name == "Asing")
        #expect(!foreign.isHidden)
    }
}
