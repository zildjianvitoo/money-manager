import SwiftUI
import SwiftData
import MoneyCore

enum TransactionListMode: String, CaseIterable, Identifiable {
    case daily = "Harian"
    case calendar = "Kalender"
    case monthly = "Bulanan"

    var id: Self { self }
}

/// What the transaction sheet opens with.
enum TransactionFormRoute: Identifiable {
    case create(defaultDate: Date)
    case edit(MoneyTransaction)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let tx): tx.id.uuidString
        }
    }
}

/// "Transaksi" tab: month navigation, month summary and the daily list.
struct TransactionListView: View {
    @Environment(ProfileStore.self) private var store
    @Query(sort: [SortDescriptor(\Profile.sortOrder), SortDescriptor(\Profile.createdAt)]) private var profiles: [Profile]

    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var mode: TransactionListMode = .daily
    @State private var formRoute: TransactionFormRoute?
    @State private var isSearching = false
    @State private var isFiltering = false
    @Environment(FilterState.self) private var filterState
    /// Day picked in the calendar view; owned here so the + button can use it.
    @State private var selectedDay: Date?

    private var activeProfile: Profile? {
        profiles.first { $0.id == store.activeProfileID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let profile = activeProfile {
                    if mode == .monthly {
                        YearTransactionsView(profile: profile, month: $month, mode: $mode)
                    } else {
                        MonthTransactionsView(
                            profile: profile,
                            month: $month,
                            mode: $mode,
                            selectedDay: $selectedDay,
                            onOpen: { formRoute = $0 }
                        )
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Transaksi")
            // Large title in the bar row itself: `.large` adds an empty bar above it, since this screen has no toolbar items.
            .toolbarTitleDisplayMode(.inlineLarge)
            .onChange(of: month) { selectedDay = nil }
            .toolbar {
                if activeProfile != nil {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Cari", systemImage: "magnifyingglass") { isSearching = true }
                        FilterToolbarButton(activeCount: filterState.filter.activeCount) { isFiltering = true }
                    }
                }
            }
            .sheet(isPresented: $isSearching) {
                if let profile = activeProfile { SearchView(profileID: profile.id) }
            }
            .sheet(isPresented: $isFiltering) {
                if let profile = activeProfile { FilterSheet(profileID: profile.id) }
            }
            .overlay(alignment: .bottomTrailing) {
                if activeProfile != nil {
                    addButton
                }
            }
            .sheet(item: $formRoute) { route in
                switch route {
                case .create(let date): TransactionFormView(mode: .create(defaultDate: date))
                case .edit(let tx): TransactionFormView(mode: .edit(tx))
                }
            }
        }
    }

    private var addButton: some View {
        Button {
            formRoute = .create(defaultDate: defaultDate)
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Tambah transaksi")
        .padding(.trailing, 20)
        .padding(.bottom, 16)
    }

    /// The selected calendar day (noon, or now if today); else now in the current month, otherwise noon on the 1st of the viewed month.
    private var defaultDate: Date {
        let calendar = Calendar.current
        if mode == .calendar, let day = selectedDay {
            if calendar.isDateInToday(day) { return .now }
            return calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: day)) ?? day
        }
        if calendar.isDate(month, equalTo: .now, toGranularity: .month) { return .now }
        return calendar.date(byAdding: .hour, value: 12, to: month) ?? month
    }
}

/// Owns the `@Query` for one profile and month; rebuilt whenever either changes.
private struct MonthTransactionsView: View {
    let profile: Profile
    @Binding var month: Date
    @Binding var mode: TransactionListMode
    @Binding var selectedDay: Date?
    let onOpen: (TransactionFormRoute) -> Void

    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(FilterState.self) private var filterState
    @Query private var rawTransactions: [MoneyTransaction]
    @State private var pendingDelete: MoneyTransaction?

    private var transactions: [MoneyTransaction] { filterState.filter.apply(rawTransactions) }

