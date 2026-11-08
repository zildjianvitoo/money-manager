import Foundation
import SwiftData

/// Satu kali import. Menyimpan id kategori dan aset yang dibuat batch ini (dipisah koma, supaya aman untuk CloudKit)
/// agar undo bisa menghapusnya kembali bila tidak dipakai lagi.
@Model
public final class ImportBatch {
    public var id: UUID = UUID()
    public var profileID: UUID = UUID()
    public var fileName: String = ""
    public var importedAt: Date = Date.now
    public var rowCount: Int = 0
    public var skippedCount: Int = 0
    public var createdCategoryIDsRaw: String = ""
    public var createdAssetIDsRaw: String = ""

    public var createdCategoryIDs: [UUID] {
        get { createdCategoryIDsRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
        set { createdCategoryIDsRaw = newValue.map(\.uuidString).joined(separator: ",") }
    }

    public var createdAssetIDs: [UUID] {
        get { createdAssetIDsRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
        set { createdAssetIDsRaw = newValue.map(\.uuidString).joined(separator: ",") }
    }

    public init(profileID: UUID, fileName: String) {
        self.profileID = profileID
        self.fileName = fileName
    }
}
