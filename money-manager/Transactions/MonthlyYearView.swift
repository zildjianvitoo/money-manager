import SwiftUI
import MoneyCore

/// "Bulanan" list: one row per month with income, expense and total. Tapping a row opens that month.
struct MonthlyYearView: View {
    let rows: [MonthRow]
    let onSelect: (MonthRow) -> Void

    var body: some View {
        List {
            ForEach(rows) { row in
                Button { onSelect(row) } label: {
                    MonthRowView(row: row)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct MonthRowView: View {
    let row: MonthRow

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.dateFormat = "MMMM"
        return formatter
    }()

    private var name: String { Self.formatter.string(from: row.id) }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            Text(name)
                .font(.body.weight(.semibold))
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                HStack(spacing: 8) {
                    Text(MoneyFormatter.string(row.income)).foregroundStyle(.blue)
                    Text(MoneyFormatter.string(row.expense)).foregroundStyle(.red)
                }
                .font(.footnote.weight(.medium))
                Text(MoneyFormatter.string(row.total))
                    .font(.body.weight(.medium))
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), pendapatan \(MoneyFormatter.string(row.income)), pengeluaran \(MoneyFormatter.string(row.expense)), total \(MoneyFormatter.string(row.total))")
        .accessibilityAddTraits(.isButton)
    }
}
