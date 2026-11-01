import SwiftUI
import MoneyCore

/// "Lainnya" tab. Placeholder until Task 14; already offers the profile
/// switcher so it stays reachable even when the tab bar gestures are off.
struct MoreView: View {
    let activeProfile: Profile?
    let onSwitchProfile: () -> Void

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
                    Label("Import / Export", systemImage: "square.and.arrow.down.on.square")
                    Label("Transaksi Berulang", systemImage: "repeat")
                    Label("Keamanan", systemImage: "faceid")
                } footer: {
                    Text("Segera hadir")
                }
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Lainnya")
        }
    }
}
