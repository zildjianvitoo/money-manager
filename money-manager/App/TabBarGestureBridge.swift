import SwiftUI
import UIKit
import OSLog

/// Adds Instagram-style double-tap and long-press on the profile tab of the
/// native `TabView`. SwiftUI exposes neither gesture per tab item, so this
/// attaches UIKit recognizers to the hosting `UITabBar`. Plain taps are left
/// entirely to the system (`cancelsTouchesInView = false`, no failure
/// requirements). If the tab bar can't be found, nothing is installed.
struct TabBarGestureBridge: UIViewControllerRepresentable {
    let profileTabIndex: Int
    let profileTabLabel: String
    let onDoubleTap: () -> Void
    let onLongPress: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.profileTabIndex = profileTabIndex
        controller.profileTabLabel = profileTabLabel
        controller.onDoubleTap = onDoubleTap
        controller.onLongPress = onLongPress
        controller.installIfNeeded()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        var profileTabIndex = 0
        var profileTabLabel = ""
        var onDoubleTap: () -> Void = {}
        var onLongPress: () -> Void = {}

        private static let doubleTapName = "profileTab.doubleTap"
        private static let longPressName = "profileTab.longPress"
        private static let logger = Logger(subsystem: "pakenanya.money-manager", category: "TabBarGestureBridge")
        private weak var tabBar: UITabBar?

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            installIfNeeded()
        }

        func installIfNeeded() {
            guard tabBar == nil, view.window != nil else { return }
            guard let tabBarController = findTabBarController() else {
                Self.logger.warning("UITabBarController not found; profile tab gestures disabled")
                return
            }
            let bar = tabBarController.tabBar
            tabBar = bar
            // Several tabs may host a bridge; recognizers are shared per tab bar.
            if bar.gestureRecognizers?.contains(where: { $0.name == Self.doubleTapName }) == true {
                retarget(bar)
                return
            }

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.name = Self.doubleTapName
            doubleTap.numberOfTapsRequired = 2
            configure(doubleTap)
            bar.addGestureRecognizer(doubleTap)

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPress.name = Self.longPressName
            longPress.minimumPressDuration = 0.4
            configure(longPress)
            bar.addGestureRecognizer(longPress)
        }

        private func configure(_ recognizer: UIGestureRecognizer) {
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
        }

        /// Point existing recognizers at this controller (the latest bridge wins).
        private func retarget(_ bar: UITabBar) {
            for recognizer in bar.gestureRecognizers ?? [] {
                switch recognizer.name {
                case Self.doubleTapName:
                    recognizer.removeTarget(nil, action: nil)
                    recognizer.addTarget(self, action: #selector(handleDoubleTap(_:)))
                    recognizer.delegate = self
                case Self.longPressName:
                    recognizer.removeTarget(nil, action: nil)
                    recognizer.addTarget(self, action: #selector(handleLongPress(_:)))
                    recognizer.delegate = self
                default:
                    break
                }
            }
        }

        private func findTabBarController() -> UITabBarController? {
            var current: UIViewController? = self
            while let controller = current {
                if let tabBarController = controller as? UITabBarController { return tabBarController }
                current = controller.parent
            }
            return view.window?.rootViewController.flatMap(Self.firstTabBarController(in:))
        }

        private static func firstTabBarController(in controller: UIViewController) -> UITabBarController? {
            if let tabBarController = controller as? UITabBarController { return tabBarController }
            for child in controller.children {
                if let found = firstTabBarController(in: child) { return found }
            }
            return nil
        }

        @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onDoubleTap()
        }

        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            onLongPress()
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let bar = tabBar else { return false }
            return profileItemFrame(in: bar).contains(touch.location(in: bar))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // MARK: Locating the profile item

        /// Frame of the profile tab button in `bar` coordinates: the subview whose
        /// accessibility label is the profile name, else the trailing quarter of
        /// the item area.
        private func profileItemFrame(in bar: UITabBar) -> CGRect {
            if let button = Self.view(in: bar, withAccessibilityLabel: profileTabLabel) {
                return button.convert(button.bounds, to: bar)
            }
            let itemCount = max(bar.items?.count ?? 4, 1)
            let content = Self.itemArea(in: bar)
            let width = content.width / CGFloat(itemCount)
            return CGRect(
                x: content.minX + width * CGFloat(min(profileTabIndex, itemCount - 1)),
                y: content.minY,
                width: width,
                height: content.height
            )
        }

        private static func view(in root: UIView, withAccessibilityLabel label: String) -> UIView? {
            guard !label.isEmpty else { return nil }
            for subview in root.subviews where !subview.isHidden {
                if subview.accessibilityLabel == label, subview.bounds.width > 0 { return subview }
                if let found = view(in: subview, withAccessibilityLabel: label) { return found }
            }
            return nil
        }

        /// The union of the visible item views; on iOS 26 the glass bar floats
        /// inside a wider `UITabBar`, so its bounds alone are too wide.
        private static func itemArea(in bar: UITabBar) -> CGRect {
            let candidates = bar.subviews.filter { !$0.isHidden && $0.bounds.width > 0 && $0.bounds.width < bar.bounds.width }
            guard let first = candidates.first else { return bar.bounds }
            return candidates.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        }
    }
}
