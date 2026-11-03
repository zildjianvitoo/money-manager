import Foundation
import SwiftData
import Testing
@testable import MoneyCore

@MainActor
struct TransactionServiceTests {
    @MainActor private struct Fixture {
        let container: ModelContainer
        let profileID: UUID
        let category: MoneyCategory
        let cash: AssetAccount
        let bank: AssetAccount
        let service: TransactionService
        var context: ModelContext { container.mainContext }
    }

    private func makeFixture() throws -> Fixture {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let profileID = UUID()
        let category = MoneyCategory(profileID: profileID, name: "Makan", kind: .expense)
        let cash = AssetAccount(profileID: profileID, name: "Tunai", group: .cash)
        let bank = AssetAccount(profileID: profileID, name: "BCA", group: .bank)
        ctx.insert(category)
        ctx.insert(cash)
        ctx.insert(bank)
        try ctx.save()
        return Fixture(
            container: container, profileID: profileID, category: category, cash: cash, bank: bank,
            service: TransactionService(context: ctx, profileID: profileID)
        )
    }

    private func expenseDraft(_ f: Fixture, amount: Decimal = 25_000) -> TransactionDraft {
        var d = TransactionDraft(type: .expense, date: Date(timeIntervalSince1970: 1_000_000))
        d.amount = amount
        d.categoryID = f.category.id
        d.assetID = f.cash.id
        return d
    }

    private func transferDraft(_ f: Fixture) -> TransactionDraft {
        var d = TransactionDraft(type: .transfer, date: Date(timeIntervalSince1970: 1_000_000))
        d.amount = 100_000
        d.assetID = f.cash.id
        d.toAssetID = f.bank.id
        return d
    }

    private func allTransactions(_ f: Fixture) throws -> [MoneyTransaction] {
        try f.context.fetch(FetchDescriptor<MoneyTransaction>())
    }

    @Test func createsExpense() throws {
        let f = try makeFixture()
        var d = expenseDraft(f)
        d.note = "Makan siang"
        d.fee = 500 // diabaikan untuk non-transfer

        let tx = try f.service.create(d)

        #expect(tx.profileID == f.profileID)
        #expect(tx.type == .expense)
        #expect(tx.amount == 25_000)
        #expect(tx.fee == 0)
        #expect(tx.category?.id == f.category.id)
        #expect(tx.asset?.id == f.cash.id)
        #expect(tx.toAsset == nil)
        #expect(tx.note == "Makan siang")
        #expect(tx.createdAt == tx.updatedAt)
        #expect(try allTransactions(f).count == 1)
    }

    @Test func createsTransferWithFeeAndNoCategory() throws {
        let f = try makeFixture()
        var d = transferDraft(f)
        d.fee = 2_500
        d.categoryID = f.category.id // diabaikan untuk transfer

        let tx = try f.service.create(d)

        #expect(tx.type == .transfer)
        #expect(tx.fee == 2_500)
        #expect(tx.category == nil)
        #expect(tx.asset?.id == f.cash.id)
        #expect(tx.toAsset?.id == f.bank.id)
    }

    @Test func validationRules() throws {
        let f = try makeFixture()

        var zero = expenseDraft(f)
        zero.amount = 0
        var noCategory = expenseDraft(f)
        noCategory.categoryID = nil
        var noAsset = expenseDraft(f)
        noAsset.assetID = nil
        var noTarget = transferDraft(f)
        noTarget.toAssetID = nil
        var noSource = transferDraft(f)
        noSource.assetID = nil
        var same = transferDraft(f)
        same.toAssetID = same.assetID
        var negativeFee = transferDraft(f)
        negativeFee.fee = -1

        let cases: [(TransactionDraft, TransactionValidationError)] = [
            (zero, .amountNotPositive),
            (noCategory, .missingCategory),
            (noAsset, .missingAsset),
            (noTarget, .missingTargetAsset),
            (noSource, .missingAsset),
            (same, .sameAsset),
            (negativeFee, .negativeFee),
        ]
        for (draft, expected) in cases {
            #expect(throws: expected) { try f.service.validate(draft) }
            #expect(throws: expected) { try f.service.create(draft) }
        }
        #expect(try allTransactions(f).isEmpty)
    }

