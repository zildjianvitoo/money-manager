import Foundation
import Observation

/// Holds the active and previous profile IDs, persisted in `UserDefaults`.
/// Powers the double-tap "switch to last profile" gesture.
@MainActor @Observable
public final class ProfileStore {
    private enum Key {
        static let active = "activeProfileID"
        static let previous = "previousProfileID"
    }

    @ObservationIgnored private let defaults: UserDefaults

    public private(set) var activeProfileID: UUID?
    public private(set) var previousProfileID: UUID?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.activeProfileID = defaults.string(forKey: Key.active).flatMap(UUID.init(uuidString:))
        self.previousProfileID = defaults.string(forKey: Key.previous).flatMap(UUID.init(uuidString:))
    }

    /// Makes `id` active and remembers the old active profile as previous. No-op if `id` is already active.
    public func switchTo(_ id: UUID) {
        guard id != activeProfileID else { return }
        previousProfileID = activeProfileID
        activeProfileID = id
        persist()
    }

    /// Swaps active and previous. Returns `false` if there is no previous profile.
    @discardableResult
    public func switchToPrevious() -> Bool {
        guard let previous = previousProfileID else { return false }
        previousProfileID = activeProfileID
        activeProfileID = previous
        persist()
        return true
    }

    /// Cleans up after a profile was deleted. If it was active, `fallback` becomes active and previous is cleared.
    public func handleDeleted(_ id: UUID, fallback: UUID?) {
        if previousProfileID == id {
            previousProfileID = nil
        }
        if activeProfileID == id {
            activeProfileID = fallback
            previousProfileID = nil
        }
        persist()
    }

    private func persist() {
        write(activeProfileID, forKey: Key.active)
        write(previousProfileID, forKey: Key.previous)
    }

    private func write(_ id: UUID?, forKey key: String) {
        if let id {
            defaults.set(id.uuidString, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
