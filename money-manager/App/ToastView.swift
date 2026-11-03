import SwiftUI

/// Short confirmation messages shown above the tab bar (e.g. "Beralih ke **Bisnis**").
@Observable
final class ToastCenter {
    private(set) var message: String?
    private var hideTask: Task<Void, Never>?

    /// Shows `text` (Markdown allowed) for 1.5 seconds.
    func show(_ text: String) {
        hideTask?.cancel()
        message = text
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

struct ToastOverlay: View {
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            if let message = toastCenter.message {
                Text(LocalizedStringKey(message))
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    .padding(.bottom, 96)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastCenter.message)
        .allowsHitTesting(false)
    }
}
