import SwiftUI
import SwiftData
import MoneyCore

enum AppTab: Hashable {
    case transactions, statistics, assets, profile
}

/// Native iOS 26 `TabView` whose last tab is the active profile's avatar,
/// with Instagram-style gestures on it: tap opens "Lainnya", double-tap
/// switches to the previous profile, long-press opens the profile switcher.
struct RootView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(ToastCenter.self) private var toastCenter
    @Query(sort: [SortDescriptor(\Profile.sortOrder), SortDescriptor(\Profile.createdAt)]) private var profiles: [Profile]

    @State private var selection: AppTab = .transactions
    /// Last tab that wasn't the profile tab; restored after a profile gesture,
    /// because the gesture's first touch also selects the profile tab.
    @State private var tabBeforeProfile: AppTab = .transactions
    @State private var isSwitcherPresented = false
    /// Tab to return to once a long-press releases on the profile tab.
    @State private var tabToRestoreAfterLongPress: AppTab?

    private var activeProfile: Profile? {
        profiles.first { $0.id == store.activeProfileID }
    }

    private var profileName: String { activeProfile?.name ?? "Profil" }
    private var profileColor: String { activeProfile?.colorHex ?? "#FF6B5A" }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Transaksi", systemImage: "list.bullet.rectangle.portrait", value: AppTab.transactions) {
                withGestureBridge(placeholder("Transaksi", systemImage: "list.bullet.rectangle.portrait"))
            }
            Tab("Statistik", systemImage: "chart.pie", value: AppTab.statistics) {
                withGestureBridge(placeholder("Statistik", systemImage: "chart.pie"))
            }
            Tab("Aset", systemImage: "building.columns", value: AppTab.assets) {
                withGestureBridge(placeholder("Aset", systemImage: "building.columns"))
            }
            Tab(value: AppTab.profile) {
                withGestureBridge(MoreView(activeProfile: activeProfile) { isSwitcherPresented = true })
            } label: {
                Label {
                    Text(profileName)
                } icon: {
                    Image(uiImage: ProfileTabIcon.image(
                        emoji: activeProfile?.emoji ?? "🙂",
                        colorHex: profileColor,
                        selected: selection == .profile
                    ))
                }
            }
        }
        .tint(Color(hex: profileColor))
        .tabBarMinimizeBehavior(.onScrollDown)
        .overlay { ToastOverlay() }
        .onChange(of: selection) { old, new in
            if new == .profile, old != .profile { tabBeforeProfile = old }
            if new == .profile, let restore = tabToRestoreAfterLongPress {
                tabToRestoreAfterLongPress = nil
                selection = restore
            }
        }
        .sheet(isPresented: $isSwitcherPresented, onDismiss: { tabToRestoreAfterLongPress = nil }) {
            ProfileSwitcherSheet { profile in
                switchTo(profile.id, name: profile.name)
            }
            .tint(Color(hex: profileColor))
        }
    }

    // MARK: Profile gestures

    private func handleDoubleTap() {
        guard store.switchToPrevious() else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        toastCenter.show("Beralih ke **\(profileName)**")
        selection = tabBeforeProfile
    }

    private func handleLongPress() {
        if selection != .profile { tabToRestoreAfterLongPress = selection }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSwitcherPresented = true
    }

    private func switchTo(_ id: UUID, name: String) {
        store.switchTo(id)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        toastCenter.show("Beralih ke **\(name)**")
    }

    // MARK: Helpers

    /// Every tab hosts a bridge so the gestures work whichever tab loads first;
    /// they share one set of recognizers on the tab bar.
    private func withGestureBridge(_ content: some View) -> some View {
        content.background(
            TabBarGestureBridge(
                profileTabIndex: 3,
                profileTabLabel: profileName,
                onDoubleTap: handleDoubleTap,
                onLongPress: handleLongPress
            )
            .frame(width: 0, height: 0)
        )
    }

    private func placeholder(_ title: String, systemImage: String) -> some View {
        NavigationStack {
            ContentUnavailableView("Segera hadir", systemImage: systemImage, description: Text("Layar \(title) sedang dibuat."))
                .navigationTitle(title)
        }
    }
}
