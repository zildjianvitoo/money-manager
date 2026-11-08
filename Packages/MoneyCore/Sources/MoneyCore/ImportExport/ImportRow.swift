import Foundation

/// Satu baris transaksi hasil baca file, belum terikat ke kategori/aset di database.
public struct ImportRow: Equatable, Sendable {
    public var type: TransactionType
    public var date: Date
    public var amount: Decimal
    public var fee: Decimal
    public var categoryName: String
    public var subcategoryName: String
    public var assetName: String
    public var toAssetName: String
    public var note: String
    public var detail: String

    public init(
        type: TransactionType, date: Date, amount: Decimal, fee: Decimal = 0,
        categoryName: String = "", subcategoryName: String = "",
        assetName: String, toAssetName: String = "", note: String = "", detail: String = ""
    ) {
        self.type = type
        self.date = date
        self.amount = amount
        self.fee = fee
        self.categoryName = categoryName
        self.subcategoryName = subcategoryName
        self.assetName = assetName
        self.toAssetName = toAssetName
        self.note = note
        self.detail = detail
    }
}

/// Informasi aset dari file sumber. `currentBalance` ada bila file memuat saldo sekarang (JSON backup).
public struct ImportAssetSpec: Equatable, Sendable {
    public var name: String
    public var group: AssetGroup
    public var currentBalance: Decimal?

    public init(name: String, group: AssetGroup, currentBalance: Decimal?) {
        self.name = name
        self.group = group
        self.currentBalance = currentBalance
    }
}

public struct ImportFailure: Equatable, Sendable {
    /// Nomor baris (CSV: baris file, 1 = header) atau urutan transaksi (JSON, mulai 1).
    public let line: Int
    public let reason: String

    public init(line: Int, reason: String) {
        self.line = line
        self.reason = reason
    }
}

public struct ImportParseResult: Equatable, Sendable {
    public var rows: [ImportRow]
    public var failures: [ImportFailure]
    public var assets: [ImportAssetSpec]

    public init(rows: [ImportRow] = [], failures: [ImportFailure] = [], assets: [ImportAssetSpec] = []) {
        self.rows = rows
        self.failures = failures
        self.assets = assets
    }
}

public enum ImportParseError: Error, Equatable, LocalizedError {
    case notReadable
    case unrecognizedFormat
    case missingColumns([String])

    public var errorDescription: String? {
        switch self {
        case .notReadable: "File tidak bisa dibaca."
        case .unrecognizedFormat: "Format file tidak dikenali. Gunakan backup JSON Money Manager atau CSV."
        case .missingColumns(let names): "Kolom wajib tidak ditemukan: \(names.joined(separator: ", "))."
        }
    }
}

/// Mem-parse angka dari berbagai format: `19000`, `19.000`, `19.000,50`, `19,000.50`, `Rp 19.000`.
public enum FlexibleNumber {
    public static func parse(_ raw: String) -> Decimal? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "Rp", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        guard !s.isEmpty else { return nil }
        var negative = false
        if s.hasPrefix("-") { negative = true; s.removeFirst() } else if s.hasPrefix("+") { s.removeFirst() }
        guard !s.isEmpty, s.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }), s.first!.isNumber else { return nil }

        let dots = s.filter { $0 == "." }.count
        let commas = s.filter { $0 == "," }.count
        var decimalSeparator: Character?
        if dots > 0 && commas > 0 {
            decimalSeparator = s.lastIndex(of: ".")! > s.lastIndex(of: ",")! ? "." : ","
        } else if dots + commas > 0 {
            let sep: Character = dots > 0 ? "." : ","
            if dots + commas == 1 {
                let afterCount = s.distance(from: s.firstIndex(of: sep)!, to: s.endIndex) - 1
                decimalSeparator = afterCount == 3 ? nil : sep
            }
        }
        var normalized = ""
        for ch in s {
            if ch.isNumber { normalized.append(ch) } else if ch == decimalSeparator { normalized.append(".") }
        }
        guard var value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        if negative { value = -value }
        return value
    }
}
