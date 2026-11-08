import SwiftUI
import SwiftData
import MoneyCore

/// Favorites of one profile: tap to fill the transaction form, swipe to delete.
struct FavoritePickerSheet: View {
    let profileID: UUID
    let onPick: (FavoriteTemplate) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var favorites: [FavoriteTemplate]
    @Query private var categories: [MoneyCategory]
    @Query private var assets: [AssetAccount]

    init(profileID: UUID, onPick: @escaping (FavoriteTemplate) -> Void) {
        self.profileID = profileID
        self.onPick = onPick
        _favorites = Query(filter: #Predicate<FavoriteTemplate> { $0.profileID == profileID },
                           sort: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        _categories = Query(filter: #Predicate<MoneyCategory> { $0.profileID == profileID })
        _assets = Query(filter: #Predicate<AssetAccount> { $0.profileID == profileID })
    }

    var body: some View {
        NavigationStack {
            List {
                if favorites.isEmpty {
                    ContentUnavailableView("Belum ada favorit", systemImage: "star",
                                           description: Text("Buka transaksi, lalu pilih “Simpan sebagai favorit”."))
                        .listRowBackground(Color.clear)
                }
                ForEach(favorites) { favorite in
                    Button {
                        onPick(favorite)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(favorite.name).font(.headline).foregroundStyle(.primary)
                                Spacer()
                                if let amount = favorite.amount {
                                    Text(MoneyFormatter.string(amount)).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            Text(detail(favorite)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .swipeActions {
                        Button("Hapus", role: .destructive) { delete(favorite) }
                    }
                }
            }
            .navigationTitle("Favorit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func detail(_ favorite: FavoriteTemplate) -> String {
        let category = categories.first { $0.id == favorite.categoryID }?.name
        let asset = assets.first { $0.id == favorite.assetID }?.name
        let to = assets.first { $0.id == favorite.toAssetID }?.name
        let kind: String = switch favorite.type {
        case .income: "Pendapatan"
        case .expense, .adjustment: "Pengeluaran"
        case .transfer: "Transfer"
        }
        let route = favorite.type == .transfer ? [asset, to].compactMap { $0 }.joined(separator: " → ") : [category, asset].compactMap { $0 }.joined(separator: " · ")
        return [kind, route, favorite.note].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func delete(_ favorite: FavoriteTemplate) {
        try? FavoriteService(context: context, profileID: profileID).delete(favorite)
    }
}
