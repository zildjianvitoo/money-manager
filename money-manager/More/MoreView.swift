import SwiftUI
import MoneyCore

/// "Lainnya" tab: the active profile with a switcher fallback (the tab bar
/// gestures can fail), management screens, upcoming features and the app version.
struct MoreView: View {
    let activeProfile: Profile?
    let onSwitchProfile: () -> Void

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
                Section {
                    LabeledContent {
                        Text(versionText)
                    } label: {
                        Label("Tentang", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Lainnya")
        }
    }

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
