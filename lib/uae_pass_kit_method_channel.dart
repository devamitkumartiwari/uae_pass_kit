import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'uae_pass_kit_platform_interface.dart';

/// An implementation of [UaePassKitPlatform] that uses method channels.
class MethodChannelUaePassKit extends UaePassKitPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('uae_pass_kit');

  @override
  Future<bool> isUaePassAppInstalled({
    required String androidPackageId,
    required String iosUrlScheme,
  }) async {
    final installed = await methodChannel.invokeMethod<bool>(
      'isUaePassAppInstalled',
      {'androidPackageId': androidPackageId, 'iosUrlScheme': iosUrlScheme},
    );
    return installed ?? false;
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
  }) {
    return methodChannel.invokeMethod<void>('setUpEnvironment', {
      'clientId': clientId,
      'clientSecret': clientSecret,
      'isProduction': isProduction,
      'appCallbackScheme': appCallbackScheme,
      'uaePassScheme': uaePassScheme,
      'redirectUri': redirectUri.toString(),
      'scope': scope,
      'language': language,
    });
  }

  @override
  Future<String?> nativeSignIn({
    required String state,
    required Uri authorizeUrl,
  }) {
    return methodChannel.invokeMethod<String>('signIn', {
      'state': state,
      'authorizeUrl': authorizeUrl.toString(),
    });
  }

  @override
  Future<String?> openSigningUrl({
    required String url,
    required Uri finishUri,
  }) {
    return methodChannel.invokeMethod<String>('openSigningUrl', {
      'url': url,
      'finishScheme': finishUri.scheme,
      'finishHost': finishUri.host,
      'finishPath': finishUri.path,
    });
  }

  @override
  Future<void> nativeSignOut() {
    return methodChannel.invokeMethod<void>('signOut');
  }
}
