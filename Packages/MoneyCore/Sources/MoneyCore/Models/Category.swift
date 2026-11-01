import Foundation
import SwiftData

public enum CategoryKind: String, CaseIterable, Sendable {
    case income, expense
}

@Model
public final class Category {
    public var id: UUID = UUID()
    public var profileID: UUID = UUID()
    public var name: String = ""
    public var emoji: String = ""
    public var kindRaw: String = CategoryKind.expense.rawValue
    public var isHidden: Bool = false
    public var sortOrder: Int = 0

    public var parent: Category?
    @Relationship(deleteRule: .cascade, inverse: \Category.parent)
    public var children: [Category]? = []
    @Relationship(inverse: \MoneyTransaction.category)
    public var transactions: [MoneyTransaction]? = []

    public var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    public init(profileID: UUID, name: String, kind: CategoryKind, emoji: String = "", parent: Category? = nil) {
        self.profileID = profileID
        self.name = name
        self.kindRaw = kind.rawValue
        self.emoji = emoji
        self.parent = parent
    }
}
