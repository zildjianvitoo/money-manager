import Foundation

/// Membaca file backup JSON Money Manager (`appName: "Money Manager"`).
/// `transactionType`: 0 = pendapatan, 1 = pengeluaran. Tipe lain dilaporkan sebagai baris gagal.
public enum BackupJSONParser {
    private struct Backup: Decodable {
        struct Currency: Decodable { let code: String? }
        struct Category: Decodable {
            let id: String
            let name: String
            let parentCategoryId: String?
        }
        struct Wallet: Decodable {
            let id: String
            let name: String
            let balance: Double?
            let walletType: String?
        }
        struct Transaction: Decodable {
            let transactionType: Int
            let category: Category?
            let wallet: Wallet?
            let amount: Double
            let date: String
            let notes: String?
            let detail: String?
        }
        let transactions: [Transaction]
        let categories: [Category]?
        let wallets: [Wallet]?
    }

    public static func parse(_ data: Data, timeZone: TimeZone = .current) throws -> ImportParseResult {
        guard let backup = try? JSONDecoder().decode(Backup.self, from: data) else {
            throw ImportParseError.unrecognizedFormat
        }
        let parents = Dictionary(
            (backup.categories ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )

        var result = ImportParseResult()
        for (index, tx) in backup.transactions.enumerated() {
            let line = index + 1
            let type: TransactionType
            switch tx.transactionType {
            case 0: type = .income
            case 1: type = .expense
            default:
                result.failures.append(.init(line: line, reason: "Jenis transaksi \(tx.transactionType) (mis. transfer) belum didukung."))
                continue
            }
            guard let date = parseDate(tx.date, timeZone: timeZone) else {
                result.failures.append(.init(line: line, reason: "Tanggal tidak terbaca: \(tx.date)"))
                continue
            }
            guard let amount = decimal(tx.amount), amount > 0 else {
                result.failures.append(.init(line: line, reason: "Nominal harus lebih dari nol."))
                continue
            }
            guard let wallet = tx.wallet, !wallet.name.trimmed.isEmpty else {
                result.failures.append(.init(line: line, reason: "Aset tidak ada."))
                continue
            }
            guard let category = tx.category, !category.name.trimmed.isEmpty else {
                result.failures.append(.init(line: line, reason: "Kategori tidak ada."))
                continue
            }
            var categoryName = category.name.trimmed
            var subcategoryName = ""
            if let parentID = category.parentCategoryId, let parent = parents[parentID] {
                subcategoryName = categoryName
                categoryName = parent.name.trimmed
            }
            result.rows.append(ImportRow(
                type: type, date: date, amount: amount,
                categoryName: categoryName, subcategoryName: subcategoryName,
                assetName: wallet.name.trimmed,
                note: (tx.notes ?? "").trimmed, detail: (tx.detail ?? "").trimmed
            ))
        }

        var wallets = backup.wallets ?? []
        for tx in backup.transactions {
            if let wallet = tx.wallet, !wallets.contains(where: { $0.name == wallet.name }) { wallets.append(wallet) }
        }
        result.assets = wallets.map {
            ImportAssetSpec(name: $0.name.trimmed, group: group(for: $0.walletType), currentBalance: $0.balance.flatMap(decimal))
        }
        return result
    }

    static func decimal(_ value: Double) -> Decimal? {
        guard value.isFinite, abs(value) < 1e15 else { return nil }
        guard let exact = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var rounded = Decimal()
        var source = exact
        NSDecimalRound(&rounded, &source, 2, .plain)
        return rounded
    }

    static func group(for raw: String?) -> AssetGroup {
        switch (raw ?? "").lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "") {
        case "cash": .cash
        case "bank", "bankaccount": .bank
        case "ewallet", "wallet": .eWallet
        case "creditcard", "credit": .creditCard
        case "investment": .investment
        default: .other
        }
    }

    static func parseDate(_ raw: String, timeZone: TimeZone) -> Date? {
        let text = raw.trimmed
        if text.hasSuffix("Z") || text.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: text) { return date }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: text)
        }
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            if let date = formatter(format, timeZone).date(from: text) { return date }
        }
        return nil
    }

    static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = format
        return f
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
