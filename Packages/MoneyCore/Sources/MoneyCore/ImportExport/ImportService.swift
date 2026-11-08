import Foundation
import SwiftData

public struct MonthTotal: Equatable, Hashable, Sendable {
    public let year: Int
    public let month: Int
    public var income: Decimal
    public var expense: Decimal
}

public struct ImportPreview: Equatable, Sendable {
    public var rowCount: Int
    public var firstDate: Date?
    public var lastDate: Date?
    public var months: [MonthTotal]
    public var newCategoryNames: [String]
    public var newAssetNames: [String]
    /// Baris yang identik dengan transaksi yang sudah ada di profil tujuan.
    public var duplicateCount: Int
}

public struct ImportOutcome: Equatable {
    public let batchID: UUID
    public let imported: Int
    public let skipped: Int
}

public enum ImportServiceError: Error, Equatable {
    case nothingToImport, foreignBatch
}

/// Pratinjau, simpan (satu operasi, rollback bila gagal), dan undo import untuk satu profil.
@MainActor
public struct ImportService {
    private let context: ModelContext
    private let profileID: UUID

    public init(context: ModelContext, profileID: UUID) {
        self.context = context
        self.profileID = profileID
    }

    // MARK: - Preview

    public func preview(_ rows: [ImportRow], calendar: Calendar = .current) throws -> ImportPreview {
        let categories = try fetchCategories()
        let assets = try fetchAssets()
        var newCategories: [String] = []
        var knownCategoryKeys = Set(categories.map(Self.categoryKey))
        var seenAssets = Set(assets.map { Self.norm($0.name) })
        var newAssets: [String] = []

        for row in rows {
            if row.type != .transfer {
                let kind: CategoryKind = row.type == .income ? .income : .expense
                let topKey = Self.key(kind, nil, row.categoryName)
                if knownCategoryKeys.insert(topKey).inserted { newCategories.append(row.categoryName) }
                if !row.subcategoryName.isEmpty,
                   knownCategoryKeys.insert(Self.key(kind, row.categoryName, row.subcategoryName)).inserted {
                    newCategories.append("\(row.categoryName) › \(row.subcategoryName)")
                }
            }
            for name in [row.assetName, row.toAssetName] where !name.isEmpty {
                if seenAssets.insert(Self.norm(name)).inserted { newAssets.append(name) }
            }
        }

        var byMonth: [Int: MonthTotal] = [:]
        for row in rows {
            let parts = calendar.dateComponents([.year, .month], from: row.date)
            let id = parts.year! * 100 + parts.month!
            var total = byMonth[id] ?? MonthTotal(year: parts.year!, month: parts.month!, income: 0, expense: 0)
            switch row.type {
            case .income: total.income += row.amount
            case .expense: total.expense += row.amount
            case .transfer: total.expense += row.fee
            case .adjustment: break
            }
            byMonth[id] = total
        }

        return ImportPreview(
            rowCount: rows.count,
            firstDate: rows.map(\.date).min(),
            lastDate: rows.map(\.date).max(),
            months: byMonth.keys.sorted().map { byMonth[$0]! },
            newCategoryNames: newCategories,
            newAssetNames: newAssets,
            duplicateCount: try duplicateFlags(rows).filter { $0 }.count
        )
    }

    // MARK: - Import

