import SwiftUI

enum AppTab: Hashable {
    case transactions, statistics, assets, profile
}

// SPIKE: minimal shell to validate the tab bar avatar and gestures.
struct RootView: View {
    @State private var selection: AppTab = .transactions
    @State private var doubleTaps = 0
    @State private var longPresses = 0
    @State private var log: [String] = []

    private let profileName = "Pribadi"
    private let profileEmoji = "🙂"
    private let profileColor = "#FF6B5A"

    var body: some View {
        TabView(selection: $selection) {
            Tab("Transaksi", systemImage: "list.bullet.rectangle.portrait", value: .transactions) {
                spikePanel(title: "Transaksi")
            }
            Tab("Statistik", systemImage: "chart.pie", value: .statistics) {
                spikePanel(title: "Statistik")
            }
            Tab("Aset", systemImage: "building.columns", value: .assets) {
                spikePanel(title: "Aset")
            }
            Tab(value: .profile) {
                spikePanel(title: "Lainnya")
            } label: {
                Label {
                    Text(profileName)
                } icon: {
                    Image(uiImage: ProfileTabIcon.image(emoji: profileEmoji, colorHex: "#34C759", selected: selection == .profile))
                }
            }
        }
        .tint(Color(hex: profileColor))
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    private func spikePanel(title: String) -> some View {
        NavigationStack {
            List {
                Section("Spike") {
                    LabeledContent("Tab aktif", value: "\(selection)")
                    LabeledContent("Double-tap profil", value: "\(doubleTaps)")
                    LabeledContent("Long-press profil", value: "\(longPresses)")
                    LabeledContent("Emoji teks", value: "🙂🍜💰")
                    LabeledContent("Ikon") {
                        Image(uiImage: ProfileTabIcon.image(emoji: profileEmoji, colorHex: "#34C759", selected: false))
                            .resizable().frame(width: 84, height: 84)
                    }
                }
                Section("Log") {
                    ForEach(Array(log.suffix(8).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.footnote.monospaced())
                    }
                }
            }
            .navigationTitle(title)
        }
        .background(
            TabBarGestureBridge(
                profileTabIndex: 3,
                profileTabLabel: profileName,
                onDoubleTap: {
                    doubleTaps += 1
                    log.append("double-tap (tab: \(selection))")
                },
                onLongPress: {
                    longPresses += 1
                    log.append("long-press (tab: \(selection))")
                }
            )
            .frame(width: 0, height: 0)
        )
    }
}

#Preview {
    RootView()
}
