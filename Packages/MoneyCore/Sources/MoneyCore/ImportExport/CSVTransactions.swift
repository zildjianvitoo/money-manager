import Foundation

/// CSV transaksi dengan kolom ala Money Manager:
/// `Date, Account, Category, Subcategory, Note, Amount, Type, To Account, Fee, Description`.
/// Impor mencocokkan kolom lewat nama header (urutan bebas, beberapa alias dikenali).
public enum CSVTransactions {
    public static let header = ["Date", "Account", "Category", "Subcategory", "Note", "Amount", "Type", "To Account", "Fee", "Description"]

    // MARK: - Export

    /// Transaksi `.adjustment` (penyesuaian saldo) tidak diekspor. UTF-8 dengan BOM supaya Excel membaca emoji dengan benar.
    public static func export(_ transactions: [MoneyTransaction], timeZone: TimeZone = .current) -> Data {
        let formatter = BackupJSONParser.formatter("yyyy-MM-dd HH:mm:ss", timeZone)
        var lines = [header.joined(separator: ",")]
        for tx in transactions.sorted(by: { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }) where tx.type != .adjustment {
            let category = tx.category
            let top = category?.parent ?? category
            let sub = category?.parent == nil ? nil : category
            let type: String = switch tx.type {
            case .income: "Income"
            case .expense: "Expense"
            default: "Transfer"
            }
            let fields = [
                formatter.string(from: tx.date),
                tx.asset?.name ?? "",
                top?.name ?? "",
                sub?.name ?? "",
                tx.note,
                plain(tx.amount),
                type,
                tx.toAsset?.name ?? "",
                tx.type == .transfer ? plain(tx.fee) : "",
                tx.detail,
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return Data(("\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    private static func plain(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Import

    public static func parse(_ data: Data, timeZone: TimeZone = .current) throws -> ImportParseResult {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportParseError.notReadable
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let table = records(text)
        guard let headerRow = table.first else { throw ImportParseError.unrecognizedFormat }

        let names = headerRow.map { $0.trimmed.lowercased() }
        func column(_ aliases: [String]) -> Int? { names.firstIndex { aliases.contains($0) } }
        let dateCol = column(["date", "period", "tanggal"])
        let accountCol = column(["account", "accounts", "asset", "aset", "akun"])
        let categoryCol = column(["category", "kategori"])
        let subCol = column(["subcategory", "subkategori"])
        let noteCol = column(["note", "notes", "catatan"])
        let amountCol = column(["amount", "idr", "nominal", "jumlah"])
        let typeCol = column(["type", "income/expense", "jenis"])
        let toCol = column(["to account", "to", "ke akun"])
        let feeCol = column(["fee", "biaya"])
        let detailCol = column(["description", "detail", "deskripsi"])

        var missing: [String] = []
        if dateCol == nil { missing.append("Date") }
        if accountCol == nil { missing.append("Account") }
        if amountCol == nil { missing.append("Amount") }
        if typeCol == nil { missing.append("Type") }
        if !missing.isEmpty { throw ImportParseError.missingColumns(missing) }

        var result = ImportParseResult()
        var pendingOut: [(line: Int, row: ImportRow)] = []
        var pendingIn: [(line: Int, row: ImportRow)] = []

        for (offset, record) in table.dropFirst().enumerated() {
            let line = offset + 2
            if record.allSatisfy({ $0.trimmed.isEmpty }) { continue }
            func cell(_ col: Int?) -> String {
                guard let col, record.indices.contains(col) else { return "" }
                return record[col].trimmed
            }
            guard let date = parseDate(cell(dateCol), timeZone: timeZone) else {
                result.failures.append(.init(line: line, reason: "Tanggal tidak terbaca: \(cell(dateCol))")); continue
            }
            guard let amount = FlexibleNumber.parse(cell(amountCol)), amount > 0 else {
                result.failures.append(.init(line: line, reason: "Nominal tidak valid: \(cell(amountCol))")); continue
            }
            let account = cell(accountCol)
            guard !account.isEmpty else {
                result.failures.append(.init(line: line, reason: "Aset kosong.")); continue
            }
            let category = cell(categoryCol)
            let sub = cell(subCol)
            let typeText = cell(typeCol).lowercased().replacingOccurrences(of: " ", with: "")
            let base = ImportRow(
                type: .expense, date: date, amount: amount, assetName: account,
                note: cell(noteCol), detail: cell(detailCol)
            )

            switch typeText {
            case "income", "pendapatan", "pemasukan", "expense", "pengeluaran":
                guard !category.isEmpty else {
                    result.failures.append(.init(line: line, reason: "Kategori kosong.")); continue
                }
                var row = base
                row.type = ["income", "pendapatan", "pemasukan"].contains(typeText) ? .income : .expense
                row.categoryName = category
                row.subcategoryName = sub
                result.rows.append(row)
            case "transfer":
                let target = cell(toCol)
                guard !target.isEmpty else {
                    result.failures.append(.init(line: line, reason: "Aset tujuan transfer kosong.")); continue
                }
                guard target.caseInsensitiveCompare(account) != .orderedSame else {
                    result.failures.append(.init(line: line, reason: "Aset asal dan tujuan sama.")); continue
                }
                var row = base
                row.type = .transfer
                row.toAssetName = target
                if let fee = FlexibleNumber.parse(cell(feeCol)), fee > 0 { row.fee = fee }
                result.rows.append(row)
            case "transfer-out", "transferout":
                var row = base; row.type = .transfer
                pendingOut.append((line, row))
            case "transfer-in", "transferin":
                var row = base; row.type = .transfer
                pendingIn.append((line, row))
            default:
                result.failures.append(.init(line: line, reason: "Jenis tidak dikenali: \(cell(typeCol))"))
            }
        }

        // Pasangkan Transfer-Out dengan Transfer-In yang waktu dan nominalnya sama.
        var unusedIn = pendingIn
        for out in pendingOut {
            if let index = unusedIn.firstIndex(where: { $0.row.date == out.row.date && $0.row.amount == out.row.amount }) {
                let incoming = unusedIn.remove(at: index)
                var row = out.row
                row.toAssetName = incoming.row.assetName
                if row.toAssetName.caseInsensitiveCompare(row.assetName) == .orderedSame {
                    result.failures.append(.init(line: out.line, reason: "Aset asal dan tujuan sama."))
                } else {
                    result.rows.append(row)
                }
            } else {
                result.failures.append(.init(line: out.line, reason: "Transfer-Out tanpa pasangan Transfer-In."))
            }
        }
        for leftover in unusedIn {
            result.failures.append(.init(line: leftover.line, reason: "Transfer-In tanpa pasangan Transfer-Out."))
        }

        result.rows.sort { $0.date < $1.date }
        result.failures.sort { $0.line < $1.line }
        var seen = Set<String>()
        result.assets = result.rows.flatMap { [$0.assetName, $0.toAssetName] }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .map { ImportAssetSpec(name: $0, group: .other, currentBalance: nil) }
        return result
    }

    static func parseDate(_ raw: String, timeZone: TimeZone) -> Date? {
        if let date = BackupJSONParser.parseDate(raw, timeZone: timeZone), raw.contains("T") || raw.count == 10 { return date }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy HH:mm", "dd/MM/yyyy"] {
            if let date = BackupJSONParser.formatter(format, timeZone).date(from: raw) { return date }
        }
        return nil
    }

    /// Pemecah CSV (RFC 4180): kutip ganda, koma dan baris baru di dalam kutip, CRLF/LF.
    static func records(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = chars.next()

        while let c = pending {
            pending = chars.next()
            if inQuotes {
                if c == "\"" {
                    if pending == "\"" { field.unicodeScalars.append(c); pending = chars.next() } else { inQuotes = false }
                } else { field.unicodeScalars.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\r": break
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                default: field.unicodeScalars.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
