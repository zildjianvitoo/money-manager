import SwiftUI
import SwiftData
import MoneyCore

/// Snapshot of the profile awaiting delete confirmation, so the alert never reads a deleted model.
private struct PendingDelete {
    let id: UUID
    let name: String
}

/// Lists every profile: edit, add, drag to reorder, and delete behind a type-the-name confirmation.
struct ProfileManagementView: View {
    @Environment(\.modelContext) private var context
    @Environment(ProfileStore.self) private var store
    @Environment(ToastCenter.self) private var toastCenter
    @Query(sort: [SortDescriptor(\Profile.sortOrder), SortDescriptor(\Profile.createdAt)]) private var profiles: [Profile]

    @State private var editMode: EditMode = .inactive
    @State private var editingProfile: Profile?
    @State private var isAdding = false
    @State private var pendingDelete: PendingDelete?
    @State private var deleteConfirmation = ""
    @State private var errorMessage: String?

    private var canDelete: Bool { profiles.count > 1 }

    private var tintColor: Color {
        Color(hex: profiles.first { $0.id == store.activeProfileID }?.colorHex ?? "#FF6B5A")
    }

    var body: some View {
        List {
            Section {
                ForEach(profiles) { profile in
                    row(for: profile)
                }
                .onMove(perform: move)
            } footer: {
                if canDelete {
                    Text("Geser profil ke kiri untuk menghapus. Semua datanya ikut terhapus.")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if profiles.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "Selesai" : "Urutkan") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Tambah profil", systemImage: "plus") { isAdding = true }
                    .accessibilityLabel("Tambah profil")
            }
        }
        .sheet(item: $editingProfile) { profile in
            ProfileFormView(editing: profile)
                .tint(tintColor)
        }
        .sheet(isPresented: $isAdding) {
            ProfileFormView(existingProfiles: profiles) { _ in }
                .tint(tintColor)
        }
        .alert(
            "Hapus profil?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { pending in
            TextField("Nama profil", text: $deleteConfirmation)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Batal", role: .cancel) {}
            Button("Hapus", role: .destructive) { delete(pending) }
                .disabled(deleteConfirmation != pending.name)
        } message: { pending in
            Text("Semua transaksi, aset, dan kategori di profil \(pending.name) ikut terhapus dan tidak bisa dikembalikan. Ketik \(pending.name) untuk melanjutkan.")
        }
        .alert("Gagal mengubah profil", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(for profile: Profile) -> some View {
        let isActive = profile.id == store.activeProfileID
        return Button {
            editingProfile = profile
        } label: {
            HStack(spacing: 12) {
                ProfileAvatar(emoji: profile.emoji, colorHex: profile.colorHex, size: 44)
                Text(profile.name).foregroundStyle(.primary)
                Spacer()
                if isActive {
                    Text("Aktif").font(.subheadline).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "\(profile.name), profil aktif" : profile.name)
        .accessibilityHint("Ubah profil")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canDelete {
                Button("Hapus", systemImage: "trash") { requestDelete(profile) }
                    .tint(.red)
            }
        }
        .contextMenu {
            Button("Ubah", systemImage: "pencil") { editingProfile = profile }
            if canDelete {
                Button("Hapus", systemImage: "trash", role: .destructive) { requestDelete(profile) }
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        do {
            try ProfileService(context: context).move(from: source, to: destination)
        } catch {
            errorMessage = "Urutan profil tidak bisa disimpan. Coba lagi."
        }
    }

    private func requestDelete(_ profile: Profile) {
        deleteConfirmation = ""
        pendingDelete = PendingDelete(id: profile.id, name: profile.name)
    }

    /// `ProfileService.deleteProfile` already tells the store, which moves the active profile (and avatar) to a fallback.
    private func delete(_ pending: PendingDelete) {
        // The alert button is disabled until the name matches; check again in case it wasn't.
        guard deleteConfirmation == pending.name else { return }
        let id = pending.id
        let name = pending.name
        let wasActive = id == store.activeProfileID
        do {
            try ProfileService(context: context).deleteProfile(id, store: store)
        } catch {
            errorMessage = "Profil tidak bisa dihapus. Coba lagi."
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if wasActive, let fallback = profiles.first(where: { $0.id == store.activeProfileID }) {
            toastCenter.show("**\(name)** dihapus. Beralih ke **\(fallback.name)**")
        } else {
            toastCenter.show("**\(name)** dihapus")
        }
    }
}
