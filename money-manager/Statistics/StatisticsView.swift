import SwiftUI
import SwiftData
import Charts
import MoneyCore

/// "Statistik" tab: period navigation, income/expense split and a category donut.
struct StatisticsView: View {
    @Environment(ProfileStore.self) private var store
    @Query(sort: [SortDescriptor(\Profile.sortOrder), SortDescriptor(\Profile.createdAt)]) private var profiles: [Profile]

    @State private var period = StatsPeriod.containing(.now, kind: .monthly, calendar: .current)
    @State private var kind: CategoryKind = .expense

    private var activeProfile: Profile? {
        profiles.first { $0.id == store.activeProfileID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let profile = activeProfile {
                    PeriodStatsView(profile: profile, period: $period, kind: $kind)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Statistik")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
    }
}

// MARK: - Palette

/// Fixed palette by rank so a category keeps its colour between the donut and the list.
enum StatsPalette {
    static let colors: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .yellow, .indigo]

    /// Rank 0-based. With more than 8 rows, ranks from 7 on share the gray "Lainnya" slice.
    static func color(rank: Int, count: Int) -> Color {
        if count > colors.count, rank >= colors.count - 1 { return .gray }
        return colors[rank % colors.count]
    }
}

// MARK: - Period label

enum StatsPeriodLabel {
    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private static let day = formatter("d")
    private static let dayMonth = formatter("dMMM")
    private static let monthYear = formatter("MMMyyyy")
    private static let dayMonthYear = formatter("dMMMyyyy")
    private static let year = formatter("yyyy")

    /// "2–8 Nov 2026", "Nov 2026", "2026", "1 Okt – 15 Nov 2026".
    static func string(_ period: StatsPeriod, calendar: Calendar = .current) -> String {
        let start = period.interval.start
        // Interval end is exclusive; the label shows the last day included.
        let last = calendar.date(byAdding: .second, value: -1, to: period.interval.end) ?? period.interval.end
        switch period.kind {
        case .monthly: return monthYear.string(from: start)
        case .yearly: return year.string(from: start)
        case .weekly, .range:
            if !calendar.isDate(start, equalTo: last, toGranularity: .year) {
                return "\(dayMonthYear.string(from: start)) – \(dayMonthYear.string(from: last))"
            }
            if calendar.isDate(start, equalTo: last, toGranularity: .month) {
                if calendar.isDate(start, inSameDayAs: last) { return dayMonthYear.string(from: start) }
                return "\(day.string(from: start))–\(dayMonthYear.string(from: last))"
            }
            return "\(dayMonth.string(from: start)) – \(dayMonthYear.string(from: last))"
        }
    }

    static func name(_ kind: StatsPeriodKind) -> String {
        switch kind {
        case .weekly: "Mingguan"
        case .monthly: "Bulanan"
        case .yearly: "Tahunan"
        case .range: "Rentang"
        }
    }
}

// MARK: - Content

/// Owns the `@Query` for one profile and period; rebuilt whenever either changes.
private struct PeriodStatsView: View {
    let profile: Profile
    @Binding var period: StatsPeriod
    @Binding var kind: CategoryKind

    @Query private var transactions: [MoneyTransaction]
    @State private var isRangeSheetPresented = false

    init(profile: Profile, period: Binding<StatsPeriod>, kind: Binding<CategoryKind>) {
        self.profile = profile
        _period = period
        _kind = kind
        _transactions = Query(TransactionQueries.descriptor(profileID: profile.id, interval: period.wrappedValue.interval))
    }

    private var rows: [CategoryShare] {
        StatisticsCalculator.breakdown(transactions, kind: kind)
    }

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .sheet(isPresented: $isRangeSheetPresented) {
                RangeSheet(period: period) { period = $0 }
            }
    }