    @discardableResult
    public func commit(
        _ rows: [ImportRow], assets specs: [ImportAssetSpec] = [], fileName: String, skipDuplicates: Bool = true
    ) throws -> ImportOutcome {
        let flags = skipDuplicates ? try duplicateFlags(rows) : Array(repeating: false, count: rows.count)
        let toImport = zip(rows, flags).filter { !$0.1 }.map(\.0)
        guard !toImport.isEmpty else { throw ImportServiceError.nothingToImport }

        let batch = ImportBatch(profileID: profileID, fileName: fileName)
        batch.rowCount = toImport.count
        batch.skippedCount = rows.count - toImport.count

        do {
            var categories = try fetchCategories()
            var assets = try fetchAssets()
            var createdCategories: [UUID] = []
            var createdAssets: [UUID] = []

            func asset(named name: String) -> AssetAccount {
                if let found = assets.first(where: { Self.norm($0.name) == Self.norm(name) }) { return found }
                let spec = specs.first { Self.norm($0.name) == Self.norm(name) }
                let created = AssetAccount(profileID: profileID, name: name, group: spec?.group ?? .other)
                created.sortOrder = (assets.map(\.sortOrder).max() ?? -1) + 1
                context.insert(created)
                assets.append(created)
                createdAssets.append(created.id)
                return created
            }

            func category(_ kind: CategoryKind, _ name: String, parent: MoneyCategory?) -> MoneyCategory {
                let match = categories.first {
                    $0.kind == kind && Self.norm($0.name) == Self.norm(name) && $0.parent?.id == parent?.id
                }
                if let match { return match }
                let created = MoneyCategory(
                    profileID: profileID, name: name, kind: kind, emoji: kind == .income ? "💰" : "🏷️", parent: parent
                )
                created.sortOrder = (categories.filter { $0.parent?.id == parent?.id && $0.kind == kind }.map(\.sortOrder).max() ?? -1) + 1
                context.insert(created)
                categories.append(created)
                createdCategories.append(created.id)
                return created
            }

            let now = Date.now
            var netByAsset: [UUID: Decimal] = [:]
            for row in toImport {
                let tx = MoneyTransaction(profileID: profileID, type: row.type, amount: row.amount, date: row.date)
                tx.note = row.note
                tx.detail = row.detail
                tx.importBatchID = batch.id
                tx.createdAt = now
                tx.updatedAt = now
                let from = asset(named: row.assetName)
                tx.asset = from
                switch row.type {
                case .income, .expense:
                    let kind: CategoryKind = row.type == .income ? .income : .expense
                    let top = category(kind, row.categoryName, parent: nil)
                    tx.category = row.subcategoryName.isEmpty ? top : category(kind, row.subcategoryName, parent: top)
                    netByAsset[from.id, default: 0] += row.type == .income ? row.amount : -row.amount
                case .transfer:
                    let to = asset(named: row.toAssetName)
                    tx.toAsset = to
                    tx.fee = row.fee
                    netByAsset[from.id, default: 0] -= row.amount + row.fee
                    netByAsset[to.id, default: 0] += row.amount
                case .adjustment:
                    break
                }
                context.insert(tx)
            }

            // Saldo awal aset baru = saldo sekarang di file dikurangi pengaruh transaksi yang diimpor.
            for id in createdAssets {
                guard let created = assets.first(where: { $0.id == id }),
                      let current = specs.first(where: { Self.norm($0.name) == Self.norm(created.name) })?.currentBalance
                else { continue }
                created.initialBalance = current - (netByAsset[id] ?? 0)
            }

            batch.createdCategoryIDs = createdCategories
            batch.createdAssetIDs = createdAssets
            context.insert(batch)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return ImportOutcome(batchID: batch.id, imported: toImport.count, skipped: rows.count - toImport.count)
    }

    // MARK: - History & undo

    public func batches() throws -> [ImportBatch] {
        let pid = profileID
        return try context.fetch(FetchDescriptor<ImportBatch>(
            predicate: #Predicate { $0.profileID == pid }, sortBy: [SortDescriptor(\.importedAt, order: .reverse)]
        ))
    }

    /// Menghapus semua transaksi batch, lalu kategori dan aset yang dibuat batch bila sudah tidak dipakai.
    public func undo(_ batch: ImportBatch) throws {
        guard batch.profileID == profileID else { throw ImportServiceError.foreignBatch }
        let pid = profileID
        let batchID = batch.id
        do {
            let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>(
                predicate: #Predicate { $0.profileID == pid && $0.importBatchID == batchID }
            ))
            for tx in transactions { context.delete(tx) }
            try context.save()

            let categoryIDs = Set(batch.createdCategoryIDs)
            let created = try fetchCategories().filter { categoryIDs.contains($0.id) }
            // Subkategori dulu, supaya induknya terhitung kosong.
            for category in created.sorted(by: { ($0.parent == nil ? 1 : 0) < ($1.parent == nil ? 1 : 0) }) {
                if (category.transactions ?? []).isEmpty && (category.children ?? []).isEmpty {
                    context.delete(category)
                    try context.save()
                }
            }
            let assetIDs = Set(batch.createdAssetIDs)
            for asset in try fetchAssets() where assetIDs.contains(asset.id) {
                if (asset.outgoing ?? []).isEmpty && (asset.incoming ?? []).isEmpty { context.delete(asset) }
            }
            context.delete(batch)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: - Private

    private func fetchCategories() throws -> [MoneyCategory] {
        let pid = profileID
        return try context.fetch(FetchDescriptor<MoneyCategory>(predicate: #Predicate { $0.profileID == pid }))
    }

    private func fetchAssets() throws -> [AssetAccount] {
        let pid = profileID
        return try context.fetch(FetchDescriptor<AssetAccount>(predicate: #Predicate { $0.profileID == pid }))
    }

    /// Per baris: true bila sudah ada transaksi identik (tanggal, nominal, jenis, aset, kategori, catatan).
    /// Setiap transaksi yang sudah ada hanya "dipakai" satu kali, jadi dua baris kembar sah di file tetap lolos
    /// pada import pertama.
    private func duplicateFlags(_ rows: [ImportRow]) throws -> [Bool] {
        let pid = profileID
        let existing = try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.profileID == pid }))
        var remaining: [String: Int] = [:]
        for tx in existing where tx.type != .adjustment {
            let category = tx.category
            let top = category?.parent ?? category
            let sub = category?.parent == nil ? nil : category
            remaining[Self.signature(
                type: tx.type, date: tx.date, amountMinor: tx.amountMinor, asset: tx.asset?.name ?? "",
                toAsset: tx.toAsset?.name ?? "", category: top?.name ?? "", sub: sub?.name ?? "", note: tx.note
            ), default: 0] += 1
        }
        return rows.map { row in
            let sig = Self.signature(
                type: row.type, date: row.date, amountMinor: row.amount.minorUnits, asset: row.assetName,
                toAsset: row.toAssetName, category: row.categoryName, sub: row.subcategoryName, note: row.note
            )
            guard let count = remaining[sig], count > 0 else { return false }
            remaining[sig] = count - 1
            return true
        }
    }

    private static func signature(
        type: TransactionType, date: Date, amountMinor: Int64, asset: String, toAsset: String,
        category: String, sub: String, note: String
    ) -> String {
        [type.rawValue, String(Int64(date.timeIntervalSince1970.rounded())), String(amountMinor), norm(asset),
         norm(toAsset), norm(category), norm(sub), norm(note)].joined(separator: "|")
    }

    static func norm(_ s: String) -> String { s.trimmed.lowercased() }

    private static func key(_ kind: CategoryKind, _ parent: String?, _ name: String) -> String {
        "\(kind.rawValue)|\(norm(parent ?? ""))|\(norm(name))"
    }

    private static func categoryKey(_ c: MoneyCategory) -> String {
        key(c.kind, c.parent?.name, c.name)
    }
}
