import Foundation
import SwiftData
import Testing
@testable import MoneyCore

@MainActor
struct AssetServiceTests {
    @MainActor private struct Fixture {
        let container: ModelContainer
        let profileID: UUID
        let service: AssetService
        var context: ModelContext { container.mainContext }

        func allTransactions() throws -> [MoneyTransaction] {
            let pid = profileID
            return try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.profileID == pid }))
        }
    }

    private func makeFixture() throws -> Fixture {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let pid = UUID()
        return Fixture(
            container: container, profileID: pid,
            service: AssetService(context: container.mainContext, profileID: pid)
        )
    }

    @Test func adjustBalanceCreatesSignedAdjustment() throws {
        let f = try makeFixture()
        let asset = try f.service.create(name: "BCA", group: .bank, initialBalance: 100_000)
        let date = Date(timeIntervalSince1970: 2_000_000)

        let adj = try #require(try f.service.adjustBalance(of: asset, to: 90_000, on: date))
        #expect(adj.type == .adjustment)
        #expect(adj.amount == -10_000)
        #expect(adj.note == "Penyesuaian saldo")
        #expect(adj.date == date)
        #expect(adj.asset?.id == asset.id)
        #expect(BalanceCalculator.balance(of: asset, transactions: try f.allTransactions()) == 90_000)

        let again = try f.service.adjustBalance(of: asset, to: 90_000, on: date)
        #expect(again == nil)
        #expect(try f.allTransactions().count == 1)
    }

    @Test func adjustBalanceUpwardIsPositive() throws {
        let f = try makeFixture()
        let asset = try f.service.create(name: "BCA", group: .bank, initialBalance: 100_000)
        let adj = try #require(try f.service.adjustBalance(of: asset, to: 125_500, on: .now))
        #expect(adj.amount == 25_500)
    }

    @Test func archivedHiddenButBalanceKept() throws {
        let f = try makeFixture()
        let a = try f.service.create(name: "Lama", group: .cash, initialBalance: 50_000)
        let b = try f.service.create(name: "Baru", group: .cash, initialBalance: 1)
        try f.service.setArchived(a, true)

        #expect(try f.service.assets(includeArchived: false).map(\.id) == [b.id])
        #expect(Set(try f.service.assets(includeArchived: true).map(\.id)) == [a.id, b.id])
        #expect(BalanceCalculator.balance(of: a, transactions: []) == 50_000)

        try f.service.setArchived(a, false)
        #expect(try f.service.assets(includeArchived: false).count == 2)
    }

    @Test func createAssignsSortOrderPerGroupAndOrdersByGroup() throws {
        let f = try makeFixture()
        let bank1 = try f.service.create(name: "B1", group: .bank, initialBalance: 0)
        let cash = try f.service.create(name: "Tunai", group: .cash, initialBalance: 0)
        let bank2 = try f.service.create(name: "B2", group: .bank, initialBalance: 0)
        #expect(bank1.sortOrder == 0)
        #expect(bank2.sortOrder == 1)
        #expect(cash.sortOrder == 0)
        // Urut group (cash sebelum bank), lalu sortOrder.
        #expect(try f.service.assets(includeArchived: false).map(\.name) == ["Tunai", "B1", "B2"])
    }

    @Test func assetsAreScopedToProfile() throws {
        let f = try makeFixture()
        let mine = try f.service.create(name: "Punyaku", group: .cash, initialBalance: 0)
        let other = AssetService(context: f.context, profileID: UUID())
        let theirs = try other.create(name: "Punya Lain", group: .cash, initialBalance: 0)
        #expect(try f.service.assets(includeArchived: true).map(\.id) == [mine.id])
        #expect(theirs.sortOrder == 0)
    }

    @Test func adjustBalanceRejectsForeignAsset() throws {
        let f = try makeFixture()
        let other = AssetService(context: f.context, profileID: UUID())
        let foreign = try other.create(name: "Asing", group: .bank, initialBalance: 10)
        #expect(throws: AssetServiceError.foreignAsset) {
            try f.service.adjustBalance(of: foreign, to: 5, on: .now)
        }
        #expect(throws: AssetServiceError.foreignAsset) {
            try f.service.setArchived(foreign, true)
        }
        #expect(try f.allTransactions().isEmpty)
        #expect(foreign.isArchived == false)
    }

    @Test func createRejectsEmptyName() throws {
        let f = try makeFixture()
        #expect(throws: AssetServiceError.emptyName) {
            try f.service.create(name: "  \n ", group: .cash, initialBalance: 0)
        }
        let trimmed = try f.service.create(name: "  Dompet  ", group: .cash, initialBalance: 0)
        #expect(trimmed.name == "Dompet")
    }

    @Test func rejectsAmountsOverCap() throws {
        let f = try makeFixture()
        let big = Decimal(string: "1000000000000000")!
        #expect(throws: AssetServiceError.amountTooLarge) {
            try f.service.create(name: "X", group: .cash, initialBalance: big)
        }
        #expect(throws: AssetServiceError.amountTooLarge) {
            try f.service.create(name: "X", group: .cash, initialBalance: -big)
        }
        let asset = try f.service.create(name: "OK", group: .cash, initialBalance: 0)
        #expect(throws: AssetServiceError.amountTooLarge) {
            try f.service.adjustBalance(of: asset, to: big, on: .now)
        }
        #expect(try f.allTransactions().isEmpty)
    }

    @Test func updateChangesFieldsAndMovesToEndOfNewGroup() throws {
        let f = try makeFixture()
        let asset = try f.service.create(name: "Dompet", group: .cash, initialBalance: 10_000)
        _ = try f.service.create(name: "B1", group: .bank, initialBalance: 0)
        let b2 = try f.service.create(name: "B2", group: .bank, initialBalance: 0)

        try f.service.update(
            asset, name: "  BCA  ", group: .bank, initialBalance: -2_500,
            includeInTotal: false, isArchived: true
        )
        #expect(asset.name == "BCA")
        #expect(asset.group == .bank)
        #expect(asset.initialBalance == -2_500)
        #expect(asset.includeInTotal == false)
        #expect(asset.isArchived == true)
        #expect(asset.sortOrder == b2.sortOrder + 1)

        // Grup yang sama tidak mengubah urutan.
        try f.service.update(
            asset, name: "BCA", group: .bank, initialBalance: 0, includeInTotal: true, isArchived: false
        )
        #expect(asset.sortOrder == b2.sortOrder + 1)
    }

    @Test func updateRejectsInvalidInputAndForeignAsset() throws {
        let f = try makeFixture()
        let asset = try f.service.create(name: "Dompet", group: .cash, initialBalance: 10_000)
        #expect(throws: AssetServiceError.emptyName) {
            try f.service.update(
                asset, name: " ", group: .bank, initialBalance: 1, includeInTotal: false, isArchived: true
            )
        }
        #expect(throws: AssetServiceError.amountTooLarge) {
            try f.service.update(
                asset, name: "X", group: .bank, initialBalance: Decimal(string: "1000000000000000")!,
                includeInTotal: false, isArchived: true
            )
        }
        // Gagal validasi tidak mengubah apa pun.
        #expect(asset.name == "Dompet")
        #expect(asset.group == .cash)
        #expect(asset.initialBalance == 10_000)
        #expect(asset.includeInTotal == true)
        #expect(asset.isArchived == false)

        let other = AssetService(context: f.context, profileID: UUID())
        let foreign = try other.create(name: "Asing", group: .bank, initialBalance: 10)
        #expect(throws: AssetServiceError.foreignAsset) {
            try f.service.update(
                foreign, name: "Dicuri", group: .cash, initialBalance: 0, includeInTotal: true, isArchived: false
            )
        }
        #expect(foreign.name == "Asing")
        #expect(foreign.group == .bank)
    }
}
