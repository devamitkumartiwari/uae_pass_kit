import Flutter
import UIKit

/// UaePassKitPlugin
///
/// The only native responsibility of this plugin: checking whether the
/// native UAE Pass app is installed, via `canOpenURL:`. Every other
/// capability (the OAuth flow, all API calls) is implemented in pure Dart
/// — see the plugin README for why.
public class UaePassKitPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "uae_pass_kit", binaryMessenger: registrar.messenger())
    let instance = UaePassKitPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isUaePassAppInstalled":
      guard let args = call.arguments as? [String: Any],
            let scheme = args["iosUrlScheme"] as? String,
            !scheme.isEmpty
      else {
        result(FlutterError(
          code: "invalid_argument",
          message: "iosUrlScheme is required",
          details: nil
        ))
        return
      }
      result(isSchemeAvailable(scheme))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Requires the calling app to declare `scheme` under
  /// `LSApplicationQueriesSchemes` in its Info.plist — without it,
  /// `canOpenURL:` always returns `false` under App Store's scheme-query
  /// allowlisting, regardless of whether the app is actually installed.
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
}
