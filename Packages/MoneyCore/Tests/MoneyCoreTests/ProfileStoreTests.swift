import Foundation
import Testing
@testable import MoneyCore

@MainActor
struct ProfileStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    @Test func switchesAndRemembersPrevious() {
        let store = ProfileStore(defaults: makeDefaults())
        let a = UUID(), b = UUID()
        store.switchTo(a)
        store.switchTo(b)
        #expect(store.activeProfileID == b)
        #expect(store.previousProfileID == a)
    }

    @Test func doubleTapTogglesBackAndForth() {
        let store = ProfileStore(defaults: makeDefaults())
        let a = UUID(), b = UUID()
        store.switchTo(a)
        store.switchTo(b)
        #expect(store.switchToPrevious())
        #expect(store.activeProfileID == a)
        #expect(store.switchToPrevious())
        #expect(store.activeProfileID == b)
        #expect(store.switchToPrevious())
        #expect(store.activeProfileID == a)
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults()
        let a = UUID(), b = UUID()
        let first = ProfileStore(defaults: defaults)
        first.switchTo(a)
        first.switchTo(b)
        let second = ProfileStore(defaults: defaults)
        #expect(second.activeProfileID == b)
        #expect(second.previousProfileID == a)
    }

    @Test func switchToPreviousWithoutPrevious() {
        let store = ProfileStore(defaults: makeDefaults())
        let a = UUID()
        store.switchTo(a)
        #expect(store.switchToPrevious() == false)
        #expect(store.activeProfileID == a)
    }

    @Test func switchToSameIsNoop() {
        let store = ProfileStore(defaults: makeDefaults())
        let a = UUID()
        store.switchTo(a)
        store.switchTo(a)
        #expect(store.previousProfileID == nil)
    }

    @Test func previousClearedWhenDeleted() {
        let store = ProfileStore(defaults: makeDefaults())
        let a = UUID(), b = UUID(), c = UUID()
        store.switchTo(a)
        store.switchTo(b)
        store.handleDeleted(a, fallback: nil)
        #expect(store.previousProfileID == nil)
        store.handleDeleted(b, fallback: c)
        #expect(store.activeProfileID == c)
        #expect(store.previousProfileID == nil)
    }
}
