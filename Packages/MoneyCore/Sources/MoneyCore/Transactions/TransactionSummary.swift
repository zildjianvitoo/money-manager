import Foundation

public struct MonthSummary: Equatable {
    public let income: Decimal
    public let expense: Decimal
    public var total: Decimal { income - expense }

    public init(income: Decimal, expense: Decimal) {
        self.income = income
        self.expense = expense
    }
}

public struct DaySection: Identifiable {
    /// Awal hari pada kalender yang diberikan.
    public let id: Date
    public let income: Decimal
    public let expense: Decimal
    /// Terbaru di atas.
    public let transactions: [MoneyTransaction]
}

public struct DayTotals: Equatable {
    public let income: Decimal
    public let expense: Decimal

    public init(income: Decimal, expense: Decimal) {
        self.income = income
        self.expense = expense
    }
}

public struct MonthRow: Identifiable, Equatable {
    /// Awal bulan pada kalender yang diberikan.
    public let id: Date
    public let income: Decimal
    public let expense: Decimal
    public var total: Decimal { income - expense }

    public init(id: Date, income: Decimal, expense: Decimal) {
        self.id = id
        self.income = income
        self.expense = expense
    }
}

public enum TransactionSummary {
    /// Income = `.income`; expense = `.expense` + fee `.transfer`. Transfer (tanpa fee) dan adjustment tidak dihitung.
    public static func month(_ txs: [MoneyTransaction]) -> MonthSummary {
        let (income, expense) = totals(txs)
        return MonthSummary(income: income, expense: expense)
    }

    /// Kelompok per hari, hari terbaru di atas; dalam satu hari transaksi terbaru di atas.
    public static func daySections(_ txs: [MoneyTransaction], calendar: Calendar) -> [DaySection] {
        let grouped = Dictionary(grouping: txs) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let sorted = grouped[day]!.sorted {
                $0.date != $1.date ? $0.date > $1.date : $0.createdAt > $1.createdAt
            }
            let (income, expense) = totals(sorted)
            return DaySection(id: day, income: income, expense: expense, transactions: sorted)
        }
    }

    /// Total per hari; kunci = awal hari. Aturan hitung sama dengan `month`.
    public static func dayTotals(_ txs: [MoneyTransaction], calendar: Calendar) -> [Date: DayTotals] {
        let grouped = Dictionary(grouping: txs) { calendar.startOfDay(for: $0.date) }
        return grouped.mapValues { group in
            let (income, expense) = totals(group)
            return DayTotals(income: income, expense: expense)
        }
    }

    /// Selalu 12 baris, Januari sampai Desember tahun yang memuat `year`; bulan kosong bernilai 0.
    public static func monthRows(_ txs: [MoneyTransaction], year: Date, calendar: Calendar) -> [MonthRow] {
        let yearInterval = TransactionQueries.yearInterval(containing: year, calendar: calendar)
        return (0..<12).map { offset in
            let start = calendar.date(byAdding: .month, value: offset, to: yearInterval.start) ?? yearInterval.start
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let (income, expense) = totals(txs.filter { $0.date >= start && $0.date < end })
            return MonthRow(id: start, income: income, expense: expense)
        }
    }

    private static func totals(_ txs: [MoneyTransaction]) -> (income: Decimal, expense: Decimal) {
        var income: Decimal = 0
        var expense: Decimal = 0
        for tx in txs {
            switch tx.type {
            case .income: income += tx.amount
            case .expense: expense += tx.amount
            case .transfer: expense += tx.fee
            case .adjustment: break
            }
        }
        return (income, expense)
    }
}
