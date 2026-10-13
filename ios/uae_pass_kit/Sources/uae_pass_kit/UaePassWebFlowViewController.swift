import UIKit
import WebKit

/// A full-screen `WKWebView` that drives any UAE Pass flow built on the
/// documented app-to-app interception mechanics — shared by both the
/// login flow and the e-signature flow, exactly as UAE Pass's own iOS SDK
/// reuses one WebView delegate for both.
///
/// This controller only orchestrates navigation and the native-app
/// hand-off; it has no opinion on what a "finished" URL means beyond the
/// [isFinished] predicate it's given. [onFinished] is called with the
/// final URL (or `nil` if the user cancelled by closing the screen) and an
/// optional error message.
final class UaePassWebFlowViewController: UIViewController, WKNavigationDelegate {
  private let initialUrl: URL
  private let appCallbackScheme: String
  private let uaePassScheme: String
  private let isFinished: (URL) -> Bool

  /// Called at most once, with either a finished/cancelled URL or an error.
  var onFinished: ((URL?, String?) -> Void)?

  private var webView: WKWebView!
  private var hasFinished = false

  init(
    initialUrl: URL,
    appCallbackScheme: String,
    uaePassScheme: String,
    isFinished: @escaping (URL) -> Bool
  ) {
    self.initialUrl = initialUrl
    self.appCallbackScheme = appCallbackScheme
    self.uaePassScheme = uaePassScheme
    self.isFinished = isFinished
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: "Close",
      style: .plain,
      target: self,
      action: #selector(closeTapped)
    )

    let configuration = WKWebViewConfiguration()
    webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = self
    webView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(webView)
    NSLayoutConstraint.activate([
      webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
    ])

    webView.load(URLRequest(url: initialUrl))
  }

  @objc private func closeTapped() {
    finish(url: nil, error: nil)
    dismiss(animated: true)
  }

  /// The original `successurl`/`failureurl` UAE Pass sent in its `uaepass://`
  /// handoff request, captured before [rewriteForNativeAppHandoff] replaces
  /// them with this app's fixed sentinel URLs — reloaded by [forceReload]
  /// once the native UAE Pass app hands control back.
  private var cachedSuccessUrl: String?
  private var cachedFailureUrl: String?

  /// Reloads the cached `successurl` (or just reloads the current page if
  /// none was captured) — called by [UaePassKitPlugin] once the native UAE
  /// Pass app opens this app's fixed `appCallbackScheme://success` sentinel.
  func forceReload() {
    if let successUrl = cachedSuccessUrl, let url = URL(string: successUrl) {
      webView.load(URLRequest(url: url))
    } else {
      webView.reload()
    }
  }

  /// Stops the current load and finishes as cancelled — called by
  /// [UaePassKitPlugin] once the native UAE Pass app opens this app's fixed
  /// `appCallbackScheme://failure` sentinel.
  func forceStop() {
    webView.stopLoading()
    finish(url: nil, error: nil)
    dismiss(animated: true)
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = navigationAction.request.url else {
      decisionHandler(.allow)
      return
    }

    if isFinished(url) {
      decisionHandler(.cancel)
      finish(url: url, error: nil)
      dismiss(animated: true)
      return
    }

    // UAE Pass's pages always link to `uaepass://`, whatever the environment;
    // retarget it at the environment's own app
    // (e.g. `uaepassstg://` on staging) before handing off.
    if url.scheme == "uaepass" || url.scheme == uaePassScheme {
      decisionHandler(.cancel)
      let rewritten = rewriteForNativeAppHandoff(url)
      if UIApplication.shared.canOpenURL(rewritten) {
        UIApplication.shared.open(rewritten, options: [:]) { opened in
          if !opened {
            self.finish(url: nil, error: "Unable to open the UAE Pass app")
            DispatchQueue.main.async { self.dismiss(animated: true) }
          }
        }
      } else {
        finish(url: nil, error: "The UAE Pass app is not available")
        dismiss(animated: true)
      }
      return
    }

    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    finish(url: nil, error: error.localizedDescription)
    dismiss(animated: true)
  }

  /// Rewrites `successurl`/`failureurl` so the native UAE Pass app hands
  /// control back to this app's fixed `appCallbackScheme://success` /
  /// `appCallbackScheme://failure` sentinel URLs instead of its own
  /// default, first caching each original value into [cachedSuccessUrl] /
  /// [cachedFailureUrl] so [forceReload] can resume the flow with it once
  /// the sentinel comes back (fixed sentinel URLs carry no payload; the
  /// actual destination is cached locally, not round-tripped through the OS).
  private func rewriteForNativeAppHandoff(_ url: URL) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let items = components.queryItems
    else {
      return url
    }
    components.scheme = uaePassScheme
    components.queryItems = items.map { item in
      switch item.name {
      case "successurl", "successURL", "successUrl":
        cachedSuccessUrl = item.value
        return URLQueryItem(name: item.name, value: "\(appCallbackScheme)://success")
      case "failureurl", "failureURL", "failureUrl":
        cachedFailureUrl = item.value
        return URLQueryItem(name: item.name, value: "\(appCallbackScheme)://failure")
      default:
        return item
      }
    }
    return components.url ?? url
  }

  private func finish(url: URL?, error: String?) {
    guard !hasFinished else { return }
    hasFinished = true
    onFinished?(url, error)
  }
}
