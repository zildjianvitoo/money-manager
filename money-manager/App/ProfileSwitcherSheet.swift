import SwiftUI
import SwiftData
import MoneyCore

/// Instagram-style account switcher: pick a profile or add a new one.
struct ProfileSwitcherSheet: View {
    /// Called after the user picks a profile other than the active one.
    let onSwitch: (Profile) -> Void

    @Environment(ProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Profile.sortOrder), SortDescriptor(\Profile.createdAt)]) private var profiles: [Profile]
    @State private var isAddingProfile = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(profiles) { profile in
                        Button {
                            pick(profile)
                        } label: {
                            HStack(spacing: 12) {
                                ProfileAvatar(emoji: profile.emoji, colorHex: profile.colorHex, size: 40)
                                Text(profile.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if profile.id == store.activeProfileID {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(profile.name)
                        .accessibilityAddTraits(profile.id == store.activeProfileID ? .isSelected : [])
                    }
                }
                Section {
                    Button {
                        isAddingProfile = true
                    } label: {
                        Label("Tambah profil", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Ganti Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { dismiss() }
                }
            }
            .sheet(isPresented: $isAddingProfile) {
                ProfileFormView(existingProfiles: profiles) { created in
                    pick(created)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func pick(_ profile: Profile) {
        if profile.id != store.activeProfileID {
            onSwitch(profile)
        }
        dismiss()
    }
}

/// Form for a profile: name, emoji and color, plus an optional category source when creating.
/// Created with `init(existingProfiles:onCreated:)` for a new profile or `init(editing:onSaved:)` to edit one.
struct ProfileFormView: View {
    private let existingProfiles: [Profile]
    private let editing: Profile?
    private let onSaved: (Profile) -> Void

    static let colorPresets = ["#FF6B5A", "#FF9F0A", "#FFD60A", "#34C759", "#30B0C7", "#0A84FF", "#5E5CE6", "#BF5AF2"]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "💼"
    @State private var colorHex = ProfileFormView.colorPresets[5]
    @State private var copyCategoriesFrom: UUID?
    @State private var errorMessage: String?

    init(existingProfiles: [Profile], onCreated: @escaping (Profile) -> Void) {
        self.existingProfiles = existingProfiles
        self.editing = nil
        self.onSaved = onCreated
    }

    init(editing profile: Profile, onSaved: @escaping (Profile) -> Void = { _ in }) {
        self.existingProfiles = []
        self.editing = profile
        self.onSaved = onSaved
        _name = State(initialValue: profile.name)
        _emoji = State(initialValue: profile.emoji)
        _colorHex = State(initialValue: profile.colorHex)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ProfileAvatar(emoji: emoji.isEmpty ? "🙂" : emoji, colorHex: colorHex, size: 72)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Profil") {
                    TextField("Nama", text: $name)
                        .textInputAutocapitalization(.words)
                    LabeledContent("Emoji") {
                        TextField("Emoji", text: $emoji)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: emoji) { _, new in
                                if new.count > 1 { emoji = String(new.suffix(1)) }
                            }
                    }
                }
                Section("Warna") {
                    colorGrid
                }
                if editing == nil {
                    Section {
                        Picker("Salin kategori dari", selection: $copyCategoriesFrom) {
                            Text("Kategori bawaan").tag(UUID?.none)
                            ForEach(existingProfiles) { profile in
                                Text(profile.name).tag(UUID?.some(profile.id))
                            }
                        }
                    } footer: {
                        Text("Profil baru punya transaksi, aset, kategori, dan anggaran sendiri.")
                    }
                }
            }
            .navigationTitle(editing == nil ? "Profil Baru" : "Ubah Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Gagal menyimpan profil", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var colorGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            ForEach(Self.colorPresets, id: \.self) { hex in
                Button {
                    colorHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 44, height: 44)
                        .overlay {
                            if hex == colorHex {
                                Image(systemName: "checkmark")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Warna \(hex)")
                .accessibilityAddTraits(hex == colorHex ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        let service = ProfileService(context: context)
        let finalEmoji = emoji.isEmpty ? "🙂" : emoji
        do {
            if let editing {
                try service.update(editing, name: name, emoji: finalEmoji, colorHex: colorHex)
                dismiss()
                onSaved(editing)
            } else {
                let profile = try service.createProfile(
                    name: name,
                    emoji: finalEmoji,
                    colorHex: colorHex,
                    copyCategoriesFrom: copyCategoriesFrom
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
                onSaved(profile)
            }
        } catch {
            errorMessage = "Periksa nama profil lalu coba lagi."
        }
    }
}
