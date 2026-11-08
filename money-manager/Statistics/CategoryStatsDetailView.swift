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
    @Query private var rawPeriodTransactions: [MoneyTransaction]
    @Environment(FilterState.self) private var filterState
    /// Transactions across the 6-month window ending at the period's last month (trend only).
    @Query private var rawWindowTransactions: [MoneyTransaction]
    @State private var formRoute: TransactionFormRoute?
    /// Month tapped in the trend chart (its first moment). `nil` follows the statistics period.
    @State private var selectedMonth: Date?

    private static let trendMonths = 6

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    init(profile: Profile, share: CategoryShare, kind: CategoryKind, period: StatsPeriod) {
        self.share = share
        self.kind = kind
        self.period = period
        _rawPeriodTransactions = Query(TransactionQueries.descriptor(profileID: profile.id, interval: period.interval))
        let window = Self.trendWindow(endingAt: Self.endMonthStart(of: period))
        _rawWindowTransactions = Query(TransactionQueries.descriptor(profileID: profile.id, interval: window))
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

    /// The same filter as the statistics list, so totals here match the row that opened this screen.
    private var periodTransactions: [MoneyTransaction] { filterState.filter.apply(rawPeriodTransactions) }
    private var windowTransactions: [MoneyTransaction] { filterState.filter.apply(rawWindowTransactions) }

    private var trend: [TrendPoint] {
        StatisticsCalculator.trend(
            windowTransactions, shareID: share.id, kind: kind,
            months: Self.trendMonths, endingAt: Self.endMonthStart(of: period), calendar: .current
        )
    }

    /// What the lists below show: the tapped month's transactions, otherwise the statistics period's.
    private var scopedTransactions: [MoneyTransaction] {
        guard let selectedMonth else { return periodTransactions }
        let month = TransactionQueries.monthInterval(containing: selectedMonth, calendar: .current)
        return windowTransactions.filter { $0.date >= month.start && $0.date < month.end }
    }

    private var scopeLabel: String {
        selectedMonth.map { Self.monthFormatter.string(from: $0) } ?? StatsPeriodLabel.string(period)
    }

    private var subcategories: [CategoryShare] {
        StatisticsCalculator.subcategoryBreakdown(scopedTransactions, parentID: share.id, kind: kind)
    }

    private var transactions: [MoneyTransaction] {
        StatisticsCalculator.transactions(scopedTransactions, shareID: share.id, kind: kind)
    }

    var body: some View {
        let subcategories = subcategories
        List {
            Section("6 bulan terakhir") {
                TrendChart(
                    points: trend,
                    selected: selectedMonth ?? trend.last?.id,
                    onSelect: { selectedMonth = $0 }
                )
            }
            if subcategories.count > 1 {
                Section("Subkategori") {
                    ForEach(Array(subcategories.enumerated()), id: \.element.id) { index, row in
                        ShareRow(row: row, color: StatsPalette.color(rank: index, count: subcategories.count))
                    }
                }
            }
            Section("Transaksi · \(scopeLabel)") {
                if transactions.isEmpty {
                    Text("Belum ada transaksi di \(scopeLabel)")
                        .foregroundStyle(.secondary)
                }
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

/// Six monthly bars; the selected month is tinted, the rest secondary. Tapping anywhere in a month's
/// column (empty months included) selects it.
private struct TrendChart: View {
    let points: [TrendPoint]
    let selected: Date?
    let onSelect: (Date) -> Void

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
            .foregroundStyle(point.id == selected ? Color.accentColor : Color.secondary.opacity(0.5))
            .cornerRadius(4)
            .accessibilityLabel("\(Self.monthFormatter.string(from: point.id))\(point.id == selected ? ", dipilih" : "")")
            .accessibilityValue(MoneyFormatter.string(point.amount))
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame else { return }
                        let x = location.x - geometry[plot].origin.x
                        guard let date: Date = proxy.value(atX: x),
                              let month = points.first(where: {
                                  TransactionQueries.monthInterval(containing: $0.id, calendar: .current).contains(date)
                              })
                        else { return }
                        onSelect(month.id)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { value in
                // Fixed id_ID month names, like the rest of the app, whatever the device language.
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        let isSelected = date == selected
                        Text(date.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "id_ID"))))
                            .fontWeight(isSelected ? .bold : .regular)
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    }
                }
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
