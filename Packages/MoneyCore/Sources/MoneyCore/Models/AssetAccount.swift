import Foundation
import SwiftData

public enum AssetGroup: String, CaseIterable, Sendable {
    case cash, bank, eWallet, creditCard, investment, other

    public var displayName: String {
        switch self {
        case .cash: "Tunai"
        case .bank: "Bank"
        case .eWallet: "E-Wallet"
        case .creditCard: "Kartu Kredit"
        case .investment: "Investasi"
        case .other: "Lainnya"
        }
    }
}

@Model
public final class AssetAccount {
    public var id: UUID = UUID()
    public var profileID: UUID = UUID()
    public var name: String = ""
    public var groupRaw: String = AssetGroup.cash.rawValue
    public var initialBalanceMinor: Int64 = 0
    public var includeInTotal: Bool = true
    public var isArchived: Bool = false
    public var sortOrder: Int = 0

    @Relationship(inverse: \MoneyTransaction.asset)
    public var outgoing: [MoneyTransaction]? = []
    @Relationship(inverse: \MoneyTransaction.toAsset)
    public var incoming: [MoneyTransaction]? = []

    public var group: AssetGroup {
        get { AssetGroup(rawValue: groupRaw) ?? .other }
        set { groupRaw = newValue.rawValue }
    }

    public var initialBalance: Decimal {
        get { Decimal(minorUnits: initialBalanceMinor) }
        set { initialBalanceMinor = newValue.minorUnits }
    }

    public init(profileID: UUID, name: String, group: AssetGroup, initialBalance: Decimal = 0) {
        self.profileID = profileID
        self.name = name
        self.groupRaw = group.rawValue
        self.initialBalanceMinor = initialBalance.minorUnits
    }
}
