import Foundation
import Observation

/// Pengaturan kunci aplikasi, disimpan di `UserDefaults` (per perangkat, tidak di-sync).
@MainActor @Observable
public final class AppLockSettings {
    private enum Key {
        static let enabled = "appLockEnabled"
        static let grace = "appLockGraceSeconds"
    }

    /// Pilihan jeda dalam detik.
    public static let graceOptions: [Int] = [0, 60, 300, 900]

    @ObservationIgnored private let defaults: UserDefaults

    /// Default false.
    public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.enabled) }
    }

    /// Default 60.
    public var graceSeconds: Int {
        didSet { defaults.set(graceSeconds, forKey: Key.grace) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Key.enabled)
        self.graceSeconds = defaults.object(forKey: Key.grace) as? Int ?? 60
    }
}

public enum AppLockPolicy {
    /// Saat kembali ke foreground: kunci bila aktif dan sudah di background ≥ grace. Tanpa `backgroundedAt` (cold start) selalu kunci bila aktif.
    public static func shouldLock(enabled: Bool, backgroundedAt: Date?, now: Date, graceSeconds: Int) -> Bool {
        guard enabled else { return false }
        guard let backgroundedAt else { return true }
        let elapsed = now.timeIntervalSince(backgroundedAt)
        // Jam mundur (elapsed < 0) dianggap tidak bisa dipercaya, jadi kunci.
        return elapsed < 0 || elapsed >= TimeInterval(graceSeconds)
    }
}
