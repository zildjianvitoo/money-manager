import SwiftUI
import SwiftData
import MoneyCore

private let gridColumns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

/// Bottom sheet grid of one profile's categories. Tapping a category with
/// subcategories drills into them, with a "{induk} saja" option.
struct CategoryPickerSheet: View {
    let profileID: UUID
    let kind: CategoryKind
    let selectedID: UUID?
    let onPick: (MoneyCategory) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var parent: MoneyCategory?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 10) {
                    if let parent {
                        PickerTile(emoji: parent.emoji, title: "\(parent.name) saja", isSelected: parent.id == selectedID) {
                            onPick(parent)
                        }
                        ForEach(visibleChildren(of: parent)) { child in
                            PickerTile(emoji: child.emoji.isEmpty ? parent.emoji : child.emoji, title: child.name, isSelected: child.id == selectedID) {
                                onPick(child)
                            }
                        }
                    } else {
                        ForEach(topLevel) { category in
                            PickerTile(
                                emoji: category.emoji,
                                title: category.name,
                                isSelected: category.id == selectedID || category.children?.contains { $0.id == selectedID } == true,
                                showsChevron: !visibleChildren(of: category).isEmpty
                            ) {
                                if visibleChildren(of: category).isEmpty {
                                    onPick(category)
                                } else {
                                    withAnimation { parent = category }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(parent?.name ?? "Kategori")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if parent != nil {
                        Button("Kembali", systemImage: "chevron.left") { withAnimation { parent = nil } }
                    } else {
                        Button("Tutup") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var topLevel: [MoneyCategory] {
        (try? CategoryService(context: context, profileID: profileID).topLevel(kind: kind, includeHidden: false)) ?? []
    }

    private func visibleChildren(of category: MoneyCategory) -> [MoneyCategory] {
        (category.children ?? [])
            .filter { !$0.isHidden && $0.profileID == profileID }
            .sorted { $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder : $0.name < $1.name }
    }
}

/// Bottom sheet grid of one profile's active assets.
struct AssetPickerSheet: View {
    let profileID: UUID
    let title: String
    let selectedID: UUID?
    let onPick: (AssetAccount) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 10) {
                    ForEach(assets) { asset in
                        PickerTile(symbol: symbol(for: asset.group), title: asset.name, isSelected: asset.id == selectedID) {
                            onPick(asset)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var assets: [AssetAccount] {
        (try? AssetService(context: context, profileID: profileID).assets(includeArchived: false)) ?? []
    }

    private func symbol(for group: AssetGroup) -> String {
        switch group {
        case .cash: "banknote"
        case .bank: "building.columns"
        case .eWallet: "iphone"
        case .creditCard: "creditcard"
        case .investment: "chart.line.uptrend.xyaxis"
        case .other: "wallet.bifold"
        }
    }
}

private struct PickerTile: View {
    var emoji: String = ""
    var symbol: String?
    let title: String
    let isSelected: Bool
    var showsChevron = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let symbol {
                        Image(systemName: symbol).font(.title2)
                    } else {
                        Text(emoji.isEmpty ? "•" : emoji).font(.title)
                    }
                }
                .frame(height: 32)
                .accessibilityHidden(true)
                HStack(spacing: 2) {
                    Text(title)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if showsChevron {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .top)
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(.tint, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(showsChevron ? "Punya subkategori" : "")
    }
}
