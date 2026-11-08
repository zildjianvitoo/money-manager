import Foundation
import SwiftData
import Testing
@testable import MoneyCore

private let jakarta = TimeZone(identifier: "Asia/Jakarta")!
private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = jakarta
    return c
}

private let sampleJSON = """
{
 "categories": [
  {"id":"p1","name":"Makanan","parentCategoryId":null},
  {"id":"s1","name":"Makan Enak","parentCategoryId":"p1"},
  {"id":"g1","name":"Gaji","parentCategoryId":null}
 ],
 "wallets": [
  {"id":"w1","name":"Tunai","balance":1000000.0,"walletType":"cash"},
  {"id":"w2","name":"BCA","balance":50.5,"walletType":"bank"}
 ],
 "transactions": [
  {"transactionType":1,"category":{"id":"s1","name":"Makan Enak","parentCategoryId":"p1"},
   "wallet":{"id":"w1","name":"Tunai","walletType":"cash"},"amount":25000.0,"date":"2026-09-20T17:04:50.000","notes":"nasi","detail":null},
  {"transactionType":0,"category":{"id":"g1","name":"Gaji","parentCategoryId":null},
   "wallet":{"id":"w1","name":"Tunai","walletType":"cash"},"amount":1100000.0,"date":"2026-10-01T08:00:00.000","notes":null,"detail":null},
  {"transactionType":2,"category":null,"wallet":{"id":"w1","name":"Tunai"},"amount":1.0,"date":"2026-10-01T08:00:00.000","notes":null,"detail":null},
  {"transactionType":1,"category":{"id":"p1","name":"Makanan","parentCategoryId":null},
   "wallet":{"id":"w1","name":"Tunai"},"amount":0,"date":"2026-10-02T08:00:00.000","notes":null,"detail":null}
 ]
}
"""

struct FlexibleNumberTests {
    @Test(arguments: [
        ("19000", "19000"), ("19.000", "19000"), ("19.000,50", "19000.50"), ("19,000.50", "19000.50"),
        ("1.234.567", "1234567"), ("Rp 19.000", "19000"), ("12.5", "12.5"), ("0,5", "0.5"),
    ])
    func parses(raw: String, expected: String) {
        #expect(FlexibleNumber.parse(raw) == Decimal(string: expected))
    }

    @Test func rejectsGarbage() {
        #expect(FlexibleNumber.parse("abc") == nil)
        #expect(FlexibleNumber.parse("") == nil)
        #expect(FlexibleNumber.parse("1,2,x") == nil)
    }
}

struct BackupJSONParserTests {
    @Test func readsRowsFailuresAndAssets() throws {
        let result = try BackupJSONParser.parse(Data(sampleJSON.utf8), timeZone: jakarta)
        #expect(result.rows.count == 2)
        #expect(result.failures.map(\.line) == [3, 4])

        let first = result.rows[0]
        #expect(first.type == .expense)
        #expect(first.categoryName == "Makanan")
        #expect(first.subcategoryName == "Makan Enak")
        #expect(first.assetName == "Tunai")
        #expect(first.amount == 25000)
        #expect(first.note == "nasi")
        // 17:04:50 WIB = 10:04:50 UTC
        #expect(first.date == ISO8601DateFormatter().date(from: "2026-09-20T10:04:50Z"))

        #expect(result.rows[1].type == .income)
        #expect(result.assets.map(\.name).sorted() == ["BCA", "Tunai"])
        #expect(result.assets.first { $0.name == "BCA" }?.group == .bank)
        #expect(result.assets.first { $0.name == "BCA" }?.currentBalance == Decimal(string: "50.5"))
    }

    @Test func rejectsOtherJSON() {
        #expect(throws: ImportParseError.unrecognizedFormat) {
            try BackupJSONParser.parse(Data("{\"a\":1}".utf8))
        }
    }
}

struct CSVTests {
    @Test func splitsQuotedFields() {
        let table = CSVTransactions.records("a,\"b,c\",\"d\"\"e\"\r\n1,2,3\n\"x\ny\",z,\n")
        #expect(table == [["a", "b,c", "d\"e"], ["1", "2", "3"], ["x\ny", "z", ""]])
    }

