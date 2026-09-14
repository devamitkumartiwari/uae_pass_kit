import 'package:uae_pass_kit/uae_pass_kit_platform_interface.dart';

/// A fake [UaePassKitPlatform] that records/replays fixed results instead
/// of going through a real method channel (unavailable under plain
/// `flutter test` without binding initialization).
class FakeUaePassKitPlatform extends UaePassKitPlatform {
  /// Creates a fake platform that reports [isInstalled] for every call.
  FakeUaePassKitPlatform({this.isInstalled = false});

  /// The value [isUaePassAppInstalled] resolves to.
  bool isInstalled;

  /// The value [nativeSignIn] resolves to, if [nativeSignInError] is null.
  String? nextSignInCode;

  /// If set, [nativeSignIn] throws this instead of returning
  /// [nextSignInCode].
  Object? nativeSignInError;

  /// The value [openSigningUrl] resolves to, if [openSigningUrlError] is
  /// null.
  String? nextSigningResultUrl;

  /// If set, [openSigningUrl] throws this instead of returning
  /// [nextSigningResultUrl].
  Object? openSigningUrlError;

  /// Every call to [setUpEnvironment], most recent last.
  final List<Map<String, Object?>> setUpEnvironmentCalls = [];

  /// The `state` every [nativeSignIn] call was made with, most recent last.
  final List<String> signInStates = [];

  /// Whether [nativeSignOut] has been called.
  bool signOutCalled = false;

  @override
  Future<bool> isUaePassAppInstalled({
    required String androidPackageId,
    required String iosUrlScheme,
  }) async {
    return isInstalled;
  }

  @override
  Future<void> setUpEnvironment({
    required String clientId,
    String? clientSecret,
    required bool isProduction,
    required String appCallbackScheme,
    required String uaePassScheme,
    required Uri redirectUri,
    required String scope,
    required String language,
  }) async {
    setUpEnvironmentCalls.add({
      'clientId': clientId,
      'clientSecret': clientSecret,
      'isProduction': isProduction,
      'appCallbackScheme': appCallbackScheme,
      'uaePassScheme': uaePassScheme,
      'redirectUri': redirectUri,
      'scope': scope,
      'language': language,
    });
  }

  @override
  Future<String?> nativeSignIn({
    required String state,
    required Uri authorizeUrl,
  }) async {
    signInStates.add(state);
    final error = nativeSignInError;
    if (error != null) throw error;
    return nextSignInCode;
  }

  @override
  Future<String?> openSigningUrl({
    required String url,
    required Uri finishUri,
  }) async {
    final error = openSigningUrlError;
    if (error != null) throw error;
    return nextSigningResultUrl;
  }

  @override
  Future<void> nativeSignOut() async {
    signOutCalled = true;
  }
}
