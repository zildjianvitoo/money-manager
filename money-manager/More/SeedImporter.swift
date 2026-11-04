#if DEBUG
import Foundation
import SwiftData
import MoneyCore

/// One-off import of history from the old Money Manager app into one profile.
/// Reads `<profile>-seed.json` files from `money-manager/DebugSeed/`, cleaned exports kept out of git
/// (see .gitignore); with no such file the importer is unavailable. Debug builds only.
@MainActor
enum SeedImporter {
    struct Seed: Decodable {
        struct Asset: Decodable { let key: String; let name: String; let group: String; let initialBalance: String }
        struct Category: Decodable { let key: String; let name: String; let kind: String; let emoji: String; let parent: String? }
        struct Entry: Decodable {
            let type: String; let category: String; let asset: String; let amount: String; let date: String; let note: String
        }
        let profile: String
        let assets: [Asset]
        let categories: [Category]
        let transactions: [Entry]
    }

    enum ImportError: LocalizedError {
        case alreadyImported(String), invalidEntry(String)

        var errorDescription: String? {
            switch self {
            case .alreadyImported(let name): "Profil \(name) sudah punya transaksi, jadi impor dibatalkan supaya tidak dobel."
            case .invalidEntry(let detail): "Data tidak valid: \(detail)"
            }
        }
    }

    /// Seed files bundled in this build, keyed by target profile name.
    static var available: [(profile: String, url: URL)] {
        (Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasSuffix("-seed.json") }
            .compactMap { url in
                guard let seed = try? JSONDecoder().decode(Seed.self, from: Data(contentsOf: url)) else { return nil }
                return (seed.profile, url)
            }
            .sorted { $0.profile < $1.profile }
    }

    /// Creates (or reuses) the seed's profile and fills it. Returns the profile and the number of transactions.
    static func run(_ url: URL, context: ModelContext) throws -> (profile: Profile, count: Int) {
        let seed = try JSONDecoder().decode(Seed.self, from: Data(contentsOf: url))

        // Parse everything before writing anything, so a bad row never leaves a half-filled profile.
        let assetKeys = Set(seed.assets.map(\.key))
        let categoryKeys = Set(seed.categories.map(\.key))
        let rows: [(type: TransactionType, date: Date, amount: Decimal, category: String, asset: String, note: String)] =
            try seed.transactions.map { entry in
                guard let date = ISO8601DateFormatter().date(from: entry.date),
                      let amount = decimal(entry.amount),
                      categoryKeys.contains(entry.category), assetKeys.contains(entry.asset),
                      let type: TransactionType = entry.type == "income" ? .income : entry.type == "expense" ? .expense : nil
                else { throw ImportError.invalidEntry("\(entry.date) \(entry.note)") }
                return (type, date, amount, entry.category, entry.asset, entry.note)
            }
        let assetSpecs: [(spec: Seed.Asset, group: AssetGroup, opening: Decimal)] = try seed.assets.map { spec in
            guard let group = AssetGroup(rawValue: spec.group), let opening = decimal(spec.initialBalance)
            else { throw ImportError.invalidEntry("aset \(spec.name)") }
            return (spec, group, opening)
        }

        let profiles = ProfileService(context: context)
        let profile = try profiles.profiles().first { $0.name.localizedCaseInsensitiveCompare(seed.profile) == .orderedSame }
            ?? profiles.createProfile(
                name: seed.profile, emoji: "🙂", colorHex: "#FF6B5A",
                kind: seed.profile.localizedCaseInsensitiveCompare(ProfileKind.business.displayName) == .orderedSame ? .business : .personal,
                copyCategoriesFrom: nil
            )
        let pid = profile.id
        guard try context.fetchCount(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.profileID == pid })) == 0
        else { throw ImportError.alreadyImported(profile.name) }

        // Categories and assets are matched by name, so the profile's defaults are reused instead of duplicated.
        let categoryService = CategoryService(context: context, profileID: pid)
        var categories: [String: MoneyCategory] = [:]
        for spec in seed.categories.sorted(by: { ($0.parent == nil ? 0 : 1) < ($1.parent == nil ? 0 : 1) }) {
            let kind: CategoryKind = spec.kind == "income" ? .income : .expense
            let parent = spec.parent.flatMap { categories[$0] }
            let siblings = try parent.map { $0.children ?? [] } ?? categoryService.topLevel(kind: kind, includeHidden: true)
            categories[spec.key] = try siblings.first { $0.name.localizedCaseInsensitiveCompare(spec.name) == .orderedSame }
                ?? categoryService.create(name: spec.name, emoji: spec.emoji, kind: kind, parent: parent)
        }

        let assetService = AssetService(context: context, profileID: pid)
        let existingAssets = try assetService.assets(includeArchived: true)
        var assets: [String: AssetAccount] = [:]
        for (spec, group, opening) in assetSpecs {
            assets[spec.key] = try existingAssets.first { $0.name.localizedCaseInsensitiveCompare(spec.name) == .orderedSame }
                ?? assetService.create(name: spec.name, group: group, initialBalance: opening)
        }

        let service = TransactionService(context: context, profileID: pid)
        for row in rows {
            var draft = TransactionDraft(type: row.type, date: row.date)
            draft.amount = row.amount
            draft.categoryID = categories[row.category]?.id
            draft.assetID = assets[row.asset]?.id
            draft.note = row.note
            try service.create(draft)
        }
        return (profile, rows.count)
    }

    private static func decimal(_ string: String) -> Decimal? {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
    }
}
#endif