    @Test func parsesAliasedHeadersAndFlexibleValues() throws {
        let csv = "\u{FEFF}Period,Accounts,Category,Subcategory,Note,IDR,Income/Expense\n"
            + "2026-10-01 08:00:00,Tunai,Gaji,,Bonus,\"1.100.000,00\",Income\n"
            + "01/10/2026 09:00,Tunai,Makanan,Makan Enak,,25.000,Expense\n"
            + "bukan tanggal,Tunai,Makanan,,,10,Expense\n"
        let result = try CSVTransactions.parse(Data(csv.utf8), timeZone: jakarta)
        #expect(result.rows.count == 2)
        #expect(result.rows[0].amount == 1_100_000)
        #expect(result.rows[1].subcategoryName == "Makan Enak")
        #expect(result.failures.map(\.line) == [4])
    }

    @Test func pairsTransferOutAndIn() throws {
        let csv = "Date,Account,Category,Note,Amount,Type\n"
            + "2026-10-01 08:00:00,Tunai,Transfer,,5000,Transfer-Out\n"
            + "2026-10-01 08:00:00,BCA,Transfer,,5000,Transfer-In\n"
            + "2026-10-02 08:00:00,Tunai,Transfer,,7000,Transfer-Out\n"
        let result = try CSVTransactions.parse(Data(csv.utf8), timeZone: jakarta)
        #expect(result.rows.count == 1)
        #expect(result.rows[0].type == .transfer)
        #expect(result.rows[0].assetName == "Tunai")
        #expect(result.rows[0].toAssetName == "BCA")
        #expect(result.failures.map(\.line) == [4])
    }

    @Test func reportsMissingColumns() {
        #expect(throws: ImportParseError.missingColumns(["Amount", "Type"])) {
            try CSVTransactions.parse(Data("Date,Account\n".utf8))
        }
    }
}

@MainActor
struct ImportServiceTests {
    /// Container harus tetap hidup selama test, jadi ikut dikembalikan.
    nonisolated(unsafe) private static var keep: [ModelContainer] = []

    private func makeService() throws -> (ImportService, ModelContext, UUID) {
        let container = try MoneySchema.makeContainer(inMemory: true)
        Self.keep.append(container)
        let pid = UUID()
        return (ImportService(context: container.mainContext, profileID: pid), container.mainContext, pid)
    }

    private func rows() throws -> ImportParseResult {
        try BackupJSONParser.parse(Data(sampleJSON.utf8), timeZone: jakarta)
    }