    init(profile: Profile, month: Binding<Date>, mode: Binding<TransactionListMode>, selectedDay: Binding<Date?>, onOpen: @escaping (TransactionFormRoute) -> Void) {
        self.profile = profile
        _month = month
        _mode = mode
        _selectedDay = selectedDay
        self.onOpen = onOpen
        let interval = TransactionQueries.monthInterval(containing: month.wrappedValue, calendar: .current)
        _rawTransactions = Query(TransactionQueries.descriptor(profileID: profile.id, interval: interval))
    }

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .confirmationDialog(
                "Hapus transaksi ini?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { tx in
                Button("Hapus", role: .destructive) { delete(tx) }
            } message: { _ in
                Text("Transaksi yang dihapus tidak bisa dikembalikan.")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .daily:
            if transactions.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Same backdrop as the header and the grouped list, so no band shows between them.
                    .background(Color(.systemGroupedBackground))
                    .contentShape(Rectangle())
                    .gesture(monthSwipe)
            } else {
                dailyList
            }
        case .calendar:
            calendarList
        case .monthly:
            // Handled by `YearTransactionsView`.
            EmptyView()
        }
    }

    private var dailyList: some View {
        List {
            ForEach(TransactionSummary.daySections(transactions, calendar: .current)) { section in
                DailySectionView(
                    section: section,
                    onOpen: { onOpen(.edit($0)) },
                    onDelete: { pendingDelete = $0 },
                    onDuplicate: duplicate
                )
            }
        }
        .listStyle(.insetGrouped)
        // Keeps the last rows clear of the floating + button.
        .contentMargins(.bottom, 72, for: .scrollContent)
    }

    private var calendarList: some View {
        let calendar = Calendar.current
        let selected = selectedDay.flatMap { day in
            TransactionSummary.daySections(transactions, calendar: calendar).first { $0.id == day }
        }
        return List {
            Section {
                CalendarMonthView(
                    month: month,
                    dayTotals: TransactionSummary.dayTotals(transactions, calendar: calendar),
                    selectedDay: $selectedDay
                )
                .simultaneousGesture(monthSwipe)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            if let selected {
                DailySectionView(
                    section: selected,
                    onOpen: { onOpen(.edit($0)) },
                    onDelete: { pendingDelete = $0 },
                    onDuplicate: duplicate
                )
            } else if let day = selectedDay {
                Section {
                    Text("Tidak ada transaksi")
                        .foregroundStyle(.secondary)
                } header: {
                    Text(day, format: .dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "id_ID")))
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, 72, for: .scrollContent)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(filterState.filter.isActive ? "Tidak ada yang cocok" : "Belum ada transaksi", systemImage: "tray")
        } description: {
            Text(filterState.filter.isActive ? "dengan filter di \(MonthFormat.string(month))" : "di \(MonthFormat.string(month))")
        } actions: {
            if filterState.filter.isActive {
                Button("Hapus filter") { filterState.filter = TransactionFilter() }
                    .buttonStyle(.bordered)
            } else {
                Button("Catat transaksi") { onOpen(.create(defaultDate: defaultDate)) }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        TransactionListHeader(
            title: MonthFormat.string(month),
            previousLabel: "Bulan sebelumnya",
            nextLabel: "Bulan berikutnya",
            summary: TransactionSummary.month(transactions),
            mode: $mode,
            onShift: shiftMonth
        )
    }

    /// Horizontal swipe on the header, the calendar grid or the empty state changes month.
    /// The list itself keeps horizontal swipes for the row actions.
    private var monthSwipe: some Gesture {
        PeriodSwipe.gesture(onShift: shiftMonth)
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: delta, to: month) else { return }
        withAnimation { month = next }
    }

    private var defaultDate: Date {
        let calendar = Calendar.current
        if calendar.isDate(month, equalTo: .now, toGranularity: .month) { return .now }
        return calendar.date(byAdding: .hour, value: 12, to: month) ?? month
    }

    // MARK: Actions

    private var service: TransactionService {
        TransactionService(context: context, profileID: profile.id)
    }

    private func delete(_ tx: MoneyTransaction) {
        do {
            try service.delete(tx)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            assertionFailure("Hapus transaksi gagal: \(error)")
        }
    }

    private func duplicate(_ tx: MoneyTransaction) {
        do {
            try service.duplicate(tx, on: .now)
            toastCenter.show("Disalin ke **hari ini**")
        } catch {
            assertionFailure("Duplikat transaksi gagal: \(error)")
        }
    }
}

