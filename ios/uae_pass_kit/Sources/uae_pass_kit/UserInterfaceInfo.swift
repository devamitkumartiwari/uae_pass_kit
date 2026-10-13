import UIKit

/// Finds the top-most presented view controller to present UAE Pass's
/// web-flow screen on, walking through the key window's root controller and
/// any presented/navigation/tab-bar controllers on top of it.
enum UserInterfaceInfo {
  static func topViewController() -> UIViewController? {
    // Fall back to any window when none is key yet (e.g. right after the
    // app returns to the foreground).
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    let window = windows.first { $0.isKeyWindow } ?? windows.first
    guard var top = window?.rootViewController else { return nil }
    while true {
      if let presented = top.presentedViewController {
        top = presented
      } else if let nav = top as? UINavigationController, let visible = nav.visibleViewController {
        top = visible
      } else if let tab = top as? UITabBarController, let selected = tab.selectedViewController {
        top = selected
      } else {
        return top
      }
    }
  }
}
