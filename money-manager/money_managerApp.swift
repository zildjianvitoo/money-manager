//
//  money_managerApp.swift
//  money-manager
//
//  Created by Zildjian Vito  on 01/11/26.
//

import SwiftUI
import SwiftData
import MoneyCore

@main
struct money_managerApp: App {
    private let container: ModelContainer
    @State private var profileStore = ProfileStore()
    @State private var toastCenter = ToastCenter()

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
                .task { bootstrapProfiles() }
        }
        .modelContainer(container)
    }

    /// Ensures a "Pribadi" profile exists and the active profile is valid.
    private func bootstrapProfiles() {
        do {
            _ = try ProfileService(context: container.mainContext).bootstrap(store: profileStore)
        } catch {
            assertionFailure("Bootstrap profil gagal: \(error)")
        }
    }
}