/// Pinned header shared by the month and year screens: navigator, summary columns and the mode picker.
private struct TransactionListHeader: View {
    let title: String
    let previousLabel: String
    let nextLabel: String
    let summary: MonthSummary
    @Binding var mode: TransactionListMode
    let onShift: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            navigator
            HStack(alignment: .top) {
                SummaryColumn(title: "Pendapatan", amount: summary.income, color: .blue)
                SummaryColumn(title: "Pengeluaran", amount: summary.expense, color: .red)
                SummaryColumn(title: "Total", amount: summary.total, color: .primary)
            }
            Picker("Tampilan", selection: $mode) {
                ForEach(TransactionListMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        // Pinned bar: capped like system bars so accessibility sizes don't fill the screen; the list still scales.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // Opaque so rows scroll beneath it; `.safeAreaBar` blurred the large title.
        .background(Color(.systemGroupedBackground), ignoresSafeAreaEdges: [])
        .contentShape(Rectangle())
        // High priority: the inset sits on the list's scroll view, whose pan would win otherwise.
        .highPriorityGesture(PeriodSwipe.gesture(onShift: onShift))
    }

    private var navigator: some View {
        // Chevrons pinned to the header edges; each one's button fills the space up to the title, so the whole side is tappable.
        HStack(spacing: 8) {
            Button { onShift(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(previousLabel)
            Text(title)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Button { onShift(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(nextLabel)
        }
    }
}

private enum PeriodSwipe {
    static func gesture(onShift: @escaping (Int) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 60, abs(dx) > abs(value.translation.height) * 2 else { return }
                onShift(dx < 0 ? 1 : -1)
            }
    }
}

/// "Bulanan": owns the `@Query` for one profile and year; 12 month rows, newest first.
private struct YearTransactionsView: View {
    let profile: Profile
    @Binding var month: Date
    @Binding var mode: TransactionListMode

    @Environment(FilterState.self) private var filterState
    @Query private var rawTransactions: [MoneyTransaction]

    private var transactions: [MoneyTransaction] { filterState.filter.apply(rawTransactions) }

    init(profile: Profile, month: Binding<Date>, mode: Binding<TransactionListMode>) {
        self.profile = profile
        _month = month
        _mode = mode
        let interval = TransactionQueries.yearInterval(containing: month.wrappedValue, calendar: .current)
        _rawTransactions = Query(TransactionQueries.descriptor(profileID: profile.id, interval: interval))
    }

    var body: some View {
        MonthlyYearView(rows: rows, onSelect: select)
            .safeAreaInset(edge: .top, spacing: 0) {
                TransactionListHeader(
                    title: String(Calendar.current.component(.year, from: month)),
                    previousLabel: "Tahun sebelumnya",
                    nextLabel: "Tahun berikutnya",
                    summary: TransactionSummary.month(transactions),
                    mode: $mode,
                    onShift: shiftYear
                )
            }
    }

    /// Newest month first; months after the current one are hidden in the current year.
    private var rows: [MonthRow] {
        let calendar = Calendar.current
        let all = TransactionSummary.monthRows(transactions, year: month, calendar: calendar)
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let isCurrentYear = calendar.isDate(month, equalTo: .now, toGranularity: .year)
        return all
            .filter { !isCurrentYear || $0.id <= thisMonth }
            .sorted { $0.id > $1.id }
    }

    private func select(_ row: MonthRow) {
        month = row.id
        mode = .daily
    }

    private func shiftYear(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .year, value: delta, to: month) else { return }
        withAnimation { month = next }
    }
}

private struct SummaryColumn: View {
    let title: String
    let amount: Decimal
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(MoneyFormatter.string(amount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

enum MonthFormat {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
        return formatter
    }()

    /// "Okt 2026".
    static func string(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
