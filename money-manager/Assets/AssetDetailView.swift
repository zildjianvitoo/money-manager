import SwiftUI
import SwiftData
import MoneyCore

/// One asset: current balance, "Sesuaikan saldo", and its history per month with running balance.
struct AssetDetailView: View {
    let asset: AssetAccount

    @Query private var transactions: [MoneyTransaction]
    @Query(sort: [SortDescriptor(\Profile.sortOrder), SortDescriptor(\Profile.createdAt)]) private var profiles: [Profile]
    @State private var isEditing = false
    @State private var isAdjusting = false

    init(asset: AssetAccount) {
        self.asset = asset
        let profileID = asset.profileID
        _transactions = Query(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.profileID == profileID }))
    }

    private var balance: Decimal {
        BalanceCalculator.balance(of: asset, transactions: transactions)
    }

    private var colorHex: String {
        profiles.first { $0.id == asset.profileID }?.colorHex ?? "#FF6B5A"
    }

    var body: some View {
        let months = Self.monthSections(for: asset, transactions: transactions)
        List {
            Section {
                balanceHeader
            }
            if months.isEmpty {
                Section {
                    Text("Belum ada transaksi di aset ini.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(months) { month in
                Section {
                    ForEach(month.rows) { HistoryRow(row: $0, asset: asset) }
                } header: {
                    MonthHeader(section: month)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(asset.name)
        .navigationSubtitle(asset.group.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Ubah", systemImage: "pencil") { isEditing = true }
                    .accessibilityLabel("Ubah aset")
            }
        }
        .sheet(isPresented: $isEditing) {
            AssetFormView(mode: .edit(asset))
        }
        .sheet(isPresented: $isAdjusting) {
            AdjustBalanceSheet(asset: asset, currentBalance: balance, colorHex: colorHex)
        }
    }

    private var balanceHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Saldo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(MoneyFormatter.string(balance))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(balance < 0 ? .red : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if asset.isArchived || !asset.includeInTotal {
                    Text([asset.isArchived ? "Diarsipkan" : nil, asset.includeInTotal ? nil : "Tidak masuk total"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Button("Sesuaikan saldo", systemImage: "slider.horizontal.3") { isAdjusting = true }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    // MARK: History

    private struct HistoryEntry: Identifiable {
        let transaction: MoneyTransaction
        /// How much this transaction moved the asset's balance.
        let delta: Decimal
        let balanceAfter: Decimal
        var id: UUID { transaction.id }
    }

    private struct MonthSection: Identifiable {
        let id: Date
        /// Newest first.
        let rows: [HistoryEntry]
        let net: Decimal
    }

    /// Months newest first, rows newest first within a month.
    private static func monthSections(for asset: AssetAccount, transactions: [MoneyTransaction]) -> [MonthSection] {
        let calendar = Calendar.current
        var previous = asset.initialBalance
        var byMonth: [Date: [HistoryEntry]] = [:]
        for item in BalanceCalculator.runningBalances(of: asset, transactions: transactions) {
            let entry = HistoryEntry(
                transaction: item.transaction, delta: item.balanceAfter - previous, balanceAfter: item.balanceAfter
            )
            previous = item.balanceAfter
            let month = calendar.dateInterval(of: .month, for: item.transaction.date)?.start ?? item.transaction.date
            byMonth[month, default: []].append(entry)
        }
        return byMonth
            .map { MonthSection(id: $0.key, rows: $0.value.reversed(), net: $0.value.reduce(0) { $0 + $1.delta }) }
            .sorted { $0.id > $1.id }
    }

    private struct MonthHeader: View {
        let section: MonthSection

        var body: some View {
            HStack {
                Text(MonthFormat.string(section.id))
                Spacer()
                Text(Self.signed(section.net))
                    .monospacedDigit()
            }
            .font(.footnote.weight(.semibold))
            .textCase(nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(MonthFormat.string(section.id)), perubahan \(Self.signed(section.net))")
            .accessibilityAddTraits(.isHeader)
        }

        private static func signed(_ amount: Decimal) -> String {
            amount > 0 ? "+" + MoneyFormatter.string(amount) : MoneyFormatter.string(amount)
        }
    }

    private struct HistoryRow: View {
        let row: HistoryEntry
        let asset: AssetAccount

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        private static let dayFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "id_ID")
            formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
            return formatter
        }()

        private var transaction: MoneyTransaction { row.transaction }
        private var topCategory: MoneyCategory? { transaction.category?.parent ?? transaction.category }

        var body: some View {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    // Stacked so nothing truncates at accessibility sizes.
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(leadingEmoji).accessibilityHidden(true)
                            Text(title)
                        }
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        delta
                        balanceAfter
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 12) {
                        Text(leadingEmoji)
                            .font(.title3)
                            .frame(width: 32)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.body)
                                .lineLimit(1)
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            delta
                            balanceAfter
                        }
                        .lineLimit(1)
                        .layoutPriority(1)
                    }
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }

        private var delta: some View {
            Text(row.delta > 0 ? "+" + MoneyFormatter.string(row.delta) : MoneyFormatter.string(row.delta))
                .font(.body.weight(.medium))
                .monospacedDigit()
                .italic(transaction.type == .adjustment)
                .foregroundStyle(deltaColor)
        }

        private var balanceAfter: some View {
            Text("Saldo \(MoneyFormatter.string(row.balanceAfter))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }

        private var leadingEmoji: String {
            switch transaction.type {
            case .transfer: "🔁"
            case .adjustment: "⚖️"
            case .income, .expense: topCategory.map(\.emoji).flatMap { $0.isEmpty ? nil : $0 } ?? "•"
            }
        }

        /// The note, or the (sub)category name when the note is empty.
        private var title: String {
            let note = transaction.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { return note }
            switch transaction.type {
            case .transfer: return "Transfer"
            case .adjustment: return "Penyesuaian"
            case .income, .expense: return transaction.category?.name ?? "Tanpa kategori"
            }
        }

        private var subtitle: String {
            let day = Self.dayFormatter.string(from: transaction.date)
            switch transaction.type {
            case .transfer:
                if transaction.asset?.id == asset.id { return "\(day) · Ke \(transaction.toAsset?.name ?? "-")" }
                return "\(day) · Dari \(transaction.asset?.name ?? "-")"
            case .adjustment:
                return "\(day) · Penyesuaian"
            case .income, .expense:
                return "\(day) · \(topCategory?.name ?? "Tanpa kategori")"
            }
        }

        private var deltaColor: Color {
            switch transaction.type {
            case .income: .blue
            case .expense: .red
            case .transfer, .adjustment: .secondary
            }
        }
    }
}

/// Enter the real balance, see the difference, confirm, and let `AssetService` record the adjustment.
private struct AdjustBalanceSheet: View {
    let asset: AssetAccount
    let currentBalance: Decimal
    let colorHex: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var expression = ""
    @State private var isKeypadActive = true
    @State private var showsError = false
    @State private var isConfirming = false

    private var result: Result<Decimal, AmountParserError> {
        BalanceExpression.evaluate(expression)
    }

    /// `actual − current`, or `nil` while the expression is empty or invalid.
    private var difference: Decimal? {
        guard !expression.isEmpty, case .success(let actual) = result else { return nil }
        return actual - currentBalance
    }

    private var canAdjust: Bool {
        guard let difference else { return false }
        return difference != 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Saldo saat ini") {
                        Text(MoneyFormatter.string(currentBalance))
                            .monospacedDigit()
                    }
                    BalanceAmountRow(
                        title: "Saldo sebenarnya",
                        expression: expression,
                        result: result,
                        isActive: isKeypadActive,
                        showsError: showsError,
                        onTap: { isKeypadActive = true }
                    )
                    if let difference {
                        LabeledContent("Selisih") {
                            Text(difference == 0 ? "Sudah sesuai" : Self.signed(difference))
                                .monospacedDigit()
                                .foregroundStyle(difference == 0 ? .secondary : .primary)
                        }
                    }
                } footer: {
                    Text("Selisih dicatat sebagai transaksi Penyesuaian. Nilainya tidak masuk Pendapatan, Pengeluaran, atau Statistik.")
                }
            }
            .navigationTitle("Sesuaikan saldo")
            .navigationSubtitle(asset.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sesuaikan") { evaluate(confirming: true) }
                        .disabled(!canAdjust)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isKeypadActive {
                    CalculatorKeypad(
                        expression: $expression,
                        onEquals: { evaluate(confirming: false) },
                        onConfirm: { evaluate(confirming: true) }
                    )
                    .frame(maxWidth: .infinity)
                    .background(.background)
                    .transition(.move(edge: .bottom))
                    .animation(.snappy, value: isKeypadActive)
                }
            }
            .onChange(of: expression) { showsError = false }
            .confirmationDialog("Sesuaikan saldo \(asset.name)?", isPresented: $isConfirming, titleVisibility: .visible) {
                Button("Sesuaikan") { adjust() }
            } message: {
                if let difference, case .success(let actual) = result {
                    Text("Saldo berubah dari \(MoneyFormatter.string(currentBalance)) menjadi \(MoneyFormatter.string(actual)), selisih \(Self.signed(difference)).")
                }
            }
        }
        .tint(Color(hex: colorHex))
        .presentationDetents([.large])
        .interactiveDismissDisabled(!expression.isEmpty)
    }

    private static func signed(_ amount: Decimal) -> String {
        amount > 0 ? "+" + MoneyFormatter.string(amount) : MoneyFormatter.string(amount)
    }

    /// `=` just evaluates; `Ya` and the toolbar button also ask for confirmation when there is a difference.
    private func evaluate(confirming: Bool) {
        guard !expression.isEmpty else { return }
        guard case .success(let value) = result else {
            showsError = true
            return
        }
        expression = BalanceExpression.expression(for: value, keepingZero: true)
        guard confirming else { return }
        isKeypadActive = false
        isConfirming = canAdjust
    }

    private func adjust() {
        guard case .success(let actual) = result else { return }
        do {
            try AssetService(context: context, profileID: asset.profileID).adjustBalance(of: asset, to: actual, on: .now)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            assertionFailure("Sesuaikan saldo gagal: \(error)")
            return
        }
        dismiss()
    }
}
