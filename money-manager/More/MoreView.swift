import SwiftUI
import SwiftData
import MoneyCore

/// "Lainnya" tab: the active profile with a switcher fallback (the tab bar
/// gestures can fail), management screens, upcoming features and the app version.
struct MoreView: View {
    let activeProfile: Profile?
    let onSwitchProfile: () -> Void

    #if DEBUG
    @Environment(\.modelContext) private var context
    @Environment(ProfileStore.self) private var store
    @Environment(ToastCenter.self) private var toastCenter
    @State private var isConfirmingSeedImport = false
    @State private var seedImportError: String?
    #endif

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "Versi \(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                if let profile = activeProfile {
                    Section {
                        HStack(spacing: 14) {
                            ProfileAvatar(emoji: profile.emoji, colorHex: profile.colorHex, size: 52)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name).font(.headline)
                                Text("Profil aktif").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        Button("Ganti profil", systemImage: "arrow.left.arrow.right", action: onSwitchProfile)
                    }
                }
                Section {
                    NavigationLink {
                        ProfileManagementView()
                    } label: {
                        Label("Profil", systemImage: "person.2")
                    }
                    NavigationLink {
                        CategoryManagementView()
                    } label: {
                        Label("Kategori", systemImage: "square.grid.2x2")
                    }
                }
                Section {
                    comingSoonRow("Import / Export", systemImage: "square.and.arrow.down.on.square")
                    comingSoonRow("Transaksi Berulang", systemImage: "repeat")
                    comingSoonRow("Keamanan", systemImage: "faceid")
                }
                #if DEBUG
                if BusinessSeedImporter.isAvailable {
                    Section {
                        Button("Impor data awal Bisnis", systemImage: "square.and.arrow.down") {
                            isConfirmingSeedImport = true
                        }
                    } footer: {
                        Text("Khusus build debug. Memasukkan riwayat dari Money Manager ke profil Bisnis, sekali saja.")
                    }
                }
                #endif
                Section {
                    LabeledContent {
                        Text(versionText)
                    } label: {
                        Label("Tentang", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Lainnya")
            #if DEBUG
            .confirmationDialog("Impor data awal Bisnis?", isPresented: $isConfirmingSeedImport, titleVisibility: .visible) {
                Button("Impor") { importBusinessSeed() }
            } message: {
                Text("Profil Bisnis dibuat kalau belum ada, lalu diisi aset dan transaksi dari backup.")
            }
            .alert("Impor gagal", isPresented: Binding(get: { seedImportError != nil }, set: { if !$0 { seedImportError = nil } })) {
                Button("OK") { seedImportError = nil }
            } message: {
                Text(seedImportError ?? "")
            }
            #endif
        }
    }

    #if DEBUG
    private func importBusinessSeed() {
        do {
            let result = try BusinessSeedImporter.run(context: context)
            store.switchTo(result.profile.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            toastCenter.show("\(result.count) transaksi masuk ke **\(result.profile.name)**")
        } catch {
            seedImportError = error.localizedDescription
        }
    }
    #endif

    /// A disabled row, announced by VoiceOver as dimmed.
    private func comingSoonRow(_ title: String, systemImage: String) -> some View {
        Button {} label: {
            LabeledContent {
                Text("Segera hadir")
            } label: {
                Label(title, systemImage: systemImage)
            }
        }
        .disabled(true)
    }
}
