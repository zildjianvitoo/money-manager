import SwiftUI
import SwiftData
import MoneyCore

/// What the category sheet opens with. Routes carry IDs, not models, so a sheet
/// never reads a category that was just deleted.
private enum CategoryRoute: Identifiable {
    case create(CategoryKind)
    case edit(UUID)

    var id: String {
        switch self {
        case .create(let kind): "create-\(kind.rawValue)"
        case .edit(let id): id.uuidString
        }
    }
}

/// Manages the active profile's categories: Pengeluaran | Pendapatan, reorder, hide, edit and delete.
struct CategoryManagementView: View {
    @Environment(ProfileStore.self) private var store

    var body: some View {
        Group {
            if let profileID = store.activeProfileID {
                ProfileCategoriesView(profileID: profileID)
                    .id(profileID)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Kategori")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Owns the `@Query` for one profile; rebuilt when the active profile changes.
private struct ProfileCategoriesView: View {
    let profileID: UUID

    @Environment(\.modelContext) private var context
    @Query private var categories: [MoneyCategory]
    @Query private var profiles: [Profile]

    @State private var kind: CategoryKind = .expense
    @State private var editMode: EditMode = .inactive
    @State private var route: CategoryRoute?
    @State private var deleting: CategoryDeletion?
    @State private var errorMessage: String?

    init(profileID: UUID) {
        self.profileID = profileID
        _categories = Query(filter: #Predicate<MoneyCategory> { $0.profileID == profileID })
        _profiles = Query(filter: #Predicate<Profile> { $0.id == profileID })
    }

    private var service: CategoryService { CategoryService(context: context, profileID: profileID) }

    private var tintColor: Color { Color(hex: profiles.first?.colorHex ?? "#FF6B5A") }

    /// Same order as `CategoryService.topLevel`, so `onMove` offsets match the service's list.
    private var rows: [MoneyCategory] {
        categories.filter { $0.parent == nil && $0.kind == kind }.inDisplayOrder()
    }

    var body: some View {
        List {
            Section {
                Picker("Jenis", selection: $kind) {
                    Text("Pengeluaran").tag(CategoryKind.expense)
                    Text("Pendapatan").tag(CategoryKind.income)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(rows) { category in
                    CategoryRow(category: category, showsSubcategoryCount: true) { route = .edit(category.id) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            hideButton(for: category)
                            Button("Hapus", systemImage: "trash") { deleting = CategoryDeletion(id: category.id) }
                                .tint(.red)
                        }
                        .contextMenu {
                            Button("Ubah", systemImage: "pencil") { route = .edit(category.id) }
                            hideButton(for: category)
                            Button("Hapus", systemImage: "trash", role: .destructive) { deleting = CategoryDeletion(id: category.id) }
                        }
                }
                .onMove(perform: move)
            } footer: {
                Text("Kategori yang disembunyikan tidak muncul saat mencatat, tetapi transaksi lamanya tetap tampil.")
            }
        }
        .environment(\.editMode, $editMode)
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView("Belum ada kategori", systemImage: "square.grid.2x2")
            }
        }
        .toolbar {
            if rows.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "Selesai" : "Urutkan") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Tambah kategori", systemImage: "plus") { route = .create(kind) }
                    .accessibilityLabel("Tambah kategori")
            }
        }
        .sheet(item: $route) { route in
            switch route {
            case .create(let kind):
                CategoryFormView(profileID: profileID, mode: .create(kind: kind, parent: nil))
                    .tint(tintColor)
            case .edit(let id):
                if let category = categories.first(where: { $0.id == id }) {
                    CategoryFormView(profileID: profileID, mode: .edit(category))
                        .tint(tintColor)
                }
            }
        }
        .sheet(item: $deleting) { deletion in
            CategoryDeleteSheet(profileID: profileID, categoryID: deletion.id)
                .tint(tintColor)
        }
        .alert("Gagal mengubah kategori", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func hideButton(for category: MoneyCategory) -> some View {
        Button(
            category.isHidden ? "Tampilkan" : "Sembunyikan",
            systemImage: category.isHidden ? "eye" : "eye.slash"
        ) {
            do {
                try service.setHidden(category, !category.isHidden)
            } catch {
                errorMessage = "Kategori tidak bisa diubah. Coba lagi."
            }
        }
        .tint(.orange)
    }

    private func move(from source: IndexSet, to destination: Int) {
        do {
            try service.move(kind: kind, parent: nil, from: source, to: destination)
        } catch {
            errorMessage = "Urutan kategori tidak bisa disimpan. Coba lagi."
        }
    }
}

/// One category line: emoji, name, a subtitle for hidden state or subcategory count, and a chevron.
/// Hidden categories stay listed but dimmed.
struct CategoryRow: View {
    let category: MoneyCategory
    var showsSubcategoryCount = false
    let action: () -> Void

    private var subtitle: String? {
        var parts: [String] = []
        if category.isHidden { parts.append("Disembunyikan") }
        let count = category.children?.count ?? 0
        if showsSubcategoryCount, count > 0 { parts.append("\(count) subkategori") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(category.emoji.isEmpty ? "•" : category.emoji)
                    .font(.title2)
                    .frame(minWidth: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name).foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if category.isHidden {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(category.isHidden ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ubah kategori")
    }
}

extension Sequence where Element == MoneyCategory {
    /// `sortOrder`, then name: the order `CategoryService` uses for siblings.
    func inDisplayOrder() -> [MoneyCategory] {
        sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name < $1.name
        }
    }
}
