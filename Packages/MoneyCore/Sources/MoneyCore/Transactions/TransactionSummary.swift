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
