import Foundation
import SwiftData

@Model
public final class Profile {
    public var id: UUID = UUID()
    public var name: String = ""
    public var emoji: String = "🙂"
    public var colorHex: String = "#FF6B5A"
    public var sortOrder: Int = 0
    public var createdAt: Date = Date.now

    public init(name: String, emoji: String = "🙂", colorHex: String = "#FF6B5A") {
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
    }
}
