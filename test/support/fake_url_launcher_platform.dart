import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// A fake [UrlLauncherPlatform] that records every launch attempt instead
/// of actually opening a URL, so tests can assert on what
/// [UaePassWebFlowScreen] tries to launch when handing off to the native
/// UAE Pass app.
class FakeUrlLauncherPlatform extends UrlLauncherPlatform {
  /// Every URL passed to [launchUrl], in order.
  final List<String> launchedUrls = [];

  /// Whether [canLaunch] should report the URL as launchable.
  bool canLaunchResult = true;

  /// Whether [launchUrl] should report success.
  bool launchResult = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => canLaunchResult;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    return launchResult;
  }
}
