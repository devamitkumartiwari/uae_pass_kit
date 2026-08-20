// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uae_pass_kit/uae_pass_kit_platform_interface.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('isUaePassAppInstalled resolves without throwing', (
    WidgetTester tester,
  ) async {
    // Exercises the plugin's one piece of real native code end-to-end on
    // a device/emulator/simulator. The result depends on whether UAE
    // Pass's staging app happens to be installed, so this only asserts
    // the call completes and returns a bool rather than a fixed value.
    final installed = await UaePassKitPlatform.instance.isUaePassAppInstalled(
      androidPackageId: 'ae.uaepass.mainapp.stg',
      iosUrlScheme: 'uaepassstg',
    );
    expect(installed, isA<bool>());
  });
}
