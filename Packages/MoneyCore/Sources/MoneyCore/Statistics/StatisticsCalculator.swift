import Foundation

public struct CategoryShare: Identifiable, Equatable {
    /// nil = "Tanpa kategori"; `StatisticsCalculator.transferFeeID` = "Biaya transfer".
    public let id: UUID?
    public let name: String
    public let emoji: String
    public let amount: Decimal
    /// 0...1
    public let fraction: Double

    public init(id: UUID?, name: String, emoji: String, amount: Decimal, fraction: Double) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.amount = amount
        self.fraction = fraction
    }
}

public struct TrendPoint: Identifiable, Equatable {
    /// Awal bulan pada kalender yang diberikan.
    public let id: Date
    public let amount: Decimal

    public init(id: Date, amount: Decimal) {
        self.id = id
        self.amount = amount
    }
}

/// Aturan hitung sama dengan `TransactionSummary`: income = `.income`; expense = `.expense` + fee `.transfer`.
public enum StatisticsCalculator {
    public static let transferFeeID = UUID(uuidString: "00000000-0000-0000-0000-00000000FEE0")!

    private static let feeName = "Biaya transfer"
    private static let feeEmoji = "💸"
    private static let uncategorizedName = "Tanpa kategori"
    private static let uncategorizedEmoji = "❓"

    /// Per kategori induk (subkategori dihitung ke induknya), besar ke kecil.
    public static func breakdown(_ txs: [MoneyTransaction], kind: CategoryKind) -> [CategoryShare] {
        shares(entries(txs, kind: kind)) { entry in
            (entry.shareID, entry.topName, entry.topEmoji)
        }
    }

    public static func total(_ txs: [MoneyTransaction], kind: CategoryKind) -> Decimal {
        entries(txs, kind: kind).reduce(0) { $0 + $1.amount }
    }

    /// Transaksi langsung di induk = baris induk itu sendiri.
    public static func subcategoryBreakdown(
        _ txs: [MoneyTransaction], parentID: UUID?, kind: CategoryKind
    ) -> [CategoryShare] {
        let selected = entries(txs, kind: kind).filter { $0.shareID == parentID }
        return shares(selected) { entry in
            if let sub = entry.subcategory { return (sub.id, sub.name, sub.emoji) }
            return (entry.shareID, entry.topName, entry.topEmoji)
        }
    }

    /// Terbaru di atas.
    public static func transactions(_ txs: [MoneyTransaction], shareID: UUID?, kind: CategoryKind) -> [MoneyTransaction] {
        var seen = Set<UUID>()
        return entries(txs, kind: kind)
            .filter { $0.shareID == shareID }
            .map(\.tx)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.createdAt > $1.createdAt }
    }

    /// Selalu `months` titik, bulan terlama dulu; titik terakhir = bulan `endingAt`. `shareID` nil = "Tanpa kategori".
    public static func trend(
        _ txs: [MoneyTransaction], shareID: UUID?, kind: CategoryKind,
        months: Int, endingAt: Date, calendar: Calendar
    ) -> [TrendPoint] {
        let lastStart = TransactionQueries.monthInterval(containing: endingAt, calendar: calendar).start
        let selected = entries(txs, kind: kind).filter { $0.shareID == shareID }
        return (0..<max(months, 0)).map { index in
            let start = calendar.date(byAdding: .month, value: index - (months - 1), to: lastStart) ?? lastStart
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let sum = selected.filter { $0.tx.date >= start && $0.tx.date < end }.reduce(Decimal(0)) { $0 + $1.amount }
            return TrendPoint(id: start, amount: sum)
        }
    }

    // MARK: - Private

    private struct Entry {
        let tx: MoneyTransaction
        let shareID: UUID?
        let topName: String
        let topEmoji: String
        /// Subkategori bila transaksi dicatat di subkategori.
        let subcategory: MoneyCategory?
        let amount: Decimal
    }

    private static func entries(_ txs: [MoneyTransaction], kind: CategoryKind) -> [Entry] {
        var result: [Entry] = []
        for tx in txs {
            switch (tx.type, kind) {
            case (.income, .income), (.expense, .expense):
                let category = tx.category
                let top = category?.parent ?? category
                result.append(Entry(
                    tx: tx,
                    shareID: top?.id,
                    topName: top?.name ?? uncategorizedName,
                    topEmoji: top?.emoji ?? uncategorizedEmoji,
                    subcategory: category?.parent == nil ? nil : category,
                    amount: tx.amount
                ))
            case (.transfer, .expense) where tx.fee > 0:
                result.append(Entry(
                    tx: tx, shareID: transferFeeID, topName: feeName, topEmoji: feeEmoji,
                    subcategory: nil, amount: tx.fee
                ))
            default:
                break
            }
        }
        return result
    }

    private static func shares(
        _ entries: [Entry], key: (Entry) -> (id: UUID?, name: String, emoji: String)
    ) -> [CategoryShare] {
        var order: [UUID?] = []
        var rows: [UUID?: (name: String, emoji: String, amount: Decimal)] = [:]
        for entry in entries {
            let k = key(entry)
            if rows[k.id] == nil {
                order.append(k.id)
                rows[k.id] = (k.name, k.emoji, 0)
            }
            rows[k.id]!.amount += entry.amount
        }
        let total = rows.values.reduce(Decimal(0)) { $0 + $1.amount }
        guard total > 0 else { return [] }
        return order
            .map { id in
                let row = rows[id]!
                let fraction = NSDecimalNumber(decimal: row.amount / total).doubleValue
                return CategoryShare(id: id, name: row.name, emoji: row.emoji, amount: row.amount, fraction: fraction)
            }
            .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.name < $1.name }
    }
}
