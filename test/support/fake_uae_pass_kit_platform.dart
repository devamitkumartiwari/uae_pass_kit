import 'package:uae_pass_kit/uae_pass_kit_platform_interface.dart';

/// A fake [UaePassKitPlatform] that reports a fixed install-detection
/// result instead of going through a real method channel (unavailable
/// under plain `flutter test` without binding initialization).
class FakeUaePassKitPlatform extends UaePassKitPlatform {
  /// Creates a fake platform that reports [isInstalled] for every call.
  FakeUaePassKitPlatform({this.isInstalled = false});

  /// The value [isUaePassAppInstalled] resolves to.
  bool isInstalled;

  @override
  Future<bool> isUaePassAppInstalled({
    required String androidPackageId,
    required String iosUrlScheme,
  }) async {
    return isInstalled;
  }
}