    @Test func rejectsNegativeAmount() throws {
        let f = try makeFixture()
        #expect(throws: TransactionValidationError.amountNotPositive) {
            try f.service.validate(expenseDraft(f, amount: -5))
        }
    }

    @Test func rejectsAdjustmentDraft() throws {
        let f = try makeFixture()
        var d = expenseDraft(f)
        d.type = .adjustment
        #expect(throws: TransactionValidationError.amountNotPositive) { try f.service.validate(d) }
        #expect(throws: TransactionValidationError.amountNotPositive) { try f.service.create(d) }
        #expect(try allTransactions(f).isEmpty)
    }

    @Test func amountIsCheckedBeforeFee() throws {
        let f = try makeFixture()
        var d = transferDraft(f)
        d.amount = 0
        d.fee = -1
        #expect(throws: TransactionValidationError.amountNotPositive) { try f.service.validate(d) }
    }

    @Test func expenseIgnoresNegativeFee() throws {
        let f = try makeFixture()
        var d = expenseDraft(f)
        d.fee = -1

        let tx = try f.service.create(d)

        #expect(tx.fee == 0)
    }

    @Test func rejectsSubCentAmount() throws {
        let f = try makeFixture()
        #expect(throws: TransactionValidationError.amountNotPositive) {
            try f.service.validate(expenseDraft(f, amount: Decimal(string: "0.004")!))
        }
        #expect(try allTransactions(f).isEmpty)
    }

    @Test func rejectsTooLargeAmountAndFee() throws {
        let f = try makeFixture()
        let tooLarge = Decimal(string: "1000000000000000")!
        #expect(throws: TransactionValidationError.amountTooLarge) {
            try f.service.validate(expenseDraft(f, amount: tooLarge))
        }
        var fee = transferDraft(f)
        fee.fee = tooLarge
        #expect(throws: TransactionValidationError.amountTooLarge) { try f.service.validate(fee) }
        var negative = transferDraft(f)
        negative.amount = -tooLarge
        #expect(throws: TransactionValidationError.amountTooLarge) { try f.service.validate(negative) }
        let maxAmount = Decimal(string: "999999999999999")!
        #expect(throws: Never.self) { try f.service.validate(expenseDraft(f, amount: maxAmount)) }
    }

    private func foreignTransaction(_ f: Fixture) throws -> MoneyTransaction {
        let otherProfile = UUID()
        let category = MoneyCategory(profileID: otherProfile, name: "Asing", kind: .expense)
        let asset = AssetAccount(profileID: otherProfile, name: "Asing", group: .cash)
        f.context.insert(category)
        f.context.insert(asset)
        try f.context.save()
        let other = TransactionService(context: f.context, profileID: otherProfile)
        var d = TransactionDraft(type: .expense, date: Date(timeIntervalSince1970: 1_000_000))
        d.amount = 10_000
        d.categoryID = category.id
        d.assetID = asset.id
        return try other.create(d)
    }

    @Test func updateRejectsForeignTransaction() throws {
        let f = try makeFixture()
        let foreign = try foreignTransaction(f)
        let past = Date(timeIntervalSince1970: 0)
        foreign.updatedAt = past

        #expect(throws: TransactionValidationError.foreignTransaction) {
            try f.service.update(foreign, with: expenseDraft(f, amount: 1))
        }

        #expect(foreign.amount == 10_000)
        #expect(foreign.profileID != f.profileID)
        #expect(foreign.category?.profileID != f.profileID)
        #expect(foreign.updatedAt == past)
    }

    @Test func deleteRejectsForeignTransaction() throws {
        let f = try makeFixture()
        let foreign = try foreignTransaction(f)

        #expect(throws: TransactionValidationError.foreignTransaction) { try f.service.delete(foreign) }

        #expect(try allTransactions(f).count == 1)
    }

    @Test func duplicateRejectsForeignTransaction() throws {
        let f = try makeFixture()
        let foreign = try foreignTransaction(f)

        #expect(throws: TransactionValidationError.foreignTransaction) {
            try f.service.duplicate(foreign, on: .now)
        }

        #expect(try allTransactions(f).count == 1)
    }

    @Test func rejectsForeignProfileIDs() throws {
        let f = try makeFixture()
        let otherProfile = UUID()
        let foreignCategory = MoneyCategory(profileID: otherProfile, name: "Asing", kind: .expense)
        let foreignAsset = AssetAccount(profileID: otherProfile, name: "Asing", group: .bank)
        f.context.insert(foreignCategory)
        f.context.insert(foreignAsset)
        try f.context.save()

        var badCategory = expenseDraft(f)
        badCategory.categoryID = foreignCategory.id
        var badAsset = expenseDraft(f)
        badAsset.assetID = foreignAsset.id
        var badSource = transferDraft(f)
        badSource.assetID = foreignAsset.id
        var badTarget = transferDraft(f)
        badTarget.toAssetID = foreignAsset.id

        #expect(throws: TransactionValidationError.missingCategory) { try f.service.validate(badCategory) }
        #expect(throws: TransactionValidationError.missingAsset) { try f.service.validate(badAsset) }
        #expect(throws: TransactionValidationError.missingAsset) { try f.service.validate(badSource) }
        #expect(throws: TransactionValidationError.missingTargetAsset) { try f.service.validate(badTarget) }
        #expect(throws: TransactionValidationError.missingCategory) { try f.service.create(badCategory) }
        #expect(try allTransactions(f).isEmpty)
    }

    @Test func draftFromTransactionMapsRelationshipsToIDs() throws {
        let f = try makeFixture()
        var d = transferDraft(f)
        d.fee = 1_000
        d.note = "Isi saldo"
        d.detail = "Detail"
        let tx = try f.service.create(d)

        let back = TransactionDraft(from: tx)

        #expect(back == d)
        let expense = try f.service.create(expenseDraft(f))
        #expect(TransactionDraft(from: expense).categoryID == f.category.id)
        #expect(TransactionDraft(from: expense).toAssetID == nil)
    }

    @Test func duplicateCopiesFieldsWithNewDate() throws {
        let f = try makeFixture()
        var d = transferDraft(f)
        d.fee = 1_000
        d.note = "Catatan"
        d.detail = "Rincian"
        let original = try f.service.create(d)
        original.recurringRuleID = UUID()
        original.occurrenceKey = "k"
        original.importBatchID = UUID()
        let newDate = Date(timeIntervalSince1970: 5_000_000)

        let copy = try f.service.duplicate(original, on: newDate)

        #expect(copy.id != original.id)
        #expect(copy.date == newDate)
        #expect(copy.profileID == original.profileID)
        #expect(copy.type == original.type)
        #expect(copy.amount == original.amount)
        #expect(copy.fee == original.fee)
        #expect(copy.category?.id == original.category?.id)
        #expect(copy.asset?.id == original.asset?.id)
        #expect(copy.toAsset?.id == original.toAsset?.id)
        #expect(copy.note == "Catatan")
        #expect(copy.detail == "Rincian")
        #expect(copy.recurringRuleID == nil)
        #expect(copy.occurrenceKey == nil)
        #expect(copy.importBatchID == nil)
        #expect(try allTransactions(f).count == 2)
    }

    @Test func updateChangesFieldsAndTimestamp() throws {
        let f = try makeFixture()
        let tx = try f.service.create(expenseDraft(f))
        let createdAt = tx.createdAt
        let past = Date(timeIntervalSince1970: 0)
        tx.updatedAt = past
        let otherCategory = MoneyCategory(profileID: f.profileID, name: "Transport", kind: .expense)
        f.context.insert(otherCategory)

        var d = TransactionDraft(from: tx)
        d.amount = 99_000
        d.categoryID = otherCategory.id
        d.assetID = f.bank.id
        d.note = "Baru"
        try f.service.update(tx, with: d)

        #expect(tx.amount == 99_000)
        #expect(tx.category?.id == otherCategory.id)
        #expect(tx.asset?.id == f.bank.id)
        #expect(tx.note == "Baru")
        #expect(tx.updatedAt > past)
        #expect(tx.createdAt == createdAt)
    }

    @Test func updateToTransferClearsCategoryAndKeepsFee() throws {
        let f = try makeFixture()
        let tx = try f.service.create(expenseDraft(f))
        var d = transferDraft(f)
        d.fee = 700
        try f.service.update(tx, with: d)

        #expect(tx.type == .transfer)
        #expect(tx.category == nil)
        #expect(tx.toAsset?.id == f.bank.id)
        #expect(tx.fee == 700)
    }

    @Test func failedUpdateDoesNotMutate() throws {
        let f = try makeFixture()
        let tx = try f.service.create(expenseDraft(f))
        var d = TransactionDraft(from: tx)
        d.amount = 1
        d.note = "Tidak boleh tersimpan"
        d.categoryID = UUID() // tidak ada

        #expect(throws: TransactionValidationError.missingCategory) { try f.service.update(tx, with: d) }

        #expect(tx.amount == 25_000)
        #expect(tx.note == "")
        #expect(tx.category?.id == f.category.id)
    }

    @Test func deleteRemoves() throws {
        let f = try makeFixture()
        let tx = try f.service.create(expenseDraft(f))
        #expect(try allTransactions(f).count == 1)

        try f.service.delete(tx)

        #expect(try allTransactions(f).isEmpty)
    }
}
