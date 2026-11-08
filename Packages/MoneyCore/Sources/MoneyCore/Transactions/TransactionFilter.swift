import Foundation

/// Kriteria filter transaksi. Kriteria kosong = tidak membatasi. Semua kriteria yang aktif harus terpenuhi (AND).
public struct TransactionFilter: Equatable, Sendable {
    /// Kosong = semua jenis.
    public var types: Set<TransactionType> = []
    /// Kategori induk atau subkategori. Memilih induk ikut menyertakan subkategorinya.
    /// Transaksi tanpa kategori (transfer) tidak lolos bila kriteria ini aktif.
    public var categoryIDs: Set<UUID> = []
    /// Aset asal atau tujuan.
    public var assetIDs: Set<UUID> = []
    public var minAmount: Decimal?
    public var maxAmount: Decimal?

    public init() {}

    /// Jumlah kelompok kriteria yang aktif (untuk badge): jenis, kategori, aset, nominal.
    public var activeCount: Int {
        [!types.isEmpty, !categoryIDs.isEmpty, !assetIDs.isEmpty, minAmount != nil || maxAmount != nil]
            .filter { $0 }.count
    }

    public var isActive: Bool { activeCount > 0 }

    public func matches(_ tx: MoneyTransaction) -> Bool {
        if !types.isEmpty, !types.contains(tx.type) { return false }
        if !categoryIDs.isEmpty {
            guard let category = tx.category else { return false }
            guard categoryIDs.contains(category.id) || category.parent.map({ categoryIDs.contains($0.id) }) == true
            else { return false }
        }
        if !assetIDs.isEmpty {
            let ids = [tx.asset?.id, tx.toAsset?.id].compactMap { $0 }
            guard ids.contains(where: assetIDs.contains) else { return false }
        }
        if let minAmount, tx.amount < minAmount { return false }
        if let maxAmount, tx.amount > maxAmount { return false }
        return true
    }

    public func apply(_ txs: [MoneyTransaction]) -> [MoneyTransaction] {
        isActive ? txs.filter(matches) : txs
    }
}

/// Pencarian teks bebas di catatan dan deskripsi.
public enum TransactionSearch {
    /// Semua kata pada `query` harus muncul (tanpa membedakan huruf besar/kecil dan aksen) di catatan atau deskripsi.
    /// Query kosong menghasilkan daftar kosong.
    public static func search(_ txs: [MoneyTransaction], query: String) -> [MoneyTransaction] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        return txs.filter { tx in
            let text = tx.note + "\n" + tx.detail
            return words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}
