import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'uae_pass_kit_method_channel.dart';

/// The platform-specific interface this plugin's native code is
/// implemented against.
///
/// Every plain HTTPS API call (token exchange, profile, document
/// upload/poll/download) is implemented in pure Dart in `lib/src/` — see the
/// plugin README. Only the parts of the flow that involve a browser/native
/// UAE Pass app hand-off and the deep-link return are routed through this
/// platform channel, because that hand-off is what proved unreliable when
/// implemented in pure Dart (the flow getting stuck after control bounced
/// out to the UAE Pass app or the system browser).
abstract class UaePassKitPlatform extends PlatformInterface {
  /// Constructs a UaePassKitPlatform.
  UaePassKitPlatform() : super(token: _token);

  static final Object _token = Object();

  static UaePassKitPlatform _instance = MethodChannelUaePassKit();

  /// The default instance of [UaePassKitPlatform] to use.
  ///
  /// Defaults to [MethodChannelUaePassKit].
  static UaePassKitPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [UaePassKitPlatform] when
  /// they register themselves.
  static set instance(UaePassKitPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Returns whether the native UAE Pass app is installed on this device.
  ///
  /// On Android this checks package visibility for [androidPackageId]
  /// (requires the corresponding `<queries>` manifest entry). On iOS this
  /// checks `canOpenURL:` for `$iosUrlScheme://` (requires the
  /// corresponding `LSApplicationQueriesSchemes` `Info.plist` entry). On
  /// web, this always returns `false` — there is no native app to detect.
  Future<bool> isUaePassAppInstalled({
    required String androidPackageId,
    required String iosUrlScheme,
  }) {
    throw UnimplementedError(
      'isUaePassAppInstalled() has not been implemented.',
    );
  }

  /// Pushes this flow's configuration to native code, ahead of
  /// [nativeSignIn] or [openSigningUrl].
  ///
  /// [clientSecret] is no longer used by any platform and is kept only for
  /// compatibility with existing implementations of this interface.
  /// [uaePassScheme] is the native UAE Pass app's own custom URL scheme
  /// (e.g. `uaepassstg`, without `://`) — distinct from
  /// [appCallbackScheme], which is this app's own scheme.
  Future<void> setUpEnvironment({
    required String clientId,
    String? clientSecret,
    required bool isProduction,
    required String appCallbackScheme,
    required String uaePassScheme,
    required Uri redirectUri,
    required String scope,
    required String language,
  }) {
    throw UnimplementedError('setUpEnvironment() has not been implemented.');
  }

  /// Runs the whole UAE Pass sign-in hand-off natively — presenting the
  /// login UI, switching to the native UAE Pass app when installed, and
  /// resuming via the platform's own deep-link mechanism — and returns the
  /// resulting authorization code.
  ///
  /// [authorizeUrl] is pre-built by Dart from [UaePassConfig] and [state];
  /// the native flow starts from it, and rejects a redirect whose `state`
  /// doesn't match it.
  ///
  /// Throws a `PlatformException` with code `"ERROR"` on failure or
  /// cancellation; callers are expected to classify the message the same
  /// way `UaePassKit` classifies an `error` query parameter.
  Future<String?> nativeSignIn({
    required String state,
    required Uri authorizeUrl,
  }) {
    throw UnimplementedError('nativeSignIn() has not been implemented.');
  }

  /// Opens [url] (a UAE Pass e-signature UI URL) natively, applying the
  /// same app-switch/deep-link mechanics as [nativeSignIn], until either
  /// the flow reaches a URL matching [finishUri] (compared by scheme, host
  /// and path) or the resulting URL carries a `status` query parameter —
  /// matching UAE Pass's own documented signing-completion signal.
  ///
  /// Returns the final URL as a string, or `null` if the user cancelled by
  /// closing the native UI.
  Future<String?> openSigningUrl({
    required String url,
    required Uri finishUri,
  }) {
    throw UnimplementedError('openSigningUrl() has not been implemented.');
  }

  /// Clears cookies held by native code's own WebView, as part of
  /// [UaePassKit.logout].
  Future<void> nativeSignOut() {
    throw UnimplementedError('nativeSignOut() has not been implemented.');
  }
}
