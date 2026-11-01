import SwiftUI
import UIKit

/// Renders the active profile's avatar (emoji on its color) for the tab bar.
/// Rendered through SwiftUI's `ImageRenderer`, which draws color emoji
/// reliably, and marked `.alwaysOriginal` so the tab bar keeps its colors.
enum ProfileTabIcon {
    static let size: CGFloat = 28

    static func image(emoji: String, colorHex: String, selected: Bool, scale: CGFloat = 3) -> UIImage {
        let renderer = ImageRenderer(content: Avatar(emoji: emoji, colorHex: colorHex, selected: selected))
        renderer.scale = scale
        return (renderer.uiImage ?? UIImage()).withRenderingMode(.alwaysOriginal)
    }

    private struct Avatar: View {
        let emoji: String
        let colorHex: String
        let selected: Bool

        var body: some View {
            Circle()
                .fill(Color(hex: colorHex))
                .overlay {
                    Text(emoji).font(.system(size: ProfileTabIcon.size * 0.55))
                }
                .overlay {
                    if selected {
                        Circle().strokeBorder(Color(uiColor: .label), lineWidth: 2)
                    }
                }
                .frame(width: ProfileTabIcon.size, height: ProfileTabIcon.size)
        }
    }
}