    @ViewBuilder
    private var content: some View {
        let rows = rows
        if rows.isEmpty {
            ContentUnavailableView("Belum ada data", systemImage: "chart.pie", description: Text(StatsPeriodLabel.string(period)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Same backdrop as the header and the grouped list, so no band shows between them.
                .background(Color(.systemGroupedBackground))
                .contentShape(Rectangle())
                .gesture(periodSwipe)
        } else {
            List {
                Section {
                    DonutView(rows: rows, total: StatisticsCalculator.total(transactions, kind: kind))
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        NavigationLink {
                            CategoryStatsDetailView(profile: profile, share: row, kind: kind, period: period)
                        } label: {
                            ShareRow(row: row, color: StatsPalette.color(rank: index, count: rows.count))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                periodMenu
                Spacer()
            }
            periodNavigator
            kindPicker
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        // Pinned bar: capped like system bars so accessibility sizes don't fill the screen; the list still scales.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // Opaque so rows scroll beneath it.
        .background(Color(.systemGroupedBackground), ignoresSafeAreaEdges: [])
        .contentShape(Rectangle())
        // High priority: the inset sits on the list's scroll view, whose pan would win otherwise.
        .highPriorityGesture(periodSwipe)
    }

    private var periodMenu: some View {
        Menu {
            Picker("Periode", selection: kindBinding) {
                ForEach(StatsPeriodKind.allCases, id: \.self) { Text(StatsPeriodLabel.name($0)).tag($0) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(StatsPeriodLabel.name(period.kind))
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .font(.subheadline.weight(.medium))
        }
        .accessibilityLabel("Periode, \(StatsPeriodLabel.name(period.kind))")
    }

    /// Picking Rentang asks for dates first; the other kinds re-anchor on the middle of the current period.
    private var kindBinding: Binding<StatsPeriodKind> {
        Binding(
            get: { period.kind },
            set: { newKind in
                if newKind == .range {
                    isRangeSheetPresented = true
                } else {
                    let middle = period.interval.start.addingTimeInterval(period.interval.duration / 2)
                    withAnimation { period = .containing(middle, kind: newKind, calendar: .current) }
                }
            }
        )
    }

    private var periodNavigator: some View {
        // Chevrons pinned to the header edges; each one's button fills the space up to the label, so the whole side is tappable.
        HStack(spacing: 8) {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Periode sebelumnya")
            Button {
                if period.kind == .range { isRangeSheetPresented = true }
            } label: {
                Text(StatsPeriodLabel.string(period))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.plain)
            Button { shift(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Periode berikutnya")
        }
    }

    /// Two segments, each with its period total, so both numbers stay visible while switching.
    private var kindPicker: some View {
        HStack(spacing: 4) {
            kindSegment(.income, title: "Pendapatan")
            kindSegment(.expense, title: "Pengeluaran")
        }
        .padding(3)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    private func kindSegment(_ segment: CategoryKind, title: String) -> some View {
        let selected = kind == segment
        let total = MoneyFormatter.string(StatisticsCalculator.total(transactions, kind: segment))
        return Button {
            withAnimation(.snappy) { kind = segment }
        } label: {
            VStack(spacing: 1) {
                Text(title).font(.caption)
                Text(total)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if selected { Capsule().fill(Color(.systemBackground)) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(total)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Horizontal swipe on the header or the empty state shifts the period.
    private var periodSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 60, abs(dx) > abs(value.translation.height) * 2 else { return }
                shift(dx < 0 ? 1 : -1)
            }
    }

    private func shift(_ delta: Int) {
        withAnimation { period = period.shifted(by: delta, calendar: .current) }
    }
}

// MARK: - Donut

/// One slice of the donut; the tail beyond the palette is merged into "Lainnya".
private struct DonutSlice: Identifiable {
    let id: Int
    let name: String
    let amount: Decimal
    let fraction: Double
    let color: Color
}

private struct DonutView: View {
    let rows: [CategoryShare]
    let total: Decimal

    private var slices: [DonutSlice] {
        let limit = StatsPalette.colors.count
        guard rows.count > limit else {
            return rows.enumerated().map { index, row in
                DonutSlice(id: index, name: row.name, amount: row.amount, fraction: row.fraction,
                           color: StatsPalette.color(rank: index, count: rows.count))
            }
        }
        // Chart only: ranks 0..<7 keep their colour, the rest collapse into one gray slice.
        let head = rows.prefix(limit - 1)
        let tail = rows.dropFirst(limit - 1)
        var result = head.enumerated().map { index, row in
            DonutSlice(id: index, name: row.name, amount: row.amount, fraction: row.fraction, color: StatsPalette.colors[index])
        }
        result.append(DonutSlice(
            id: limit - 1, name: "Lainnya",
            amount: tail.reduce(0) { $0 + $1.amount },
            fraction: tail.reduce(0) { $0 + $1.fraction },
            color: .gray
        ))
        return result
    }

    var body: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Jumlah", NSDecimalNumber(decimal: slice.amount).doubleValue),
                innerRadius: .ratio(0.6),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(slice.color)
            .accessibilityLabel(slice.name)
            .accessibilityValue("\(MoneyFormatter.string(slice.amount)), \(Int((slice.fraction * 100).rounded())) persen")
        }
        .chartLegend(.hidden)
        .frame(height: 220)
        .overlay {
            VStack(spacing: 2) {
                Text("Total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(MoneyFormatter.string(total))
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            // Keeps the label inside the hole (60% of the donut's diameter).
            .frame(width: 120)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Rows

/// Percent badge, emoji + name, amount. Shared by the category list and the subcategory breakdown.
struct ShareRow: View {
    let row: CategoryShare
    let color: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var percentText: String {
        let percent = row.fraction * 100
        return percent > 0 && percent < 1 ? "<1%" : "\(Int(percent.rounded()))%"
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Stacked so nothing truncates at accessibility sizes.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        badge
                        Text(row.emoji).accessibilityHidden(true)
                        Text(row.name)
                    }
                    amount
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    badge
                    Text(row.emoji)
                        .font(.title3)
                        .accessibilityHidden(true)
                    Text(row.name)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    amount
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name), \(percentText), \(MoneyFormatter.string(row.amount))")
    }

    private var badge: some View {
        Text(percentText)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 48)
            .background(color, in: Capsule())
    }

    private var amount: some View {
        Text(MoneyFormatter.string(row.amount))
            .font(.body.weight(.medium))
            .monospacedDigit()
    }
}

// MARK: - Range sheet

/// Two date pickers (Dari / Sampai) for the "Rentang" period.
private struct RangeSheet: View {
    let onApply: (StatsPeriod) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var from: Date
    @State private var to: Date

    init(period: StatsPeriod, onApply: @escaping (StatsPeriod) -> Void) {
        self.onApply = onApply
        _from = State(initialValue: period.interval.start)
        // Interval end is exclusive; show the last included day.
        _to = State(initialValue: Calendar.current.date(byAdding: .second, value: -1, to: period.interval.end) ?? period.interval.end)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Dari", selection: $from, in: ...to, displayedComponents: .date)
                DatePicker("Sampai", selection: $to, in: from..., displayedComponents: .date)
            }
            .environment(\.locale, Locale(identifier: "id_ID"))
            .navigationTitle("Rentang")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terapkan") {
                        onApply(.range(from: from, to: to, calendar: .current))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
