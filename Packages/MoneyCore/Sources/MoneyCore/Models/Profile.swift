import Foundation
import SwiftData

/// Decides which default categories a new profile starts with.
public enum ProfileKind: String, CaseIterable, Sendable {
    case personal, business

    public var displayName: String {
        switch self {
        case .personal: "Pribadi"
        case .business: "Bisnis"
        }
    }
}

@Model
public final class Profile {
    public var id: UUID = UUID()
    public var name: String = ""
    public var emoji: String = "🙂"
    public var colorHex: String = "#FF6B5A"
    public var sortOrder: Int = 0
    public var createdAt: Date = Date.now
    public var kindRaw: String = ProfileKind.personal.rawValue

    public var kind: ProfileKind {
        get { ProfileKind(rawValue: kindRaw) ?? .personal }
        set { kindRaw = newValue.rawValue }
    }

    public init(name: String, emoji: String = "🙂", colorHex: String = "#FF6B5A") {
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
    }
}
