import 'environment.dart';
import 'locale.dart';

/// The default UAE Pass general-profile scope, sufficient for basic sign-in
/// and profile retrieval.
const String kUaePassDefaultScope = 'urn:uae:digitalid:profile:general';

/// Immutable configuration for a [UaePassEnvironment] integration.
///
/// There is deliberately no default [redirectUri] or [appCallbackScheme] —
/// defaulting either to a demo value would risk an integrator accidentally
/// leaving it in a production build. Both must be explicitly supplied and
/// must match what was registered with UAE Pass during onboarding.
class UaePassConfig {
  /// Creates a UAE Pass configuration.
  const UaePassConfig({
    required this.clientId,
    this.uaePassClientSecret,
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

  /// The client secret issued to you by UAE Pass for [environment],
  /// **required on Android only**.
  ///
  /// UAE Pass's official native Android SDK (which this plugin vendors for
  /// its sign-in flow) requires `client_secret` up front just to obtain an
  /// authorization code, not only to exchange it for a token — an SDK
  /// requirement, not a choice made here. This means the secret is
  /// unavoidably shipped inside the app on Android once this SDK is used,
  /// regardless of whether you otherwise use a backend `tokenExchanger` to
  /// keep it server-side for the token-exchange step. iOS's sign-in flow
  /// does not need it (the authorize page never requires a secret), so it's
  /// left `null` there. Calling [UaePassKit.signIn] on Android without this
  /// set throws [UaePassConfigurationException].
  final String? uaePassClientSecret;

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
