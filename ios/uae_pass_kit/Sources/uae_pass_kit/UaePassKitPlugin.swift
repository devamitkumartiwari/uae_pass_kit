import Flutter
import UIKit

/// UaePassKitPlugin
///
/// Owns every part of the UAE Pass flow that involves the browser/native-app
/// hand-off and the deep-link return, because that hand-off is what proved
/// unreliable when driven from Dart (`webview_flutter` + `url_launcher` +
/// `app_links`) — the flow getting stuck after control bounced out to the
/// UAE Pass app or the system browser. Every other capability (token
/// exchange, profile fetch, document upload/poll/download) stays in Dart —
/// see the plugin README.
///
/// Unlike Android (which vendors UAE Pass's official native SDK), there is
/// no equivalent iOS binary, so sign-in and document-signing are both
/// driven by one in-app `WKWebView` (never Safari), following the exact
/// mechanics UAE Pass's own reference SDKs implement: intercept navigation
/// to the configured redirect/finish URL, and intercept navigation to UAE
/// Pass's own custom scheme to hand off to the native app, rewriting its
/// `successurl`/`failureurl` to this app's fixed `appCallbackScheme://success`
/// / `appCallbackScheme://failure` sentinel URLs before launching it — the
/// actual destination is cached locally (see `UaePassWebFlowViewController`)
/// rather than round-tripped through the returning deep link itself.
public class UaePassKitPlugin: NSObject, FlutterPlugin {
  private var appCallbackScheme: String?
  private var uaePassScheme: String?

