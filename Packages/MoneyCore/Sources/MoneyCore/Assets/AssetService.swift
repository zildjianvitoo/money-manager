import Foundation
import SwiftData

public enum AssetServiceError: Error, Equatable {
    case emptyName, foreignAsset, amountTooLarge
}

/// Daftar, pembuatan, penyesuaian saldo, dan pengarsipan aset milik satu profil.
@MainActor
public struct AssetService {
    private let context: ModelContext
    private let profileID: UUID

    public init(context: ModelContext, profileID: UUID) {
        self.context = context
        self.profileID = profileID
    }

    /// Urut menurut `AssetGroup.allCases`, lalu `sortOrder`, lalu nama.
    public func assets(includeArchived: Bool) throws -> [AssetAccount] {
        let pid = profileID
        let all = try context.fetch(FetchDescriptor<AssetAccount>(predicate: #Predicate { $0.profileID == pid }))
        let groupIndex = Dictionary(uniqueKeysWithValues: AssetGroup.allCases.enumerated().map { ($1.rawValue, $0) })
        return all
            .filter { includeArchived || !$0.isArchived }
            .sorted {
                let (g0, g1) = (groupIndex[$0.groupRaw] ?? Int.max, groupIndex[$1.groupRaw] ?? Int.max)
                if g0 != g1 { return g0 < g1 }
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.name < $1.name
            }
    }

    @discardableResult
    public func create(name: String, group: AssetGroup, initialBalance: Decimal) throws -> AssetAccount {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AssetServiceError.emptyName }
        try requireWithinCap(initialBalance)

        let pid = profileID
        let raw = group.rawValue
        let sameGroup = try context.fetch(
            FetchDescriptor<AssetAccount>(predicate: #Predicate { $0.profileID == pid && $0.groupRaw == raw })
        )
        let asset = AssetAccount(profileID: profileID, name: trimmed, group: group, initialBalance: initialBalance)
        asset.sortOrder = (sameGroup.map(\.sortOrder).max() ?? -1) + 1
        context.insert(asset)
        try context.save()
        return asset
    }

    /// Membuat transaksi `.adjustment` bertanda sebesar `actual − saldo sekarang`. `nil` bila selisih 0.
    @discardableResult
    public func adjustBalance(of asset: AssetAccount, to actual: Decimal, on date: Date) throws -> MoneyTransaction? {
        try requireOwned(asset)
        try requireWithinCap(actual)

        let pid = profileID
        let txs = try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.profileID == pid }))
        let difference = actual - BalanceCalculator.balance(of: asset, transactions: txs)
        guard difference.minorUnits != 0 else { return nil }

        let now = Date.now
        let tx = MoneyTransaction(profileID: profileID, type: .adjustment, amount: difference, date: date)
        tx.asset = asset
        tx.note = "Penyesuaian saldo"
        tx.createdAt = now
        tx.updatedAt = now
        context.insert(tx)
        try context.save()
        return tx
    }

    public func setArchived(_ asset: AssetAccount, _ archived: Bool) throws {
        try requireOwned(asset)
        asset.isArchived = archived
        try context.save()
    }

    // MARK: - Private

    /// Batas nominal yang sama dengan TransactionService dan AmountParser.
    private static let maxAmount = Decimal(string: "999999999999999")!

    private func requireOwned(_ asset: AssetAccount) throws {
        guard asset.profileID == profileID else { throw AssetServiceError.foreignAsset }
    }

    /// `minorUnits` trap pada NaN, jadi NaN ditolak bersama nominal terlalu besar.
    private func requireWithinCap(_ value: Decimal) throws {
        guard !value.isNaN, abs(value) <= Self.maxAmount else { throw AssetServiceError.amountTooLarge }
    }
}
