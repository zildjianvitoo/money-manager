import SwiftUI
import SwiftData
import Charts
import MoneyCore

/// One category in the statistics tab: 6-month trend, subcategories and the period's transactions.
struct CategoryStatsDetailView: View {
    let share: CategoryShare
    let kind: CategoryKind
    let period: StatsPeriod

    /// Transactions inside the period (subcategories + list).
    @Query private var periodTransactions: [MoneyTransaction]
    /// Transactions across the 6-month window ending at the period's last month (trend only).
    @Query private var windowTransactions: [MoneyTransaction]
    @State private var formRoute: TransactionFormRoute?

    private static let trendMonths = 6

    init(profile: Profile, share: CategoryShare, kind: CategoryKind, period: StatsPeriod) {
        self.share = share
        self.kind = kind
        self.period = period
        _periodTransactions = Query(TransactionQueries.descriptor(profileID: profile.id, interval: period.interval))
        let window = Self.trendWindow(endingAt: Self.endMonthStart(of: period))
        _windowTransactions = Query(TransactionQueries.descriptor(profileID: profile.id, interval: window))
    }

    /// Start of the month holding the period's last included moment (the interval end is exclusive).
    private static func endMonthStart(of period: StatsPeriod) -> Date {
        let calendar = Calendar.current
        let last = calendar.date(byAdding: .second, value: -1, to: period.interval.end) ?? period.interval.end
        return TransactionQueries.monthInterval(containing: last, calendar: calendar).start
    }

    private static func trendWindow(endingAt monthStart: Date) -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .month, value: -(trendMonths - 1), to: monthStart) ?? monthStart
        let end = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        return DateInterval(start: start, end: end)
    }

    private var trend: [TrendPoint] {
        StatisticsCalculator.trend(
            windowTransactions, shareID: share.id, kind: kind,
            months: Self.trendMonths, endingAt: Self.endMonthStart(of: period), calendar: .current
        )
    }

    private var subcategories: [CategoryShare] {
        StatisticsCalculator.subcategoryBreakdown(periodTransactions, parentID: share.id, kind: kind)
    }

    private var transactions: [MoneyTransaction] {
        StatisticsCalculator.transactions(periodTransactions, shareID: share.id, kind: kind)
    }

    var body: some View {
        let subcategories = subcategories
        List {
            Section("6 bulan terakhir") {
                TrendChart(points: trend)
            }
            if subcategories.count > 1 {
                Section("Subkategori") {
                    ForEach(Array(subcategories.enumerated()), id: \.element.id) { index, row in
                        ShareRow(row: row, color: StatsPalette.color(rank: index, count: subcategories.count))
                    }
                }
            }
            Section("Transaksi · \(StatsPeriodLabel.string(period))") {
                ForEach(transactions) { tx in
                    Button { formRoute = .edit(tx) } label: {
                        TransactionRow(transaction: tx)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(share.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $formRoute) { route in
            switch route {
            case .create(let date): TransactionFormView(mode: .create(defaultDate: date))
            case .edit(let tx): TransactionFormView(mode: .edit(tx))
            }
        }
    }
}

/// Six monthly bars; the last (the period's month) is tinted, the rest secondary.
private struct TrendChart: View {
    let points: [TrendPoint]

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    /// "1,2 jt", "350 rb" - keeps the y-axis labels short.
    private static func compact(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.maximumFractionDigits = 1
        if value >= 1_000_000 { return (formatter.string(from: NSNumber(value: value / 1_000_000)) ?? "") + " jt" }
        if value >= 1_000 { return (formatter.string(from: NSNumber(value: value / 1_000)) ?? "") + " rb" }
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Bulan", point.id, unit: .month),
                y: .value("Jumlah", NSDecimalNumber(decimal: point.amount).doubleValue)
            )
            .foregroundStyle(point.id == points.last?.id ? Color.accentColor : Color.secondary.opacity(0.5))
            .cornerRadius(4)
            .accessibilityLabel(Self.monthFormatter.string(from: point.id))
            .accessibilityValue(MoneyFormatter.string(point.amount))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                // Fixed id_ID month names, like the rest of the app, whatever the device language.
                AxisValueLabel(format: .dateTime.month(.abbreviated).locale(Locale(identifier: "id_ID")), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) { Text(Self.compact(amount)) }
                }
            }
        }
        .environment(\.locale, Locale(identifier: "id_ID"))
        .frame(height: 180)
        .padding(.vertical, 4)
    }
}