    private func transactions(_ context: ModelContext, _ pid: UUID) throws -> [MoneyTransaction] {
        try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.profileID == pid }))
    }

    @Test func previewReportsMonthsAndNewItems() throws {
        let (service, _, _) = try makeService()
        let preview = try service.preview(try rows().rows, calendar: calendar)
        #expect(preview.rowCount == 2)
        #expect(preview.months == [
            MonthTotal(year: 2026, month: 9, income: 0, expense: 25000),
            MonthTotal(year: 2026, month: 10, income: 1_100_000, expense: 0),
        ])
        #expect(preview.newCategoryNames == ["Makanan", "Makanan › Makan Enak", "Gaji"])
        #expect(preview.newAssetNames == ["Tunai"])
        #expect(preview.duplicateCount == 0)
    }

    @Test func commitCreatesStructureAndOpeningBalance() throws {
        let (service, context, pid) = try makeService()
        let parsed = try rows()
        let outcome = try service.commit(parsed.rows, assets: parsed.assets, fileName: "backup.json")
        #expect(outcome.imported == 2)

        let txs = try transactions(context, pid)
        #expect(txs.count == 2)
        #expect(txs.allSatisfy { $0.importBatchID == outcome.batchID })
        let expense = try #require(txs.first { $0.type == .expense })
        #expect(expense.category?.name == "Makan Enak")
        #expect(expense.category?.parent?.name == "Makanan")

        // Saldo sekarang di file 1.000.000 => saldo awal = 1.000.000 - (1.100.000 - 25.000).
        let asset = try #require(try context.fetch(FetchDescriptor<AssetAccount>()).first { $0.profileID == pid })
        #expect(asset.initialBalance == -75_000)
        #expect(BalanceCalculator.balance(of: asset, transactions: txs) == 1_000_000)
    }

    @Test func secondImportOfSameFileAddsNothing() throws {
        let (service, context, pid) = try makeService()
        let parsed = try rows()
        try service.commit(parsed.rows, assets: parsed.assets, fileName: "a.json")
        #expect(try service.preview(parsed.rows).duplicateCount == 2)
        #expect(throws: ImportServiceError.nothingToImport) {
            try service.commit(parsed.rows, assets: parsed.assets, fileName: "a.json")
        }
        #expect(try transactions(context, pid).count == 2)
    }

    @Test func identicalRowsInsideOneFileBothImport() throws {
        let (service, context, pid) = try makeService()
        let row = ImportRow(type: .expense, date: Date(timeIntervalSince1970: 1_000_000), amount: 5000,
                            categoryName: "Jajan", assetName: "Tunai", note: "es teh")
        let outcome = try service.commit([row, row], fileName: "x.csv")
        #expect(outcome.imported == 2)
        #expect(try transactions(context, pid).count == 2)
        // Import ulang: keduanya sudah ada, jadi dua-duanya dilewati.
        #expect(try service.preview([row, row]).duplicateCount == 2)
        #expect(try service.preview([row, row, row]).duplicateCount == 2)
    }

    @Test func keepDuplicatesWhenAsked() throws {
        let (service, context, pid) = try makeService()
        let parsed = try rows()
        try service.commit(parsed.rows, assets: parsed.assets, fileName: "a.json")
        try service.commit(parsed.rows, assets: parsed.assets, fileName: "a.json", skipDuplicates: false)
        #expect(try transactions(context, pid).count == 4)
    }

    @Test func matchesExistingCategoriesAndAssetsByName() throws {
        let (service, context, pid) = try makeService()
        let existingCategory = MoneyCategory(profileID: pid, name: "makanan", kind: .expense)
        let existingAsset = AssetAccount(profileID: pid, name: "TUNAI", group: .cash)
        context.insert(existingCategory)
        context.insert(existingAsset)
        try context.save()

        let parsed = try rows()
        let preview = try service.preview(parsed.rows)
        #expect(preview.newAssetNames.isEmpty)
        #expect(preview.newCategoryNames == ["Makanan › Makan Enak", "Gaji"])
        try service.commit(parsed.rows, assets: parsed.assets, fileName: "a.json")
        #expect(try context.fetch(FetchDescriptor<AssetAccount>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<MoneyCategory>()).filter { $0.name.lowercased() == "makanan" }.count == 1)
    }

    @Test func undoRemovesTransactionsAndCreatedItemsOnly() throws {
        let (service, context, pid) = try makeService()
        let keep = MoneyCategory(profileID: pid, name: "Makanan", kind: .expense)
        context.insert(keep)
        try context.save()

        let parsed = try rows()
        try service.commit(parsed.rows, assets: parsed.assets, fileName: "a.json")
        let batch = try #require(try service.batches().first)
        try service.undo(batch)

        #expect(try transactions(context, pid).isEmpty)
        #expect(try service.batches().isEmpty)
        #expect(try context.fetch(FetchDescriptor<AssetAccount>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MoneyCategory>()).map(\.name) == ["Makanan"])
    }

    @Test func undoKeepsItemsStillUsedByOtherTransactions() throws {
        let (service, context, pid) = try makeService()
        let parsed = try rows()
        try service.commit(parsed.rows, assets: parsed.assets, fileName: "a.json")
        // Transaksi manual memakai aset hasil import.
        let asset = try #require(try context.fetch(FetchDescriptor<AssetAccount>()).first)
        let category = try #require(try context.fetch(FetchDescriptor<MoneyCategory>()).first { $0.name == "Gaji" })
        let manual = MoneyTransaction(profileID: pid, type: .income, amount: 1, date: .now)
        manual.asset = asset
        manual.category = category
        context.insert(manual)
        try context.save()

        try service.undo(try #require(try service.batches().first))
        #expect(try context.fetch(FetchDescriptor<AssetAccount>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<MoneyCategory>()).map(\.name) == ["Gaji"])
        #expect(try transactions(context, pid).count == 1)
    }

    @Test func importsTransfersWithFee() throws {
        let (service, context, pid) = try makeService()
        let row = ImportRow(type: .transfer, date: Date(timeIntervalSince1970: 2_000_000), amount: 10_000, fee: 500,
                            assetName: "Tunai", toAssetName: "BCA")
        try service.commit([row], fileName: "t.csv")
        let tx = try #require(try transactions(context, pid).first)
        #expect(tx.type == .transfer)
        #expect(tx.fee == 500)
        #expect(tx.asset?.name == "Tunai")
        #expect(tx.toAsset?.name == "BCA")
        let preview = try service.preview([row], calendar: calendar)
        #expect(preview.months.first?.expense == 500)
    }
}

