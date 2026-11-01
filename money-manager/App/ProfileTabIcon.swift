import SwiftUI
import UIKit

/// A profile's avatar: its emoji on a circle of its color.
struct ProfileAvatar: View {
    let emoji: String
    let colorHex: String
    var size: CGFloat = 28
    var selected = false

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex))
            .overlay {
                Text(emoji).font(.system(size: size * 0.55))
            }
            .overlay {
                if selected {
                    Circle().strokeBorder(Color(uiColor: .label), lineWidth: max(2, size / 14))
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Renders the active profile's avatar for the tab bar. Rendered through
/// SwiftUI's `ImageRenderer`, which draws color emoji reliably, and marked
/// `.alwaysOriginal` so the tab bar keeps its colors instead of tinting it.
enum ProfileTabIcon {
    static let size: CGFloat = 28

    static func image(emoji: String, colorHex: String, selected: Bool, scale: CGFloat = 3) -> UIImage {
        let renderer = ImageRenderer(content: ProfileAvatar(emoji: emoji, colorHex: colorHex, size: size, selected: selected))
        renderer.scale = scale
        return (renderer.uiImage ?? UIImage()).withRenderingMode(.alwaysOriginal)
    }
}
