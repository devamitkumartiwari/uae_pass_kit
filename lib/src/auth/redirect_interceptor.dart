import '../config.dart';
import '../exceptions.dart';
import '../models/auth_result.dart';

/// The acr_values that trigger UAE Pass's native same-device app-to-app
/// handoff, used when the UAE Pass app is installed.
const String kUaePassAcrMobileOnDevice =
    'urn:digitalid:authentication:flow:mobileondevice';

/// The acr_values that trigger UAE Pass's push-notification fallback flow,
/// used when the UAE Pass app is not installed.
const String kUaePassAcrPushNotificationFallback =
    'urn:safelayer:tws:policies:authentication:level:low';

/// Implements the documented UAE Pass app-to-app WebView-interception
/// mechanics as pure, side-effect-free URL transformations.
///
/// Deliberately kept independent of `webview_flutter`/`app_links` so it can
/// be unit tested without a real browser engine or platform channel, and so
/// the same logic can be reused for both the login flow and the
/// e-signature flow's `status=finished`/`status=success` handling — the
/// real iOS SDK source shares one delegate implementation for both, which
/// this mirrors.
class UaePassRedirectInterceptor {
  /// Creates an interceptor bound to [config].
  const UaePassRedirectInterceptor(this.config);

  /// The configuration this interceptor was built for.
  final UaePassConfig config;

  /// Builds the `/idshub/authorize` URL to load in the WebView.
  ///
  /// [isAppInstalled] selects between the native app-to-app `acr_values`
  /// and the push-notification fallback, matching both official SDKs'
  /// behavior.
  Uri buildAuthorizeUrl({required String state, required bool isAppInstalled}) {
    final params = <String, String>{
      'response_type': 'code',
      'client_id': config.clientId,
      'redirect_uri': config.redirectUri.toString(),
      'scope': config.scope,
      'state': state,
      'acr_values': isAppInstalled
          ? kUaePassAcrMobileOnDevice
          : kUaePassAcrPushNotificationFallback,
      'ui_locales': config.locale.wireValue,
      if (config.useFaceVerification) 'verificationType': 'face',
    };
    return config.environment.endpoints.authorize.replace(
      queryParameters: params,
    );
  }

  /// Whether [uri] is UAE Pass's native-app deep link for
  /// [config]'s environment (e.g. `uaepassstg://...`) — the point in the
  /// flow where the WebView must intercept navigation rather than let it
  /// fail to load as a normal page.
  bool isNativeAppLaunchUrl(Uri uri) {
    return uri.scheme == config.environment.iosUrlScheme;
  }

  /// Rewrites the `successURL`/`failureURL` query parameters embedded in
  /// UAE Pass's native-app deep link [uaePassDeepLink] so they point back
  /// into this app via [UaePassConfig.appCallbackScheme] instead of UAE
  /// Pass's own default, then returns the deep link with those parameters
  /// replaced — ready to hand to the OS to launch the native UAE Pass app.
  ///
  /// This is the exact rewrite both official SDKs perform (Android's
  /// `UAEPassAuthenticationDialog`, iOS's `UAEPassWebViewController`)
  /// before calling `Intent`/`UIApplication.open()`.
  Uri rewriteForNativeAppHandoff(Uri uaePassDeepLink) {
    final originalSuccess =
        uaePassDeepLink.queryParameters['successURL'] ??
        uaePassDeepLink.queryParameters['successUrl'];
    final originalFailure =
        uaePassDeepLink.queryParameters['failureURL'] ??
        uaePassDeepLink.queryParameters['failureUrl'];

    final rewrittenParams = Map<String, String>.from(
      uaePassDeepLink.queryParameters,
    );
    if (originalSuccess != null) {
      rewrittenParams['successURL'] = _appCallbackUrl(
        originalUrl: originalSuccess,
      ).toString();
    }
    if (originalFailure != null) {
      rewrittenParams['failureURL'] = _appCallbackUrl(
        originalUrl: originalFailure,
      ).toString();
    }
    return uaePassDeepLink.replace(queryParameters: rewrittenParams);
  }

  /// Builds `config.appCallbackScheme:///resume_authn?url=<originalUrl>` —
  /// matching UAE Pass's own documented example byte-for-byte (three
  /// slashes: an empty host, with `/resume_authn` as the path). Getting
  /// this exact shape wrong is a real, observed cause of the native UAE
  /// Pass app falling back to opening [originalUrl] in the system browser
  /// instead of handing control back to this app.
  Uri _appCallbackUrl({required String originalUrl}) {
    return Uri(
      scheme: config.appCallbackScheme,
      host: '',
      path: '/resume_authn',
      queryParameters: {'url': originalUrl},
    );
  }

  /// Whether [uri] is this app's own callback scheme
  /// (`config.appCallbackScheme://...`) — the point where control returns
  /// from the native UAE Pass app.
  bool isAppCallbackUrl(Uri uri) => uri.scheme == config.appCallbackScheme;

  /// Extracts the original UAE Pass success/failure URL that was wrapped
  /// by [rewriteForNativeAppHandoff], from an incoming [appCallbackUri]
  /// received via `app_links`. Returns `null` if [appCallbackUri] doesn't
  /// carry a recognizable wrapped URL.
  Uri? extractOriginalUrl(Uri appCallbackUri) {
    final wrapped = appCallbackUri.queryParameters['url'];
    if (wrapped == null || wrapped.isEmpty) return null;
    return Uri.tryParse(wrapped);
  }

  /// Whether [uri] matches [UaePassConfig.redirectUri] — the final step of
  /// the OAuth redirect, carrying `code`/`state` (or an error).
  bool isFinalRedirect(Uri uri) {
    return uri.scheme == config.redirectUri.scheme &&
        uri.host == config.redirectUri.host &&
        uri.path == config.redirectUri.path;
  }

  /// Parses the final OAuth redirect [uri] into a [UaePassAuthResult],
  /// validating that its `state` matches [expectedState].
  ///
  /// A user cancelling or being declined inside the UAE Pass UI is treated
  /// as [UaePassAuthCancelled], never as an exception — this is the direct
  /// structural fix for a well-documented issue in prior community
  /// wrappers, where an unguarded null in the equivalent native callback
  /// crashed the whole host app.
  UaePassAuthResult parseFinalRedirect(
    Uri uri, {
    required String expectedState,
  }) {
    final error = uri.queryParameters['error'];
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];

    if (error != null) {
      if (_isCancellationError(error)) {
        return const UaePassAuthCancelled();
      }
      final description = uri.queryParameters['error_description'];
      return UaePassAuthFailure(
        UaePassServerException(
          description ?? 'UAE Pass returned error: $error',
          statusCode: 400,
          errorCode: error,
          errorDescription: description,
        ),
      );
    }

    if (code == null || code.isEmpty) {
      return const UaePassAuthCancelled();
    }

    if (state != expectedState) {
      return UaePassAuthFailure(
        UaePassStateMismatchException(
          'The state returned by UAE Pass did not match the request. '
          'Aborting to avoid a possible CSRF/tampering condition.',
        ),
      );
    }

    return UaePassAuthSuccess(code: code, state: state!);
  }

  bool _isCancellationError(String error) {
    const cancellationErrors = {
      'access_denied',
      'user_cancelled',
      'user_cancel',
      'cancelled',
      'canceled',
      'login_required',
    };
    return cancellationErrors.contains(error.toLowerCase());
  }
}
