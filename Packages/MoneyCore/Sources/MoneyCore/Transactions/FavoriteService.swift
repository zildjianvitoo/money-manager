import Foundation
import SwiftData

public enum FavoriteServiceError: Error, Equatable {
    case emptyName, unsupportedType, foreignFavorite
}

/// Favorit (template transaksi) milik satu profil.
@MainActor
public struct FavoriteService {
    private let context: ModelContext
    private let profileID: UUID

    public init(context: ModelContext, profileID: UUID) {
        self.context = context
        self.profileID = profileID
    }

    public func favorites() throws -> [FavoriteTemplate] {
        let pid = profileID
        return try context.fetch(FetchDescriptor<FavoriteTemplate>(
            predicate: #Predicate { $0.profileID == pid },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
    }

    /// Menyimpan isi `draft` sebagai template. Nominal ikut disimpan bila `includeAmount` dan nominalnya > 0.
    /// Penyesuaian saldo tidak bisa dijadikan favorit.
    @discardableResult
    public func create(name: String, from draft: TransactionDraft, includeAmount: Bool) throws -> FavoriteTemplate {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FavoriteServiceError.emptyName }
        guard draft.type != .adjustment else { throw FavoriteServiceError.unsupportedType }

        let favorite = FavoriteTemplate(profileID: profileID, name: trimmed, type: draft.type)
        favorite.categoryID = draft.categoryID
        favorite.assetID = draft.assetID
        favorite.toAssetID = draft.toAssetID
        favorite.note = draft.note
        if includeAmount, draft.amount > 0 { favorite.amount = draft.amount }
        favorite.sortOrder = (try favorites().map(\.sortOrder).max() ?? -1) + 1
        context.insert(favorite)
        try context.save()
        return favorite
    }

    public func delete(_ favorite: FavoriteTemplate) throws {
        guard favorite.profileID == profileID else { throw FavoriteServiceError.foreignFavorite }
        context.delete(favorite)
        try context.save()
    }

    /// Mengisi `draft` dari template: jenis, kategori, aset, catatan, dan nominal bila ada. Tanggal dan fee tidak diubah.
    /// Kategori/aset yang sudah tidak ada (atau milik profil lain) dikosongkan.
    public func apply(_ favorite: FavoriteTemplate, to draft: inout TransactionDraft) throws {
        guard favorite.profileID == profileID else { throw FavoriteServiceError.foreignFavorite }
        let pid = profileID
        let categoryIDs = Set(try context.fetch(FetchDescriptor<MoneyCategory>(predicate: #Predicate { $0.profileID == pid })).map(\.id))
        let assetIDs = Set(try context.fetch(FetchDescriptor<AssetAccount>(predicate: #Predicate { $0.profileID == pid })).map(\.id))

        draft.type = favorite.type
        draft.categoryID = favorite.categoryID.flatMap { categoryIDs.contains($0) ? $0 : nil }
        draft.assetID = favorite.assetID.flatMap { assetIDs.contains($0) ? $0 : nil }
        draft.toAssetID = favorite.toAssetID.flatMap { assetIDs.contains($0) ? $0 : nil }
        draft.note = favorite.note
        if let amount = favorite.amount { draft.amount = amount }
    }
}
