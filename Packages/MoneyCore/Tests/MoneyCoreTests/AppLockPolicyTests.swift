import Testing
import Foundation
@testable import MoneyCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Test func disabledNeverLocks() {
    #expect(!AppLockPolicy.shouldLock(enabled: false, backgroundedAt: nil, now: now, graceSeconds: 0))
    #expect(!AppLockPolicy.shouldLock(enabled: false, backgroundedAt: now.addingTimeInterval(-9_999), now: now, graceSeconds: 60))
}

@Test func coldStartLocks() {
    #expect(AppLockPolicy.shouldLock(enabled: true, backgroundedAt: nil, now: now, graceSeconds: 900))
}

@Test func withinGraceStaysOpen() {
    #expect(!AppLockPolicy.shouldLock(enabled: true, backgroundedAt: now.addingTimeInterval(-59), now: now, graceSeconds: 60))
}

@Test func pastGraceLocks() {
    #expect(AppLockPolicy.shouldLock(enabled: true, backgroundedAt: now.addingTimeInterval(-60), now: now, graceSeconds: 60))
    #expect(AppLockPolicy.shouldLock(enabled: true, backgroundedAt: now.addingTimeInterval(-301), now: now, graceSeconds: 300))
}

@Test func zeroGraceAlwaysLocks() {
    #expect(AppLockPolicy.shouldLock(enabled: true, backgroundedAt: now, now: now, graceSeconds: 0))
}

@Test func clockGoingBackwardsLocks() {
    #expect(AppLockPolicy.shouldLock(enabled: true, backgroundedAt: now.addingTimeInterval(100), now: now, graceSeconds: 60))
}

@MainActor @Test func settingsPersist() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let first = AppLockSettings(defaults: defaults)
    #expect(first.isEnabled == false)
    #expect(first.graceSeconds == 60)
    first.isEnabled = true
    first.graceSeconds = 300
    let second = AppLockSettings(defaults: defaults)
    #expect(second.isEnabled == true)
    #expect(second.graceSeconds == 300)
    #expect(AppLockSettings.graceOptions == [0, 60, 300, 900])
}
