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

    private var activeProfile: Profile? {
        profiles.first { $0.id == store.activeProfileID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let profile = activeProfile {
                    MonthTransactionsView(
                        profile: profile,
                        month: $month,
                        mode: $mode,
                        onOpen: { formRoute = $0 }
                    )
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Transaksi")
            .navigationBarTitleDisplayMode(.large)
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

    /// Now when viewing the current month, otherwise noon on the 1st of the viewed month.
    private var defaultDate: Date {
        let calendar = Calendar.current
        if calendar.isDate(month, equalTo: .now, toGranularity: .month) { return .now }
        return calendar.date(byAdding: .hour, value: 12, to: month) ?? month
    }
}

/// Owns the `@Query` for one profile and month; rebuilt whenever either changes.
private struct MonthTransactionsView: View {
    let profile: Profile
    @Binding var month: Date
    @Binding var mode: TransactionListMode
    let onOpen: (TransactionFormRoute) -> Void

    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toastCenter
    @Query private var transactions: [MoneyTransaction]
    @State private var pendingDelete: MoneyTransaction?

    init(profile: Profile, month: Binding<Date>, mode: Binding<TransactionListMode>, onOpen: @escaping (TransactionFormRoute) -> Void) {
        self.profile = profile
        _month = month
        _mode = mode
        self.onOpen = onOpen
        let interval = TransactionQueries.monthInterval(containing: month.wrappedValue, calendar: .current)
        _transactions = Query(TransactionQueries.descriptor(profileID: profile.id, interval: interval))
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
                    .contentShape(Rectangle())
                    .gesture(monthSwipe)
            } else {
                dailyList
            }
        case .calendar, .monthly:
            ContentUnavailableView("Segera hadir", systemImage: "calendar", description: Text("Tampilan \(mode.rawValue) sedang dibuat."))
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

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Belum ada transaksi", systemImage: "tray")
        } description: {
            Text("di \(MonthFormat.string(month))")
        } actions: {
            Button("Catat transaksi") { onOpen(.create(defaultDate: defaultDate)) }
                .buttonStyle(.bordered)
        }
    }

    // MARK: Header

    private var header: some View {
        let summary = TransactionSummary.month(transactions)
        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(Color(hex: profile.colorHex))
                    .frame(width: 4, height: 18)
                    .accessibilityHidden(true)
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                monthNavigator
            }
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
        .highPriorityGesture(monthSwipe)
    }

    private var monthNavigator: some View {
        HStack(spacing: 4) {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Bulan sebelumnya")
            Text(MonthFormat.string(month))
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Bulan berikutnya")
        }
    }

    /// Horizontal swipe on the header or the empty state changes month.
    /// The list itself keeps horizontal swipes for the row actions.
    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 60, abs(dx) > abs(value.translation.height) * 2 else { return }
                shiftMonth(dx < 0 ? 1 : -1)
            }
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
