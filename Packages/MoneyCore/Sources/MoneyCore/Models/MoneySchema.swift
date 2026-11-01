import Foundation
import SwiftData

public enum MoneySchema {
    public static let models: [any PersistentModel.Type] = [
        Profile.self, AssetAccount.self, Category.self, MoneyTransaction.self,
    ]

    /// `inMemory: false` memakai `cloudKitDatabase: .none` untuk sementara; Rencana 3 mengaktifkan `.automatic`.
    @MainActor
    public static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
