import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'uae_pass_kit_method_channel.dart';

/// The platform-specific interface this plugin's single piece of native
/// code — checking whether the UAE Pass app is installed — is implemented
/// against.
///
/// Every other capability (the OAuth flow, profile/token/document/signing
/// API calls) is implemented in pure Dart in `lib/src/`, deliberately not
/// routed through a platform channel — see the plugin README for why.
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
}