@MainActor
struct ExportRoundTripTests {
    @Test func exportThenImportIntoEmptyProfileMatches() throws {
        let container = try MoneySchema.makeContainer(inMemory: true)
        let context = container.mainContext
        let source = UUID()
        let cash = AssetAccount(profileID: source, name: "Tunai", group: .cash)
        let bank = AssetAccount(profileID: source, name: "BCA, \"utama\"", group: .bank)
        let food = MoneyCategory(profileID: source, name: "Makanan", kind: .expense)
        let dinner = MoneyCategory(profileID: source, name: "Makan Enak", kind: .expense, parent: food)
        let salary = MoneyCategory(profileID: source, name: "Gaji", kind: .income)
        [cash, bank].forEach(context.insert)
        [food, dinner, salary].forEach(context.insert)

        func add(_ type: TransactionType, _ amount: Decimal, _ day: Int, category: MoneyCategory?, note: String = "") {
            let tx = MoneyTransaction(profileID: source, type: type, amount: amount,
                                      date: calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!)
            tx.asset = cash
            tx.category = category
            tx.note = note
            context.insert(tx)
        }
        add(.expense, Decimal(string: "25000.50")!, 3, category: dinner, note: "nasi, \"pedas\"\nbaris dua")
        add(.income, 1_000_000, 5, category: salary)
        add(.expense, 12_000, 40 - 9, category: food)
        let transfer = MoneyTransaction(profileID: source, type: .transfer, amount: 70_000,
                                        date: calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9))!)
        transfer.asset = cash; transfer.toAsset = bank; transfer.fee = 2500
        context.insert(transfer)
        let adjustment = MoneyTransaction(profileID: source, type: .adjustment, amount: 5, date: .now)
        adjustment.asset = cash
        context.insert(adjustment)
        try context.save()

        let all = try context.fetch(FetchDescriptor<MoneyTransaction>())
        let data = CSVTransactions.export(all, timeZone: jakarta)
        #expect(data.starts(with: [0xEF, 0xBB, 0xBF]))

        let parsed = try CSVTransactions.parse(data, timeZone: jakarta)
        #expect(parsed.failures.isEmpty)
        #expect(parsed.rows.count == 4)

        let target = UUID()
        let service = ImportService(context: context, profileID: target)
        try service.commit(parsed.rows, assets: parsed.assets, fileName: "export.csv")

        let imported = try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.profileID == target }))
        #expect(imported.count == 4)
        let original = all.filter { $0.type != .adjustment }
        for month in 10...11 {
            func totals(_ list: [MoneyTransaction]) -> [Decimal] {
                let inMonth = list.filter { calendar.component(.month, from: $0.date) == month }
                return [
                    inMonth.filter { $0.type == .income }.reduce(0) { $0 + $1.amount },
                    inMonth.reduce(0) { $0 + ($1.type == .expense ? $1.amount : $1.type == .transfer ? $1.fee : 0) },
                ]
            }
            #expect(totals(imported) == totals(original))
        }
        let note = try #require(imported.first { $0.note.contains("pedas") })
        #expect(note.note == "nasi, \"pedas\"\nbaris dua")
        #expect(note.category?.parent?.name == "Makanan")
        #expect(imported.contains { $0.type == .transfer && $0.toAsset?.name == "BCA, \"utama\"" && $0.fee == 2500 })
    }
}

/// Validasi dengan file asli pemilik (folder `private/` tidak ada di git); dilewati bila file tidak ada.
@MainActor
struct RealBackupTests {
    @Test func realBackupMonthlyTotals() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("private")
        guard let file = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .first(where: { $0.lastPathComponent.hasPrefix("moneymanager_backup") && $0.pathExtension == "json" })
        else { return }
        let parsed = try BackupJSONParser.parse(Data(contentsOf: file), timeZone: .current)
        #expect(parsed.failures.isEmpty)
        let container = try MoneySchema.makeContainer(inMemory: true)
        let service = ImportService(context: container.mainContext, profileID: UUID())
        let preview = try service.preview(parsed.rows)
        // Angka pembanding dihitung terpisah dari file yang sama (Money Manager, backup 3 Nov 2026).
        #expect(parsed.rows.count == 78)
        #expect(preview.months.map { [$0.income, $0.expense] } == [[3_000_000, 137_000], [9_518_000, 835_000], [868_000, 45_500]])
    }
}
