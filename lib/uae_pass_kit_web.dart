import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'uae_pass_kit_platform_interface.dart';

/// A web implementation of [UaePassKitPlatform].
///
/// UAE Pass documents a materially different flow for web apps (a plain
/// full-page OAuth2 redirect against a real, reachable `redirect_uri` —
/// see `docs.uaepass.ae/feature-guides/authentication/web-application`)
/// than for mobile (the WebView-interception app-to-app dance this
/// package's `UaePassKit.signIn` implements). There is no native app to
/// detect on web, so this always reports `false`; web integrators should
/// drive the standard redirect flow directly using
/// `UaePassEnvironment.endpoints` and `UaePassKit`'s token/profile calls,
/// which work unchanged on any platform.
class UaePassKitWeb extends UaePassKitPlatform {
  /// Constructs a UaePassKitWeb.
  UaePassKitWeb();

  /// Registers this implementation as the platform instance for web.
  static void registerWith(Registrar registrar) {
    UaePassKitPlatform.instance = UaePassKitWeb();
  }

  @override
  Future<bool> isUaePassAppInstalled({
    required String androidPackageId,
    required String iosUrlScheme,
  }) async {
    return false;
  }
}
