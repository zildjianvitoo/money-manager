import SwiftUI

/// Full-screen lock shown in the lock window until authentication succeeds.
struct LockScreenView: View {
    let controller: AppLockController

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "faceid")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Duitku terkunci")
                .font(.title2.weight(.semibold))
            Button {
                Task { await controller.unlock() }
            } label: {
                Text("Buka")
                    .font(.headline)
                    .frame(minWidth: 140)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}
