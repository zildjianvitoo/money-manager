//
//  money_managerApp.swift
//  money-manager
//
//  Created by Zildjian Vito  on 01/11/26.
//

import SwiftUI
import SwiftData
import CoreData
import MoneyCore

@main
struct money_managerApp: App {
    private let container: ModelContainer
    @State private var profileStore = ProfileStore()
    @State private var toastCenter = ToastCenter()
    @State private var lockController = AppLockController()
    @State private var cleanupTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            container = try MoneySchema.makeContainer(inMemory: false)
        } catch {
            fatalError("Gagal membuka database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(profileStore)
                .environment(toastCenter)
                .environment(lockController)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    lockController.handle(scenePhase: phase)
                }
                .task { bootstrapProfiles() }
                .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
                    scheduleDuplicateCleanup()
                }
        }
        .modelContainer(container)
    }

    /// Ensures a "Pribadi" profile exists and the active profile is valid.
    private func bootstrapProfiles() {
        do {
            let service = ProfileService(context: container.mainContext)
            _ = try service.bootstrap(store: profileStore)
            // One-time fix for the "Bisnis" profile created by the seed import before profiles had a kind.
            let kindFixKey = "didMarkBusinessProfilesByName"
            if !UserDefaults.standard.bool(forKey: kindFixKey) {
                try service.markBusinessProfilesByName()
                UserDefaults.standard.set(true, forKey: kindFixKey)
            }
            try service.removeEmptyDuplicates(store: profileStore)
        } catch {
            assertionFailure("Bootstrap profil gagal: \(error)")
        }
    }

    /// iCloud sync can bring in an empty duplicate profile from another device; debounce, then clean up.
    private func scheduleDuplicateCleanup() {
        cleanupTask?.cancel()
        cleanupTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            _ = try? ProfileService(context: container.mainContext).removeEmptyDuplicates(store: profileStore)
        }
    }
}
