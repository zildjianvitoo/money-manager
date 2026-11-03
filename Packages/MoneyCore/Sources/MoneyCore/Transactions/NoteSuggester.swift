import Foundation
import SwiftData

/// Saran isi kolom "Catatan" dari catatan transaksi 180 hari terakhir milik satu profil.
@MainActor
public struct NoteSuggester {
    private static let windowDays = 180

    private let context: ModelContext
    private let profileID: UUID

    public init(context: ModelContext, profileID: UUID) {
        self.context = context
        self.profileID = profileID
    }

    /// Catatan unik yang diawali `prefix` (tak peka huruf besar/kecil dan diakritik).
    /// Urutan: frekuensi menurun, lalu tanggal terbaru, lalu abjad. Ejaan yang dikembalikan
    /// adalah ejaan terbaru. `categoryID` mencocokkan `category?.id` transaksi secara persis.
    public func suggestions(
        prefix: String, categoryID: UUID?, limit: Int = 5, now: Date = .now
    ) throws -> [String] {
        guard limit > 0 else { return [] }

        let profileID = self.profileID
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.windowDays, to: now)
            ?? now.addingTimeInterval(-Double(Self.windowDays) * 86_400)
        let descriptor = FetchDescriptor<MoneyTransaction>(
            predicate: #Predicate { $0.profileID == profileID && $0.date >= cutoff },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        let needle = Self.fold(String(prefix.drop(while: \.isWhitespace)))

        struct Entry {
            var text: String // ejaan terbaru
            var count: Int
            var latest: Date
        }
        var entries: [String: Entry] = [:]

        // Hasil fetch terbaru di atas, jadi kemunculan pertama = ejaan terbaru.
        for transaction in try context.fetch(descriptor) {
            if let categoryID, transaction.category?.id != categoryID { continue }
            let text = transaction.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let key = Self.fold(text)
            guard key.hasPrefix(needle) else { continue }
            if var entry = entries[key] {
                entry.count += 1
                entries[key] = entry
            } else {
                entries[key] = Entry(text: text, count: 1, latest: transaction.date)
            }
        }

        return entries.values
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                if $0.latest != $1.latest { return $0.latest > $1.latest }
                return $0.text.localizedStandardCompare($1.text) == .orderedAscending
            }
            .prefix(limit)
            .map(\.text)
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