  /// The web-flow controller currently awaiting a resumed deep link, if
  /// any — set while [presentWebFlow] is in progress, consulted by
  /// [application(_:open:options:)] when the UAE Pass app hands control
  /// back via this app's own callback scheme.
  private weak var pendingWebFlow: UaePassWebFlowViewController?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "uae_pass_kit", binaryMessenger: registrar.messenger())
    let instance = UaePassKitPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isUaePassAppInstalled":
      handleIsUaePassAppInstalled(call, result)
    case "setUpEnvironment":
      handleSetUpEnvironment(call, result)
    case "signIn":
      handleSignIn(call, result)
    case "openSigningUrl":
      handleOpenSigningUrl(call, result)
    case "signOut":
      handleSignOut(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - isUaePassAppInstalled

  /// Requires the calling app to declare `scheme` under
  /// `LSApplicationQueriesSchemes` in its Info.plist — without it,
  /// `canOpenURL:` always returns `false` under App Store's scheme-query
  /// allowlisting, regardless of whether the app is actually installed.
  private func handleIsUaePassAppInstalled(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let scheme = args["iosUrlScheme"] as? String,
          !scheme.isEmpty
    else {
      result(FlutterError(code: "invalid_argument", message: "iosUrlScheme is required", details: nil))
      return
    }
    result(isSchemeAvailable(scheme))
  }

  private func isSchemeAvailable(_ scheme: String) -> Bool {
    guard let url = URL(string: "\(scheme)://") else { return false }
    var canOpen = false
    if Thread.isMainThread {
      canOpen = UIApplication.shared.canOpenURL(url)
    } else {
      DispatchQueue.main.sync {
        canOpen = UIApplication.shared.canOpenURL(url)
      }
    }
    return canOpen
  }

  // MARK: - setUpEnvironment

  private func handleSetUpEnvironment(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let appCallbackScheme = args["appCallbackScheme"] as? String,
          let uaePassScheme = args["uaePassScheme"] as? String
    else {
      result(FlutterError(code: "invalid_argument", message: "appCallbackScheme and uaePassScheme are required", details: nil))
      return
    }
    self.appCallbackScheme = appCallbackScheme
    self.uaePassScheme = uaePassScheme
    result(nil)
  }

  // MARK: - signIn

  private func handleSignIn(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let authorizeUrlString = args["authorizeUrl"] as? String,
          let authorizeUrl = URL(string: authorizeUrlString),
          let redirectUri = authorizeUrl.queryValue(for: "redirect_uri"),
          let appCallbackScheme = self.appCallbackScheme,
          let uaePassScheme = self.uaePassScheme
    else {
      result(FlutterError(code: "invalid_argument", message: "authorizeUrl is required and setUpEnvironment must be called first", details: nil))
      return
    }

    presentWebFlow(
      initialUrl: authorizeUrl,
      appCallbackScheme: appCallbackScheme,
      uaePassScheme: uaePassScheme,
      isFinished: { url in url.absoluteString.hasPrefix(redirectUri) },
      title: "UAE PASS",
      result: { finishedUrl, error in
        if let error = error {
          result(FlutterError(code: "ERROR", message: error, details: nil))
          return
        }
        guard let finishedUrl = finishedUrl else {
          result(nil) // cancelled
          return
        }
        if let authError = finishedUrl.queryValue(for: "error") {
          let description = finishedUrl.queryValue(for: "error_description") ?? authError
          result(FlutterError(code: "ERROR", message: description, details: nil))
          return
        }
        result(finishedUrl.queryValue(for: "code"))
      }
    )
  }

  // MARK: - openSigningUrl

  private func handleOpenSigningUrl(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let urlString = args["url"] as? String,
          let url = URL(string: urlString),
          let appCallbackScheme = self.appCallbackScheme,
          let uaePassScheme = self.uaePassScheme
    else {
      result(FlutterError(code: "invalid_argument", message: "url is required and setUpEnvironment must be called first", details: nil))
      return
    }
    let finishScheme = args["finishScheme"] as? String
    let finishHost = args["finishHost"] as? String
    let finishPath = args["finishPath"] as? String

    presentWebFlow(
      initialUrl: url,
      appCallbackScheme: appCallbackScheme,
      uaePassScheme: uaePassScheme,
      isFinished: { candidate in
        if candidate.queryValue(for: "status") != nil { return true }
        guard let finishScheme = finishScheme else { return false }
        return candidate.scheme == finishScheme
          && candidate.host == finishHost
          && candidate.path == (finishPath ?? "")
      },
      title: "UAE PASS SIGNING",
      result: { finishedUrl, error in
        if let error = error {
          result(FlutterError(code: "ERROR", message: error, details: nil))
          return
        }
        result(finishedUrl?.absoluteString) // nil means cancelled
      }
    )
  }

  // MARK: - signOut

  private func handleSignOut(_ result: @escaping FlutterResult) {
    HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
    WKWebsiteDataStoreClearer.clearAll {
      result(nil)
    }
  }

  // MARK: - Shared web-flow presentation

  private func presentWebFlow(
    initialUrl: URL,
    appCallbackScheme: String,
    uaePassScheme: String,
    isFinished: @escaping (URL) -> Bool,
    title: String,
    result: @escaping (URL?, String?) -> Void
  ) {
    guard let rootViewController = UserInterfaceInfo.topViewController() else {
      result(nil, "Unable to find a view controller to present UAE Pass on")
      return
    }

    let controller = UaePassWebFlowViewController(
      initialUrl: initialUrl,
      appCallbackScheme: appCallbackScheme,
      uaePassScheme: uaePassScheme,
      isFinished: isFinished
    )
    controller.title = title
    controller.onFinished = { [weak self] finishedUrl, error in
      self?.pendingWebFlow = nil
      result(finishedUrl, error)
    }
    pendingWebFlow = controller

    let navigationController = UINavigationController(rootViewController: controller)
    navigationController.modalPresentationStyle = .fullScreen
    DispatchQueue.main.async {
      rootViewController.present(navigationController, animated: true)
    }
  }

  // MARK: - App-to-app return

  /// Catches the return from the native UAE Pass app via this app's own
  /// fixed `appCallbackScheme://success` / `appCallbackScheme://failure`
  /// sentinel URLs, and resumes whichever web flow ([handleSignIn] or
  /// [handleOpenSigningUrl]) is currently pending — matching UAE Pass's own
  /// reference SDK mechanics exactly.
  public func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    guard let scheme = appCallbackScheme, let flow = pendingWebFlow else { return false }
    let urlString = url.absoluteString
    if urlString.contains("\(scheme)://success") {
      flow.forceReload()
      return true
    }
    if urlString.contains("\(scheme)://failure") {
      flow.forceStop()
      return true
    }
    return false
  }
}
