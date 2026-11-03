import SwiftUI
import SwiftData
import MoneyCore

/// What the subcategory sheet opens with.
private enum SubcategoryRoute: Identifiable {
    case create
    case edit(MoneyCategory)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let category): category.id.uuidString
        }
    }
}

/// Add or edit a category or subcategory: name and emoji. Editing a top-level
/// category also manages its subcategories (add, rename, reorder, hide, delete);
/// those changes save immediately, name and emoji save with "Simpan".
struct CategoryFormView: View {
    enum Mode {
        case create(kind: CategoryKind, parent: MoneyCategory?)
        case edit(MoneyCategory)
    }

    let profileID: UUID
    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @State private var subEditMode: EditMode = .inactive
    @State private var subRoute: SubcategoryRoute?
    @State private var deleting: CategoryDeletion?
    @State private var errorMessage: String?

    init(profileID: UUID, mode: Mode) {
        self.profileID = profileID
        self.mode = mode
        switch mode {
        case .create(_, let parent):
            _name = State(initialValue: "")
            // Subcategories fall back to their parent's emoji when empty.
            _emoji = State(initialValue: parent == nil ? "🏷️" : "")
        case .edit(let category):
            _name = State(initialValue: category.name)
            _emoji = State(initialValue: category.emoji)
        }
    }

    // MARK: Derived

    private var service: CategoryService { CategoryService(context: context, profileID: profileID) }

    private var editedCategory: MoneyCategory? {
        if case .edit(let category) = mode { category } else { nil }
    }

    /// The parent this form's category belongs to (or will belong to), if any.
    private var parent: MoneyCategory? {
        switch mode {
        case .create(_, let parent): parent
        case .edit(let category): category.parent
        }
    }

    private var kind: CategoryKind {
        switch mode {
        case .create(let kind, _): kind
        case .edit(let category): category.kind
        }
    }

    /// Only a saved top-level category can hold subcategories.
    private var managedParent: MoneyCategory? {
        guard let category = editedCategory, category.parent == nil else { return nil }
        return category
    }

    private var title: String {
        let isSub = parent != nil
        return switch mode {
        case .create: isSub ? "Subkategori Baru" : "Kategori Baru"
        case .edit: isSub ? "Ubah Subkategori" : "Ubah Kategori"
        }
    }

    private func subcategories(of category: MoneyCategory) -> [MoneyCategory] {
        (category.children ?? []).filter { $0.profileID == profileID }.inDisplayOrder()
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nama", text: $name)
                        .textInputAutocapitalization(.words)
                    LabeledContent("Emoji") {
                        TextField("Emoji", text: $emoji)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: emoji) { _, new in
                                if new.count > 1 { emoji = String(new.suffix(1)) }
                            }
                    }
                } footer: {
                    if case .create(_, nil) = mode {
                        Text("Subkategori bisa ditambahkan setelah kategori disimpan.")
                    }
                }

                if let category = managedParent {
                    subcategorySection(for: category)
                }
            }
            .environment(\.editMode, $subEditMode)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(item: $subRoute) { route in
                switch route {
                case .create:
                    CategoryFormView(profileID: profileID, mode: .create(kind: kind, parent: editedCategory))
                case .edit(let sub):
                    CategoryFormView(profileID: profileID, mode: .edit(sub))
                }
            }
            .sheet(item: $deleting) { deletion in
                CategoryDeleteSheet(profileID: profileID, categoryID: deletion.id)
            }
            .alert("Gagal menyimpan kategori", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Subcategories

    private func subcategorySection(for category: MoneyCategory) -> some View {
        let subs = subcategories(of: category)
        return Section {
            ForEach(subs) { sub in
                CategoryRow(category: sub) { subRoute = .edit(sub) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        hideButton(for: sub)
                        Button("Hapus", systemImage: "trash") { deleting = CategoryDeletion(id: sub.id) }
                            .tint(.red)
                    }
                    .contextMenu {
                        Button("Ubah", systemImage: "pencil") { subRoute = .edit(sub) }
                        hideButton(for: sub)
                        Button("Hapus", systemImage: "trash", role: .destructive) { deleting = CategoryDeletion(id: sub.id) }
                    }
            }
            .onMove { source, destination in
                move(in: category, from: source, to: destination)
            }
            Button {
                subRoute = .create
            } label: {
                Label("Tambah subkategori", systemImage: "plus.circle.fill")
                    .frame(minHeight: 44, alignment: .leading)
            }
        } header: {
            HStack {
                Text("Subkategori")
                Spacer()
                if subs.count > 1 {
                    Button(subEditMode.isEditing ? "Selesai" : "Urutkan") {
                        withAnimation { subEditMode = subEditMode.isEditing ? .inactive : .active }
                    }
                    .font(.subheadline)
                    .textCase(nil)
                    .frame(minHeight: 44)
                }
            }
        }
    }

    private func hideButton(for sub: MoneyCategory) -> some View {
        Button(sub.isHidden ? "Tampilkan" : "Sembunyikan", systemImage: sub.isHidden ? "eye" : "eye.slash") {
            do {
                try service.setHidden(sub, !sub.isHidden)
            } catch {
                errorMessage = "Subkategori tidak bisa diubah. Coba lagi."
            }
        }
        .tint(.orange)
    }

    private func move(in category: MoneyCategory, from source: IndexSet, to destination: Int) {
        do {
            try service.move(kind: category.kind, parent: category, from: source, to: destination)
        } catch {
            errorMessage = "Urutan subkategori tidak bisa disimpan. Coba lagi."
        }
    }

    private func save() {
        do {
            switch mode {
            case .create(let kind, let parent):
                try service.create(name: name, emoji: emoji, kind: kind, parent: parent)
            case .edit(let category):
                try service.rename(category, name: name, emoji: emoji)
            }
            dismiss()
        } catch {
            errorMessage = "Periksa nama kategori lalu coba lagi."
        }
    }
}

