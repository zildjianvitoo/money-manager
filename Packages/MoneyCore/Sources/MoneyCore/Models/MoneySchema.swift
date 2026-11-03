import Foundation
import SwiftData

public enum MoneySchema {
    public static let models: [any PersistentModel.Type] = [
        Profile.self, AssetAccount.self, MoneyCategory.self, MoneyTransaction.self,
    ]

    /// `inMemory: false` memakai `cloudKitDatabase: .automatic`: sinkron iCloud bila entitlement ada, tetap lokal bila tidak.
    @MainActor
    public static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: inMemory ? .none : .automatic
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
