import Foundation
import SwiftData

public enum ProfileServiceError: Error, Equatable {
    case lastProfile, emptyName
}

/// Creates, edits, reorders and deletes profiles, keeping each profile's data isolated by `profileID`.
@MainActor
public struct ProfileService {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Ensures at least one profile exists ("Pribadi") and that `store` points at a valid active profile.
    @discardableResult
    public func bootstrap(store: ProfileStore) throws -> Profile {
        var all = try profiles()
        if all.isEmpty {
            _ = try createProfile(name: "Pribadi", emoji: "🙂", colorHex: "#FF6B5A", copyCategoriesFrom: nil)
            all = try profiles()
        }
        let active: Profile
        if let activeID = store.activeProfileID, let current = all.first(where: { $0.id == activeID }) {
            active = current
        } else {
            active = all[0]
            store.switchTo(active.id)
        }
        clearDanglingPrevious(in: store, validIDs: Set(all.map(\.id)))
        return active
    }

    public func profiles() throws -> [Profile] {
        try context.fetch(FetchDescriptor<Profile>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]))
    }

    public func createProfile(
        name: String, emoji: String, colorHex: String, copyCategoriesFrom: UUID?
    ) throws -> Profile {
        let trimmed = try validatedName(name)
        let nextOrder = (try profiles().map(\.sortOrder).max() ?? -1) + 1
        let profile = Profile(name: trimmed, emoji: emoji, colorHex: colorHex)
        profile.sortOrder = nextOrder
        context.insert(profile)

        if let source = copyCategoriesFrom {
            try copyCategories(from: source, to: profile.id)
        } else {
            seedDefaultCategories(for: profile.id)
        }
        context.insert(AssetAccount(profileID: profile.id, name: "Tunai", group: .cash, initialBalance: 0))
        try context.save()
        return profile
    }

    /// Deletes the profile and all of its transactions, assets and categories.
    public func deleteProfile(_ id: UUID, store: ProfileStore) throws {
        let all = try profiles()
        guard let target = all.first(where: { $0.id == id }) else { return }
        guard all.count > 1 else { throw ProfileServiceError.lastProfile }
        let fallback = all.first { $0.id != id }?.id

        for tx in try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.profileID == id })) {
            context.delete(tx)
        }
        for asset in try context.fetch(FetchDescriptor<AssetAccount>(predicate: #Predicate { $0.profileID == id })) {
            context.delete(asset)
        }
        for category in try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.profileID == id })) {
            context.delete(category)
        }
        context.delete(target)
        try context.save()
        store.handleDeleted(id, fallback: fallback)
    }

    public func update(_ profile: Profile, name: String, emoji: String, colorHex: String) throws {
        let trimmed = try validatedName(name)
        profile.name = trimmed
        profile.emoji = emoji
        profile.colorHex = colorHex
        try context.save()
    }

    /// Reorders profiles like `Array.move(fromOffsets:toOffset:)` and rewrites `sortOrder` as 0...n-1.
    public func move(from source: IndexSet, to destination: Int) throws {
        var ordered = try profiles()
        let moving = source.sorted().map { ordered[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { ordered.remove(at: index) }
        ordered.insert(contentsOf: moving, at: insertAt)
        for (index, profile) in ordered.enumerated() {
            profile.sortOrder = index
        }
        try context.save()
    }

    // MARK: - Private

    private func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProfileServiceError.emptyName }
        return trimmed
    }

    /// Clears a previous-profile pointer to a deleted profile. The active profile is valid at this point,
    /// so `handleDeleted` only touches `previousProfileID`.
    private func clearDanglingPrevious(in store: ProfileStore, validIDs: Set<UUID>) {
        if let previous = store.previousProfileID, !validIDs.contains(previous) {
            store.handleDeleted(previous, fallback: nil)
        }
    }

    private func seedDefaultCategories(for profileID: UUID) {
        for (index, item) in DefaultCatalog.expense.enumerated() {
            let category = Category(profileID: profileID, name: item.name, kind: .expense, emoji: item.emoji)
            category.sortOrder = index
            context.insert(category)
        }
        for (index, item) in DefaultCatalog.income.enumerated() {
            let category = Category(profileID: profileID, name: item.name, kind: .income, emoji: item.emoji)
            category.sortOrder = index
            context.insert(category)
        }
    }

    private func copyCategories(from sourceID: UUID, to targetID: UUID) throws {
        let originals = try context.fetch(
            FetchDescriptor<Category>(predicate: #Predicate { $0.profileID == sourceID }))
        var copies: [UUID: Category] = [:]
        for original in originals {
            let copy = Category(profileID: targetID, name: original.name, kind: original.kind, emoji: original.emoji)
            copy.isHidden = original.isHidden
            copy.sortOrder = original.sortOrder
            context.insert(copy)
            copies[original.id] = copy
        }
        for original in originals {
            if let parentID = original.parent?.id {
                copies[original.id]?.parent = copies[parentID]
            }
        }
    }
}
