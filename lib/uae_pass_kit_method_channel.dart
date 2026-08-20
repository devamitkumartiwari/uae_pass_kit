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
}
