import 'environment.dart';
import 'locale.dart';

/// The default UAE Pass general-profile scope, sufficient for basic sign-in
/// and profile retrieval.
const String kUaePassDefaultScope = 'urn:uae:digitalid:profile:general';

/// Immutable configuration for a [UaePassEnvironment] integration.
///
/// There is deliberately no default [redirectUri] or [appCallbackScheme] —
/// unlike `flutter_uae_pass`, which defaults `redirectUri` to a demo URL
/// (`https://oauthtest.com/authorization/return`) that integrators could
/// accidentally leave in a production build. Both must be explicitly
/// supplied and must match what was registered with UAE Pass during
/// onboarding.
class UaePassConfig {
  /// Creates a UAE Pass configuration.
  const UaePassConfig({
    required this.clientId,
    required this.redirectUri,
    required this.appCallbackScheme,
    required this.environment,
    this.scope = kUaePassDefaultScope,
    this.locale = UaePassLocale.en,
    this.useFaceVerification = false,
  }) : assert(clientId != '', 'clientId must not be empty'),
       assert(scope != '', 'scope must not be empty');

  /// The client ID issued to you by UAE Pass for [environment].
  final String clientId;

  /// The OAuth `redirect_uri` registered with UAE Pass for this app. This is
  /// the URL the plugin's WebView intercepts as the final step of the
  /// authorization-code flow — it does not need to be a reachable server,
  /// but it must exactly match what was registered during onboarding.
  final Uri redirectUri;

  /// This app's own unique custom URL scheme (without `://`), registered
  /// with UAE Pass during onboarding. UAE Pass explicitly warns against
  /// reusing the shared demo scheme (`uaepassdemoapp`) — every integrating
  /// app must use its own.
  ///
  /// This is distinct from [redirectUri]: it is used only for the
  /// intermediate app-to-app handoff, receiving control back from the
  /// native UAE Pass app before the flow resumes inside the plugin's
  /// WebView to reach [redirectUri].
  final String appCallbackScheme;

  /// Which UAE Pass environment to integrate against.
  final UaePassEnvironment environment;

  /// The requested OAuth scope(s), space-separated.
  final String scope;

  /// The display language for the UAE Pass hosted UI.
  final UaePassLocale locale;

  /// Whether to request UAE Pass's face-verification login variant.
  final bool useFaceVerification;

  /// The full `scheme://` prefix for [appCallbackScheme].
  String get appCallbackSchemePrefix => '$appCallbackScheme://';
}
