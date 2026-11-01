import Foundation
import SwiftData

/// Nilai mentah sebuah form transaksi. Relasi dinyatakan lewat id agar mudah di-bind dari UI.
public struct TransactionDraft: Equatable {
    public var type: TransactionType
    public var amount: Decimal
    public var fee: Decimal
    public var date: Date
    public var categoryID: UUID?
    public var assetID: UUID?
    public var toAssetID: UUID?
    public var note: String
    public var detail: String

    public init(type: TransactionType, date: Date) {
        self.type = type
        self.amount = 0
        self.fee = 0
        self.date = date
        self.categoryID = nil
        self.assetID = nil
        self.toAssetID = nil
        self.note = ""
        self.detail = ""
    }

    public init(from tx: MoneyTransaction) {
        self.type = tx.type
        self.amount = tx.amount
        self.fee = tx.fee
        self.date = tx.date
        self.categoryID = tx.category?.id
        self.assetID = tx.asset?.id
        self.toAssetID = tx.toAsset?.id
        self.note = tx.note
        self.detail = tx.detail
    }
}

public enum TransactionValidationError: Error, Equatable {
    case amountNotPositive, missingCategory, missingAsset, missingTargetAsset, sameAsset, negativeFee
}

/// Membuat, mengubah, menghapus, dan menduplikasi transaksi milik satu profil.
/// Kategori dan aset hanya di-resolve dari `profileID` service ini.
@MainActor
public struct TransactionService {
    private let context: ModelContext
    private let profileID: UUID

    public init(context: ModelContext, profileID: UUID) {
        self.context = context
        self.profileID = profileID
    }

    /// Satu-satunya sumber aturan validasi.
    /// Urutan: amount, fee, lalu aturan khusus tipe. Draft `.adjustment` ditolak (hanya dibuat oleh AssetService).
    public func validate(_ d: TransactionDraft) throws(TransactionValidationError) {
        _ = try resolve(d)
    }

    @discardableResult
    public func create(_ d: TransactionDraft) throws -> MoneyTransaction {
        let resolved = try resolve(d)
        let now = Date.now
        let tx = MoneyTransaction(profileID: profileID, type: d.type, amount: d.amount, date: d.date)
        apply(d, resolved, to: tx)
        tx.createdAt = now
        tx.updatedAt = now
        context.insert(tx)
        try context.save()
        return tx
    }

    public func update(_ tx: MoneyTransaction, with d: TransactionDraft) throws {
        let resolved = try resolve(d)
        apply(d, resolved, to: tx)
        tx.updatedAt = .now
        try context.save()
    }

    public func delete(_ tx: MoneyTransaction) throws {
        context.delete(tx)
        try context.save()
    }

    /// Menyalin tipe, nominal, biaya, kategori, aset, catatan, dan detail ke transaksi baru bertanggal `date`.
    /// Tidak menyalin kaitan recurring/impor.
    @discardableResult
    public func duplicate(_ tx: MoneyTransaction, on date: Date) throws -> MoneyTransaction {
        let now = Date.now
        let copy = MoneyTransaction(profileID: tx.profileID, type: tx.type, amount: tx.amount, date: date)
        copy.fee = tx.fee
        copy.category = tx.category
        copy.asset = tx.asset
        copy.toAsset = tx.toAsset
        copy.note = tx.note
        copy.detail = tx.detail
        copy.createdAt = now
        copy.updatedAt = now
        context.insert(copy)
        try context.save()
        return copy
    }

    // MARK: - Private

    private struct Resolved {
        var category: MoneyCategory?
        var asset: AssetAccount?
        var toAsset: AssetAccount?
    }

    /// Memvalidasi draft dan me-resolve relasinya tanpa mengubah apa pun.
    private func resolve(_ d: TransactionDraft) throws(TransactionValidationError) -> Resolved {
        guard d.type != .adjustment, d.amount > 0 else { throw .amountNotPositive }
        guard d.fee >= 0 else { throw .negativeFee }

        switch d.type {
        case .income, .expense:
            guard let category = fetchCategory(d.categoryID) else { throw .missingCategory }
            guard let asset = fetchAsset(d.assetID) else { throw .missingAsset }
            return Resolved(category: category, asset: asset, toAsset: nil)
        case .transfer:
            guard let asset = fetchAsset(d.assetID) else { throw .missingAsset }
            guard let toAsset = fetchAsset(d.toAssetID) else { throw .missingTargetAsset }
            guard asset.id != toAsset.id else { throw .sameAsset }
            return Resolved(category: nil, asset: asset, toAsset: toAsset)
        case .adjustment:
            throw .amountNotPositive
        }
    }

    private func apply(_ d: TransactionDraft, _ r: Resolved, to tx: MoneyTransaction) {
        tx.type = d.type
        tx.amount = d.amount
        tx.fee = d.type == .transfer ? d.fee : 0
        tx.date = d.date
        tx.category = r.category
        tx.asset = r.asset
        tx.toAsset = r.toAsset
        tx.note = d.note
        tx.detail = d.detail
    }

    private func fetchCategory(_ id: UUID?) -> MoneyCategory? {
        guard let id else { return nil }
        let pid = profileID
        var descriptor = FetchDescriptor<MoneyCategory>(predicate: #Predicate { $0.id == id && $0.profileID == pid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchAsset(_ id: UUID?) -> AssetAccount? {
        guard let id else { return nil }
        let pid = profileID
        var descriptor = FetchDescriptor<AssetAccount>(predicate: #Predicate { $0.id == id && $0.profileID == pid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