/// A category waiting to be deleted. Carries the ID, not the model, so views
/// never read a category after it is gone.
struct CategoryDeletion: Identifiable {
    let id: UUID
}

/// Confirms deleting a category or subcategory. When transactions use it (including
/// those of its subcategories) the user must pick a replacement in the same
/// profile and kind, never the category itself or one of its own subcategories.
struct CategoryDeleteSheet: View {
    let profileID: UUID
    let categoryID: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toastCenter
    @Query private var all: [MoneyCategory]

    @State private var usage: Int?
    @State private var replacementID: UUID?
    @State private var errorMessage: String?

    init(profileID: UUID, categoryID: UUID) {
        self.profileID = profileID
        self.categoryID = categoryID
        _all = Query(filter: #Predicate<MoneyCategory> { $0.profileID == profileID })
    }

    private var service: CategoryService { CategoryService(context: context, profileID: profileID) }

    /// `nil` once the category is deleted, while the sheet is dismissing.
    private var category: MoneyCategory? { all.first { $0.id == categoryID } }

    private var needsReplacement: Bool { (usage ?? 0) > 0 }

    /// Top-level categories of the same kind, each followed by its subcategories, minus this category and its own children.
    private func candidates(for category: MoneyCategory) -> [(category: MoneyCategory, label: String)] {
        let pool = all.filter { $0.kind == category.kind && $0.id != category.id && $0.parent?.id != category.id }
        var result: [(MoneyCategory, String)] = []
        for top in pool.filter({ $0.parent == nil }).inDisplayOrder() {
            result.append((top, top.name))
            for child in pool.filter({ $0.parent?.id == top.id }).inDisplayOrder() {
                result.append((child, "\(top.name) › \(child.name)"))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if let category {
                    form(for: category)
                }
            }
            .navigationTitle("Hapus Kategori")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
            }
            .alert("Gagal menghapus kategori", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if let category { usage = (try? service.usageCount(category)) ?? 0 }
        }
    }

    private func form(for category: MoneyCategory) -> some View {
        let options = candidates(for: category)
        let replacement = options.first { $0.category.id == replacementID }?.category
        let subcategoryCount = category.children?.count ?? 0
        return Form {
            Section {
                LabeledContent("Kategori") {
                    Text(category.emoji.isEmpty ? category.name : "\(category.emoji) \(category.name)")
                }
                if let usage {
                    if usage > 0 {
                        Text("Dipakai di \(usage) transaksi")
                            .foregroundStyle(.red)
                    } else {
                        Text("Belum dipakai di transaksi")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                if subcategoryCount > 0 {
                    Text("\(subcategoryCount) subkategori ikut terhapus.")
                }
            }

            if needsReplacement {
                Section {
                    Picker("Pindahkan ke", selection: $replacementID) {
                        Text("Pilih kategori").tag(UUID?.none)
                        ForEach(options, id: \.category.id) { option in
                            Text(label(for: option)).tag(UUID?.some(option.category.id))
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text("Semua transaksi kategori ini dan subkategorinya dipindah ke kategori pengganti.")
                }
            }

            Section {
                Button("Hapus Kategori", role: .destructive) { delete(category, replacement: replacement) }
                    .frame(minHeight: 44)
                    .disabled(usage == nil || (needsReplacement && replacement == nil))
            }
        }
    }

    private func label(for option: (category: MoneyCategory, label: String)) -> String {
        let emoji = option.category.emoji.isEmpty ? "" : "\(option.category.emoji) "
        let suffix = option.category.isHidden ? " (disembunyikan)" : ""
        return emoji + option.label + suffix
    }

    private func delete(_ category: MoneyCategory, replacement: MoneyCategory?) {
        let name = category.name
        let moved = usage ?? 0
        let replacementName = replacement?.name
        do {
            try service.delete(category, replacement: replacement)
        } catch {
            errorMessage = "Kategori tidak bisa dihapus. Coba lagi."
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if moved > 0, let replacementName {
            toastCenter.show("**\(name)** dihapus. \(moved) transaksi dipindah ke **\(replacementName)**")
        } else {
            toastCenter.show("**\(name)** dihapus")
        }
        dismiss()
    }
}
