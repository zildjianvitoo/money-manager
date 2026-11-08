import Foundation
import SwiftData

/// Template transaksi. Kategori dan aset disimpan sebagai id (bukan relasi) supaya template tetap sah
/// walau kategori/asetnya dihapus; id yang tidak ditemukan diperlakukan sebagai kosong.
@Model
public final class FavoriteTemplate {
    public var id: UUID = UUID()
    public var profileID: UUID = UUID()
    public var name: String = ""
    public var typeRaw: String = TransactionType.expense.rawValue
    public var categoryID: UUID?
    public var assetID: UUID?
    public var toAssetID: UUID?
    public var note: String = ""
    /// 0 = nominal tidak disimpan.
    public var amountMinor: Int64 = 0
    public var sortOrder: Int = 0
    public var createdAt: Date = Date.now

    public var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    public var amount: Decimal? {
        get { amountMinor > 0 ? Decimal(minorUnits: amountMinor) : nil }
        set { amountMinor = newValue?.minorUnits ?? 0 }
    }

    public init(profileID: UUID, name: String, type: TransactionType) {
        self.profileID = profileID
        self.name = name
        self.typeRaw = type.rawValue
    }
}
