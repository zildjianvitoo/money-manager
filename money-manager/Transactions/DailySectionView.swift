import SwiftUI
import MoneyCore

/// One day in the "Harian" list: date header with the day's totals, then its transactions.
struct DailySectionView: View {
    let section: DaySection
    let onOpen: (MoneyTransaction) -> Void
    let onDelete: (MoneyTransaction) -> Void
    let onDuplicate: (MoneyTransaction) -> Void

    var body: some View {
        Section {
            ForEach(section.transactions) { tx in
                Button { onOpen(tx) } label: {
                    TransactionRow(transaction: tx)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button("Hapus", systemImage: "trash", role: .destructive) { onDelete(tx) }
                }
                .swipeActions(edge: .leading) {
                    Button("Duplikat", systemImage: "plus.square.on.square") { onDuplicate(tx) }
                        .tint(.indigo)
                }
            }
        } header: {
            DayHeader(section: section)
        }
    }
}

private struct DayHeader: View {
    let section: DaySection

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        layout {
            HStack(spacing: 8) {
                Text(section.id, format: .dateTime.day())
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text(Self.weekdayFormatter.string(from: section.id))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor, in: RoundedRectangle(cornerRadius: 4))
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            HStack(spacing: 8) {
                Text(MoneyFormatter.string(section.income))
                    .foregroundStyle(.blue)
                Text(MoneyFormatter.string(section.expense))
                    .foregroundStyle(.red)
            }
        }
        .font(.footnote.weight(.medium))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .textCase(nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isHeader)
    }

    private var badgeColor: Color {
        switch Calendar.current.component(.weekday, from: section.id) {
        case 7: .blue
        case 1: .red
        default: .gray
        }
    }

    private var accessibilityText: String {
        let date = section.id.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "id_ID")))
        return "\(date), pendapatan \(MoneyFormatter.string(section.income)), pengeluaran \(MoneyFormatter.string(section.expense))"
    }
}

private struct TransactionRow: View {
    let transaction: MoneyTransaction

    private var topCategory: MoneyCategory? {
        transaction.category?.parent ?? transaction.category
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Stacked so nothing truncates at accessibility sizes.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(leadingEmoji).accessibilityHidden(true)
                        Text(title)
                    }
                    Text("\(topCategoryName) · \(assetText)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    amount
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
                        HStack(spacing: 4) {
                            Text(topCategoryName)
                            Text("·")
                            Text(assetText)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    amount
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var amount: some View {
        Text(MoneyFormatter.string(transaction.amount))
            .font(.body.weight(.medium))
            .monospacedDigit()
            .italic(transaction.type == .adjustment)
            .foregroundStyle(amountColor)
    }

    private var leadingEmoji: String {
        switch transaction.type {
        case .transfer: "🔁"
        case .adjustment: "⚖️"
        case .income, .expense: topCategory.map(\.emoji).flatMap { $0.isEmpty ? nil : $0 } ?? "•"
        }
    }

    private var topCategoryName: String {
        switch transaction.type {
        case .transfer: "Transfer"
        case .adjustment: "Penyesuaian"
        case .income, .expense: topCategory?.name ?? "Tanpa kategori"
        }
    }

    /// The note, or the (sub)category name when the note is empty.
    private var title: String {
        let note = transaction.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { return note }
        return transaction.category?.name ?? topCategoryName
    }

    private var assetText: String {
        let from = transaction.asset?.name ?? "-"
        guard transaction.type == .transfer else { return from }
        return "\(from) → \(transaction.toAsset?.name ?? "-")"
    }

    private var amountColor: Color {
        switch transaction.type {
        case .income: .blue
        case .expense: .red
        case .transfer, .adjustment: .secondary
        }
    }
}
