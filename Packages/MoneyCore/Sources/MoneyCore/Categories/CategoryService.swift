import Foundation
import SwiftData

public enum CategoryServiceError: Error, Equatable {
    case emptyName, nestingTooDeep, replacementInvalid, foreignCategory, kindMismatch
}

/// Kategori dan subkategori (satu level) milik satu profil: buat, ganti nama, urutkan, sembunyikan, hapus.
@MainActor
public struct CategoryService {
    private let context: ModelContext
    private let profileID: UUID

    public init(context: ModelContext, profileID: UUID) {
        self.context = context
        self.profileID = profileID
    }

    /// Hanya kategori tanpa induk; urut `sortOrder`, lalu nama.
    public func topLevel(kind: CategoryKind, includeHidden: Bool) throws -> [MoneyCategory] {
        try siblings(kind: kind, parent: nil).filter { includeHidden || !$0.isHidden }
    }

    @discardableResult
    public func create(name: String, emoji: String, kind: CategoryKind, parent: MoneyCategory?) throws -> MoneyCategory {
        let trimmed = try trimmedName(name)
        if let parent {
            try requireOwned(parent)
            guard parent.parent == nil else { throw CategoryServiceError.nestingTooDeep }
            guard parent.kind == kind else { throw CategoryServiceError.kindMismatch }
        }

        let sameSiblings = try siblings(kind: kind, parent: parent)
        let category = MoneyCategory(profileID: profileID, name: trimmed, kind: kind, emoji: emoji, parent: parent)
        category.sortOrder = (sameSiblings.map(\.sortOrder).max() ?? -1) + 1
        context.insert(category)
        try context.save()
        return category
    }

    public func rename(_ c: MoneyCategory, name: String, emoji: String) throws {
        try requireOwned(c)
        let trimmed = try trimmedName(name)
        c.name = trimmed
        c.emoji = emoji
        try context.save()
    }

    /// Memindahkan elemen daftar saudara seperti `Array.move(fromOffsets:toOffset:)`, lalu menulis ulang `sortOrder` 0...n-1.
    public func move(kind: CategoryKind, parent: MoneyCategory?, from: IndexSet, to: Int) throws {
        if let parent { try requireOwned(parent) }
        var list = try siblings(kind: kind, parent: parent)

        let moving = from.filter { list.indices.contains($0) }.map { list[$0] }
        let destination = min(max(to, 0), list.count)
        let before = from.filter { $0 < destination && list.indices.contains($0) }.count
        for index in from.sorted(by: >) where list.indices.contains(index) { list.remove(at: index) }
        list.insert(contentsOf: moving, at: destination - before)

        for (index, category) in list.enumerated() { category.sortOrder = index }
        try context.save()
    }

    public func setHidden(_ c: MoneyCategory, _ hidden: Bool) throws {
        try requireOwned(c)
        c.isHidden = hidden
        try context.save()
    }

    /// Jumlah transaksi pada kategori ini dan semua subkategorinya.
    public func usageCount(_ c: MoneyCategory) throws -> Int {
        try requireOwned(c)
        return try affectedTransactions(of: c).count
    }

    /// Transaksi kategori dan subkategorinya dipindah ke `replacement` (wajib bila terpakai), lalu subkategori dan kategori dihapus.
    public func delete(_ c: MoneyCategory, replacement: MoneyCategory?) throws {
        try requireOwned(c)
        let transactions = try affectedTransactions(of: c)

        if let replacement { try requireValidReplacement(replacement, for: c) }
        if !transactions.isEmpty && replacement == nil { throw CategoryServiceError.replacementInvalid }

        if let replacement {
            for tx in transactions { tx.category = replacement }
        }
        for child in c.children ?? [] { context.delete(child) }
        context.delete(c)
        try context.save()
    }

    // MARK: - Private

    private func requireOwned(_ c: MoneyCategory) throws {
        guard c.profileID == profileID else { throw CategoryServiceError.foreignCategory }
    }

    private func trimmedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CategoryServiceError.emptyName }
        return trimmed
    }

    private func requireValidReplacement(_ replacement: MoneyCategory, for c: MoneyCategory) throws {
        guard replacement.profileID == profileID,
              replacement.kind == c.kind,
              replacement.id != c.id,
              replacement.parent?.id != c.id
        else { throw CategoryServiceError.replacementInvalid }
    }

    /// Kategori profil ini dengan jenis dan induk yang sama, urut `sortOrder` lalu nama.
    private func siblings(kind: CategoryKind, parent: MoneyCategory?) throws -> [MoneyCategory] {
        let pid = profileID
        let raw = kind.rawValue
        let all = try context.fetch(
            FetchDescriptor<MoneyCategory>(predicate: #Predicate { $0.profileID == pid && $0.kindRaw == raw })
        )
        return all
            .filter { $0.parent?.id == parent?.id }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.name < $1.name
            }
    }

    private func affectedTransactions(of c: MoneyCategory) throws -> [MoneyTransaction] {
        let pid = profileID
        let all = try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.profileID == pid }))
        return all.filter { tx in
            guard let category = tx.category else { return false }
            return category.id == c.id || category.parent?.id == c.id
        }
    }
}
