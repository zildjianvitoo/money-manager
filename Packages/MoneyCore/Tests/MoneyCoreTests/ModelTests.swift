import Testing
import Foundation
import SwiftData
@testable import MoneyCore

@MainActor @Test func persistsAndFiltersByProfile() throws {
    let container = try MoneySchema.makeContainer(inMemory: true)
    let ctx = container.mainContext
    let a = UUID(), b = UUID()
    let tx = MoneyTransaction(profileID: a, type: .expense, amount: 19000, date: .now)
    ctx.insert(tx); ctx.insert(MoneyTransaction(profileID: b, type: .income, amount: 5, date: .now))
    try ctx.save()
    let onlyA = try ctx.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.profileID == a }))
    #expect(onlyA.count == 1)
    #expect(onlyA[0].amount == 19000)
    #expect(onlyA[0].amountMinor == 1_900_000)
}

@MainActor @Test func subcategoryRelationship() throws {
    let container = try MoneySchema.makeContainer(inMemory: true)
    let ctx = container.mainContext
    let p = UUID()
    let food = Category(profileID: p, name: "Makanan", kind: .expense)
    let lunch = Category(profileID: p, name: "Makan siang", kind: .expense, parent: food)
    ctx.insert(food); ctx.insert(lunch); try ctx.save()
    #expect(food.children?.count == 1)
}

@Test func amountAndFeeSettersWriteMinorUnits() {
    let tx = MoneyTransaction(profileID: UUID(), type: .transfer, amount: 0, date: .now)
    tx.amount = Decimal(string: "12500.5")!
    tx.fee = 2500
    #expect(tx.amountMinor == 1_250_050)
    #expect(tx.feeMinor == 250_000)
    #expect(tx.amount == Decimal(string: "12500.5")!)
    #expect(tx.fee == 2500)
}

@Test func enumBackedComputedProperties() {
    let tx = MoneyTransaction(profileID: UUID(), type: .adjustment, amount: 1, date: .now)
    #expect(tx.typeRaw == "adjustment")
    #expect(tx.type == .adjustment)
    let acc = AssetAccount(profileID: UUID(), name: "BCA", group: .bank, initialBalance: 1000)
    #expect(acc.groupRaw == "bank")
    #expect(acc.group == .bank)
    #expect(acc.initialBalanceMinor == 100_000)
    #expect(acc.initialBalance == 1000)
    let cat = Category(profileID: UUID(), name: "Gaji", kind: .income)
    #expect(cat.kindRaw == "income")
    #expect(cat.kind == .income)
    #expect(AssetGroup.eWallet.displayName == "E-Wallet")
    #expect(Profile(name: "Saya").emoji == "🙂")
}

@MainActor @Test func transferLinksBothAssets() throws {
    let container = try MoneySchema.makeContainer(inMemory: true)
    let ctx = container.mainContext
    let p = UUID()
    let cash = AssetAccount(profileID: p, name: "Tunai", group: .cash)
    let bank = AssetAccount(profileID: p, name: "BCA", group: .bank)
    let tx = MoneyTransaction(profileID: p, type: .transfer, amount: 50000, date: .now)
    tx.asset = cash; tx.toAsset = bank
    ctx.insert(cash); ctx.insert(bank); ctx.insert(tx); try ctx.save()
    #expect(cash.outgoing?.count == 1)
    #expect(bank.incoming?.count == 1)
}
