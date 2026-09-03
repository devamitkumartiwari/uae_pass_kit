import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:webview_flutter/webview_flutter.dart';

/// The single `app_links` instance every [UaePassWebFlowScreen] shares.
///
/// `AppLinks` is documented as a process-wide singleton itself, but its own
/// README also recommends instantiating it "early in your app to catch the
/// very first link when the app is in cold state" — a plain top-level
/// `final` is lazily created on first access and then reused, so the very
/// first [UaePassWebFlowScreen] pushed keeps that first reference alive for
/// the rest of the process, rather than each screen instance creating (and
/// implicitly discarding) its own.
final AppLinks _sharedAppLinks = AppLinks();

/// A full-screen WebView that drives any UAE Pass flow built on the
/// documented app-to-app interception mechanics — shared by both the login
/// flow ([UaePassKit.signIn]) and the e-signature flow
/// ([UaePassKit.signDocument]), exactly as both official native SDKs reuse
/// a single WebView delegate for both.
///
/// This widget only orchestrates navigation and the native-app handoff; it
/// has no opinion on what the URLs mean. Callers interpret the final [Uri]
/// this route is popped with (or `null`, meaning the user cancelled by
/// closing the screen) — see `UaePassRedirectInterceptor` for the login
/// interpretation.
class UaePassWebFlowScreen extends StatefulWidget {
  /// Creates a UAE Pass web-flow screen.
  const UaePassWebFlowScreen({
    super.key,
    required this.initialUrl,
    required this.isNativeAppLaunchUrl,
    required this.rewriteForNativeAppHandoff,
    required this.isAppCallbackUrl,
    required this.extractOriginalUrl,
    required this.isFinalUrl,
    this.title,
    this.appLinkStream,
    this.onNativeAppLaunchFailed,
  });

  /// The URL to load first.
  final Uri initialUrl;

  /// Returns whether a navigation target is UAE Pass's native-app deep
  /// link that must be intercepted rather than allowed to fail loading as
  /// a normal page.
  final bool Function(Uri uri) isNativeAppLaunchUrl;

  /// Rewrites a native-app deep link's success/failure callback so it
  /// routes back through this app before resuming.
  final Uri Function(Uri uri) rewriteForNativeAppHandoff;

  /// Returns whether an externally-received deep link is this app's own
  /// handoff callback (received via `app_links`, not WebView navigation).
  final bool Function(Uri uri) isAppCallbackUrl;

  /// Extracts the original UAE Pass URL wrapped inside an app-callback
  /// deep link, to be reloaded into the WebView to resume the flow.
  final Uri? Function(Uri uri) extractOriginalUrl;

  /// Returns whether a navigation target is the flow's terminal URL — when
  /// reached, this screen pops itself with that URL.
  final bool Function(Uri uri) isFinalUrl;

  /// An optional app-bar title.
  final String? title;

  /// The stream of incoming deep links to check via [isAppCallbackUrl].
  ///
  /// Defaults to `AppLinks().uriLinkStream`. Overridable so tests (and
  /// host apps that already own a deep-link listener elsewhere) don't have
  /// to go through `app_links`'s process-wide singleton, which lazily
  /// binds to whatever platform implementation is current and only
  /// rebinds once every prior listener has fully, asynchronously
  /// unsubscribed — awkward to rely on from outside from a fresh instance
  /// per use.
  final Stream<Uri>? appLinkStream;

  /// Called when the native UAE Pass app was detected as installed but
  /// couldn't actually be launched (disabled, frozen, a broken install,
  /// etc.) — the "installed but cannot be opened" case, which must fall
  /// back to the app-to-web flow rather than abandon the attempt. If
  /// provided, its return value is reloaded into this same WebView/screen
  /// in place of the failed native-app launch; if `null` (or this
  /// callback isn't provided), this screen falls back to closing itself
  /// with a `null` result instead.
  final Uri Function()? onNativeAppLaunchFailed;

  @override
  State<UaePassWebFlowScreen> createState() => _UaePassWebFlowScreenState();
}

class _UaePassWebFlowScreenState extends State<UaePassWebFlowScreen> {
  late final WebViewController _controller;
  StreamSubscription<Uri>? _appLinkSubscription;
  bool _isLoading = true;
  bool _hasFinished = false;

  @override
  void initState() {
    super.initState();
    final appLinkStream = widget.appLinkStream ?? _sharedAppLinks.uriLinkStream;
    _appLinkSubscription = appLinkStream.listen(_onAppLink);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: _onNavigationRequest,
        ),
      )
      ..loadRequest(widget.initialUrl);
  }

  @override
  void dispose() {
    unawaited(_appLinkSubscription?.cancel());
    super.dispose();
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.navigate;

    if (widget.isFinalUrl(uri)) {
      _finish(uri);
      return NavigationDecision.prevent;
    }

    if (widget.isNativeAppLaunchUrl(uri)) {
      final rewritten = widget.rewriteForNativeAppHandoff(uri);
      unawaited(_launchNativeApp(rewritten));
      return NavigationDecision.prevent;
    }

    return NavigationDecision.navigate;
  }

  Future<void> _launchNativeApp(Uri uri) async {
    final launched =
        await url_launcher.canLaunchUrl(uri) &&
        await url_launcher.launchUrl(
          uri,
          mode: url_launcher.LaunchMode.externalApplication,
        );
    if (!launched && mounted) {
      // "Installed but cannot be opened" — install detection said the app
      // should be present, but the actual launch failed (removed between
      // check and launch, disabled, frozen, etc.). Fall back to app-to-web
      // in the same screen if the caller gave us a way to, matching the
      // documented flow-selection rules; only cancel outright if it didn't.
      final fallbackUrl = widget.onNativeAppLaunchFailed?.call();
      if (fallbackUrl != null) {
        unawaited(_controller.loadRequest(fallbackUrl));
      } else {
        _finish(null);
      }
    }
  }

  void _onAppLink(Uri uri) {
    if (!widget.isAppCallbackUrl(uri)) return;
    final original = widget.extractOriginalUrl(uri);
    if (original == null) return;
    unawaited(_controller.loadRequest(original));
  }

  void _finish(Uri? result) {
    if (_hasFinished || !mounted) return;
    _hasFinished = true;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish(null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title ?? 'UAE PASS'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _finish(null),
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
