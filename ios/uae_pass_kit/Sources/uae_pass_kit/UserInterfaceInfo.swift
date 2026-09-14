import UIKit

/// Finds the top-most presented view controller to present UAE Pass's
/// web-flow screen on, walking through the key window's root controller and
/// any presented/navigation/tab-bar controllers on top of it.
enum UserInterfaceInfo {
  static func topViewController() -> UIViewController? {
    let keyWindow = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }
      .first
    guard var top = keyWindow?.rootViewController else { return nil }
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
