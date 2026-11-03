#if DEBUG
import Foundation
import SwiftData
import MoneyCore

/// One-off import of the business's history from the old Money Manager app into the "Bisnis" profile.
/// Reads `bisnis-seed.json`, a cleaned export kept out of git (`money-manager/DebugSeed/`, see .gitignore);
/// without that file the importer is unavailable. Debug builds only.
@MainActor
enum BusinessSeedImporter {
    struct Seed: Decodable {
        struct Wallet: Decodable { let name: String; let initialBalance: String }
        struct Entry: Decodable { let type: String; let category: String; let amount: String; let date: String; let note: String }
        let wallet: Wallet
        let transactions: [Entry]
    }

    enum ImportError: LocalizedError {
        case missingSeed, alreadyImported, invalidEntry(String)

        var errorDescription: String? {
            switch self {
            case .missingSeed: "File bisnis-seed.json tidak ada di build ini."
            case .alreadyImported: "Profil Bisnis sudah punya transaksi, jadi impor dibatalkan supaya tidak dobel."
            case .invalidEntry(let detail): "Data tidak valid: \(detail)"
            }
        }
    }

    private static var seedURL: URL? {
        Bundle.main.url(forResource: "bisnis-seed", withExtension: "json")
    }

    static var isAvailable: Bool { seedURL != nil }

    /// Creates (or reuses) the "Bisnis" profile and fills it. Returns the profile and the number of transactions.
    static func run(context: ModelContext) throws -> (profile: Profile, count: Int) {
        guard let url = seedURL else { throw ImportError.missingSeed }
        let seed = try JSONDecoder().decode(Seed.self, from: Data(contentsOf: url))

        // Parse everything before writing anything, so a bad row never leaves a half-filled profile.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let validKeys: Set = ["usaha", "tagihan", "gajiTim", "lainnya"]
        let rows: [(type: TransactionType, date: Date, amount: Decimal, key: String, note: String)] = try seed.transactions.map { entry in
            guard let date = formatter.date(from: entry.date),
                  let amount = decimal(entry.amount),
                  validKeys.contains(entry.category),
                  let type: TransactionType = entry.type == "income" ? .income : entry.type == "expense" ? .expense : nil
            else { throw ImportError.invalidEntry("\(entry.date) \(entry.note)") }
            return (type, date, amount, entry.category, entry.note)
        }
        guard let opening = decimal(seed.wallet.initialBalance) else { throw ImportError.invalidEntry("saldo awal") }

        let profiles = ProfileService(context: context)
        let profile = try profiles.profiles().first { $0.name.localizedCaseInsensitiveCompare("Bisnis") == .orderedSame }
            ?? profiles.createProfile(name: "Bisnis", emoji: "💼", colorHex: "#0A84FF", copyCategoriesFrom: nil)
        let pid = profile.id
        guard try context.fetchCount(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.profileID == pid })) == 0
        else { throw ImportError.alreadyImported }

        // Old categories mapped to Indonesian ones; the two expense ones are created when missing.
        let categories = CategoryService(context: context, profileID: pid)
        func category(_ name: String, _ kind: CategoryKind, emoji: String) throws -> MoneyCategory {
            if let existing = try categories.topLevel(kind: kind, includeHidden: true).first(where: { $0.name == name }) {
                return existing
            }
            return try categories.create(name: name, emoji: emoji, kind: kind, parent: nil)
        }
        let byKey: [String: MoneyCategory] = [
            "usaha": try category("Usaha", .income, emoji: "🏪"),
            "tagihan": try category("Tagihan & Langganan", .expense, emoji: "🧾"),
            "gajiTim": try category("Gaji Tim", .expense, emoji: "👥"),
            "lainnya": try category("Lainnya", .expense, emoji: "📦"),
        ]

        let assets = AssetService(context: context, profileID: pid)
        let asset = try assets.create(name: seed.wallet.name, group: .cash, initialBalance: opening)
        // The default empty "Tunai" of a new profile is unused here; archive it to keep the list clean.
        for unused in try assets.assets(includeArchived: false)
        where unused.id != asset.id && unused.name == "Tunai" && unused.initialBalance == 0 {
            try assets.setArchived(unused, true)
        }

        let service = TransactionService(context: context, profileID: pid)
        for row in rows {
            var draft = TransactionDraft(type: row.type, date: row.date)
            draft.amount = row.amount
            draft.categoryID = byKey[row.key]?.id
            draft.assetID = asset.id
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
