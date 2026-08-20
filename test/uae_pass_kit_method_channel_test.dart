import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uae_pass_kit/uae_pass_kit_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelUaePassKit', () {
    late MethodChannelUaePassKit platform;
    final channel = const MethodChannel('uae_pass_kit');
    final log = <MethodCall>[];

    setUp(() {
      platform = MethodChannelUaePassKit();
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            log.add(call);
            if (call.method == 'isUaePassAppInstalled') {
              final arguments = call.arguments as Map<Object?, Object?>;
              return arguments['androidPackageId'] == 'ae.uaepass.mainapp';
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('forwards androidPackageId/iosUrlScheme and returns the native '
        'result', () async {
      final result = await platform.isUaePassAppInstalled(
        androidPackageId: 'ae.uaepass.mainapp',
        iosUrlScheme: 'uaepass',
      );

      expect(result, isTrue);
      expect(log, hasLength(1));
      expect(log.single.method, 'isUaePassAppInstalled');
      expect(log.single.arguments, {
        'androidPackageId': 'ae.uaepass.mainapp',
        'iosUrlScheme': 'uaepass',
      });
    });

    test(
      'returns false when the native side reports the app is absent',
      () async {
        final result = await platform.isUaePassAppInstalled(
          androidPackageId: 'ae.uaepass.mainapp.stg',
          iosUrlScheme: 'uaepassstg',
        );
        expect(result, isFalse);
      },
    );

    test('defaults to false when the native side returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
      final result = await platform.isUaePassAppInstalled(
        androidPackageId: 'ae.uaepass.mainapp',
        iosUrlScheme: 'uaepass',
      );
      expect(result, isFalse);
    });
  });
}
