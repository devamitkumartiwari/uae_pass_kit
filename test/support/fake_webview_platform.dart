import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// A minimal, in-memory [WebViewPlatform] implementation for widget tests,
/// following the pattern webview_flutter's own docs recommend: "For unit
/// testing, `WebViewPlatform.instance` can be set with your own test
/// implementation." Avoids depending on a real Android/iOS WebView engine
/// (unavailable under `flutter test`) while still exercising the real
/// [UaePassWebFlowScreen] navigation-delegate wiring end-to-end.
class FakeWebViewPlatform extends WebViewPlatform {
  /// The most recently created controller, if any.
  FakeWebViewController? lastController;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakeWebViewController(params);
    lastController = controller;
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return FakeNavigationDelegate(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return FakeWebViewWidget(params);
  }

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    return FakeWebViewCookieManager(params);
  }
}

/// A fake navigation delegate that records the callbacks
/// [UaePassWebFlowScreen] registers so tests can drive them directly.
class FakeNavigationDelegate extends PlatformNavigationDelegate {
  /// Creates a fake navigation delegate.
  FakeNavigationDelegate(super.params) : super.implementation();

  /// The registered navigation-request handler, if set.
  NavigationRequestCallback? onNavigationRequest;

  /// The registered page-started handler, if set.
  PageEventCallback? onPageStarted;

  /// The registered page-finished handler, if set.
  PageEventCallback? onPageFinished;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    this.onNavigationRequest = onNavigationRequest;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {
    this.onPageStarted = onPageStarted;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    this.onPageFinished = onPageFinished;
  }
}

/// A fake WebView controller that records loaded URIs and lets tests
/// simulate the underlying browser engine attempting a navigation.
class FakeWebViewController extends PlatformWebViewController {
  /// Creates a fake WebView controller.
  FakeWebViewController(super.params) : super.implementation();

  FakeNavigationDelegate? _delegate;

  /// Every URI [loadRequest] has been called with, in order.
  final List<Uri> loadedUris = [];

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    _delegate = handler as FakeNavigationDelegate;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loadedUris.add(params.uri);
    _delegate?.onPageStarted?.call(params.uri.toString());
    _delegate?.onPageFinished?.call(params.uri.toString());
  }

  /// Simulates the native browser engine attempting to navigate to [uri],
  /// exactly as a real WebView would report it to the registered
  /// navigation delegate, and returns the resulting [NavigationDecision].
  Future<NavigationDecision> simulateNavigationAttempt(Uri uri) async {
    final callback = _delegate?.onNavigationRequest;
    if (callback == null) return NavigationDecision.navigate;
    final decision = await callback(
      NavigationRequest(url: uri.toString(), isMainFrame: true),
    );
    if (decision == NavigationDecision.navigate) {
      await loadRequest(LoadRequestParams(uri: uri));
    }
    return decision;
  }
}

/// A fake WebView widget that renders as an empty box.
class FakeWebViewWidget extends PlatformWebViewWidget {
  /// Creates a fake WebView widget.
  FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A fake cookie manager that records whether cookies were cleared.
class FakeWebViewCookieManager extends PlatformWebViewCookieManager {
  /// Creates a fake cookie manager.
  FakeWebViewCookieManager(super.params) : super.implementation();

  /// Whether [clearCookies] has been called.
  bool cleared = false;

  @override
  Future<bool> clearCookies() async {
    cleared = true;
    return true;
  }
}
