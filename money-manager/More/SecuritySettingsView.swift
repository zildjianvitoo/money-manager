import SwiftUI
import LocalAuthentication
import MoneyCore

/// Lainnya → Keamanan: app lock toggle and re-lock delay.
struct SecuritySettingsView: View {
    @Environment(AppLockController.self) private var controller

    private let capability = Capability.current()

    var body: some View {
        @Bindable var settings = controller.settings
        Form {
            Section {
                Toggle("Kunci dengan \(capability.label)", isOn: lockBinding)
                    .disabled(!capability.isAvailable)
            } footer: {
                if capability.isAvailable {
                    Text("Duitku meminta \(capability.label) atau kode sandi saat dibuka.")
                } else {
                    Text("Atur Face ID atau kode sandi di Pengaturan iPhone untuk memakai kunci aplikasi.")
                }
            }
            if controller.settings.isEnabled {
                Section {
                    Picker("Kunci ulang setelah", selection: $settings.graceSeconds) {
                        ForEach(AppLockSettings.graceOptions, id: \.self) { seconds in
                            Text(Self.graceLabel(seconds)).tag(seconds)
                        }
                    }
                } footer: {
                    Text("Waktu di latar belakang sebelum Duitku meminta autentikasi lagi.")
                }
            }
        }
        .navigationTitle("Keamanan")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Turning on requires a successful authentication first.
    private var lockBinding: Binding<Bool> {
        Binding(
            get: { controller.settings.isEnabled },
            set: { newValue in
                if newValue {
                    Task {
                        if await controller.authenticate() { controller.settings.isEnabled = true }
                    }
                } else {
                    controller.settings.isEnabled = false
                }
            }
        )
    }

    static func graceLabel(_ seconds: Int) -> String {
        seconds == 0 ? "Langsung" : "\(seconds / 60) menit"
    }

    private struct Capability {
        let isAvailable: Bool
        let label: String

        static func current() -> Capability {
            let context = LAContext()
            var error: NSError?
            let available = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            // `biometryType` is only valid after `canEvaluatePolicy`.
            let label: String
            switch context.biometryType {
            case .faceID: label = "Face ID"
            case .touchID: label = "Touch ID"
            case .opticID: label = "Optic ID"
            default: label = "Kode sandi"
            }
            return Capability(isAvailable: available, label: label)
        }
    }
}
