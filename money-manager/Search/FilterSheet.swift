import SwiftUI
import SwiftData
import MoneyCore

/// Edits the shared filter: type, category, asset and amount range.
struct FilterSheet: View {
    let profileID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(FilterState.self) private var filterState
    @Query private var categories: [MoneyCategory]
    @Query private var assets: [AssetAccount]

    @State private var minText = ""
    @State private var maxText = ""

    init(profileID: UUID) {
        self.profileID = profileID
        _categories = Query(
            filter: #Predicate<MoneyCategory> { $0.profileID == profileID && !$0.isHidden },
            sort: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        _assets = Query(
            filter: #Predicate<AssetAccount> { $0.profileID == profileID && !$0.isArchived },
            sort: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
    }

    var body: some View {
        @Bindable var state = filterState
        NavigationStack {
            Form {
                Section("Jenis") {
                    typeRow("Pendapatan", .income, $state.filter)
                    typeRow("Pengeluaran", .expense, $state.filter)
                    typeRow("Transfer", .transfer, $state.filter)
                }
                Section {
                    NavigationLink {
                        categoryPicker
                    } label: {
                        LabeledContent("Kategori", value: summary(count: state.filter.categoryIDs.count))
                    }
                    NavigationLink {
                        assetPicker
                    } label: {
                        LabeledContent("Aset", value: summary(count: state.filter.assetIDs.count))
                    }
                } footer: {
                    Text("Memilih kategori induk ikut menyertakan subkategorinya. Transfer tidak punya kategori, jadi tidak muncul bila kategori dipilih.")
                }
                Section("Nominal") {
                    TextField("Minimal", text: $minText).keyboardType(.decimalPad)
                    TextField("Maksimal", text: $maxText).keyboardType(.decimalPad)
                }
                if state.filter.isActive {
                    Section {
                        Button("Hapus semua filter", role: .destructive) {
                            filterState.filter = TransactionFilter()
                            minText = ""
                            maxText = ""
                        }
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Selesai") { dismiss() } }
            }
            .onAppear {
                minText = filterState.filter.minAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
                maxText = filterState.filter.maxAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
            }
            .onChange(of: minText) { filterState.filter.minAmount = FlexibleNumber.parse(minText) }
            .onChange(of: maxText) { filterState.filter.maxAmount = FlexibleNumber.parse(maxText) }
        }
        .presentationDetents([.medium, .large])
    }

    private func summary(count: Int) -> String { count == 0 ? "Semua" : "\(count) dipilih" }

    private func typeRow(_ title: String, _ type: TransactionType, _ filter: Binding<TransactionFilter>) -> some View {
        Button {
            if filter.wrappedValue.types.contains(type) {
                filter.wrappedValue.types.remove(type)
            } else {
                filter.wrappedValue.types.insert(type)
            }
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if filter.wrappedValue.types.contains(type) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
        }
        .accessibilityAddTraits(filter.wrappedValue.types.contains(type) ? .isSelected : [])
    }

    private var categoryPicker: some View {
        @Bindable var state = filterState
        let top = categories.filter { $0.parent == nil }
        return List {
            ForEach([CategoryKind.expense, .income], id: \.self) { kind in
                let rows = top.filter { $0.kind == kind }
                if !rows.isEmpty {
                    Section(kind == .expense ? "Pengeluaran" : "Pendapatan") {
                        ForEach(rows) { category in
                            multiSelectRow(
                                title: "\(category.emoji) \(category.name)",
                                isOn: state.filter.categoryIDs.contains(category.id)
                            ) { toggle(category.id, in: &state.filter.categoryIDs) }
                            ForEach((category.children ?? []).filter { !$0.isHidden }.sorted { $0.sortOrder < $1.sortOrder }) { sub in
                                multiSelectRow(
                                    title: "\(sub.emoji) \(sub.name)",
                                    isOn: state.filter.categoryIDs.contains(sub.id)
                                ) { toggle(sub.id, in: &state.filter.categoryIDs) }
                                .padding(.leading, 20)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Kategori")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var assetPicker: some View {
        @Bindable var state = filterState
        return List(assets) { asset in
            multiSelectRow(
                title: "\(asset.group.emoji) \(asset.name)",
                isOn: state.filter.assetIDs.contains(asset.id)
            ) { toggle(asset.id, in: &state.filter.assetIDs) }
        }
        .navigationTitle("Aset")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ id: UUID, in set: inout Set<UUID>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func multiSelectRow(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if isOn { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
