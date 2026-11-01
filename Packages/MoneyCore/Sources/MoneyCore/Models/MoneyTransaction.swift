import Foundation
import SwiftData

public enum TransactionType: String, CaseIterable, Sendable {
    case income, expense, transfer, adjustment
}

/// Catatan: `category` boleh menunjuk ke subkategori; kategori induk = `category?.parent ?? category`.
@Model
public final class MoneyTransaction {
    public var id: UUID = UUID()
    public var profileID: UUID = UUID()
    public var typeRaw: String = TransactionType.expense.rawValue
    public var amountMinor: Int64 = 0
    public var feeMinor: Int64 = 0
    public var date: Date = Date.now
    public var category: Category?
    public var asset: AssetAccount?
    public var toAsset: AssetAccount?
    public var note: String = ""
    public var detail: String = ""
    public var recurringRuleID: UUID?
    public var occurrenceKey: String?
    public var importBatchID: UUID?
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    public var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    public var amount: Decimal {
        get { Decimal(minorUnits: amountMinor) }
        set { amountMinor = newValue.minorUnits }
    }

    public var fee: Decimal {
        get { Decimal(minorUnits: feeMinor) }
        set { feeMinor = newValue.minorUnits }
    }

    public init(profileID: UUID, type: TransactionType, amount: Decimal, date: Date) {
        self.profileID = profileID
        self.typeRaw = type.rawValue
        self.amountMinor = amount.minorUnits
        self.date = date
    }
}
