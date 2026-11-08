import SwiftUI
import SwiftData
import MoneyCore

/// Free-text search over the active profile's notes and descriptions, across all periods.
struct SearchView: View {
    let profileID: UUID

    @Environment(\.dismiss) private var dismiss
    @Query private var all: [MoneyTransaction]
    @State private var query = ""
    @State private var formRoute: TransactionFormRoute?

    init(profileID: UUID) {
        self.profileID = profileID
        _all = Query(FetchDescriptor<MoneyTransaction>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        return formatter
    }()

    private var results: [MoneyTransaction] { TransactionSearch.search(all, query: query) }

    var body: some View {
        let results = results
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView("Cari transaksi", systemImage: "magnifyingglass",
                                           description: Text("Ketik kata dari catatan atau deskripsi."))
                        .listRowBackground(Color.clear)
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                } else {
                    let summary = TransactionSummary.month(results)
                    Section {
                        HStack {
                            Text("\(results.count) hasil").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(MoneyFormatter.string(summary.income)).foregroundStyle(.blue)
                            Text(MoneyFormatter.string(summary.expense)).foregroundStyle(.red)
                        }
                        .font(.footnote)
                        .monospacedDigit()
                        .accessibilityElement(children: .combine)
                    }
                    ForEach(TransactionSummary.daySections(results, calendar: .current)) { section in
                        Section {
                            ForEach(section.transactions) { tx in
                                Button { formRoute = .edit(tx) } label: { TransactionRow(transaction: tx) }
                                    .buttonStyle(.plain)
                            }
                        } header: {
                            Text(Self.dayFormatter.string(from: section.id))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Cari")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Catatan atau deskripsi")
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } }
            }
            .sheet(item: $formRoute) { route in
                switch route {
                case .create(let date): TransactionFormView(mode: .create(defaultDate: date))
                case .edit(let tx): TransactionFormView(mode: .edit(tx))
                }
            }
        }
    }
}
