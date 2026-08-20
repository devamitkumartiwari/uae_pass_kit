import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uae_pass_kit/uae_pass_kit.dart';
import 'package:uae_pass_kit/src/auth/uae_pass_web_flow_screen.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/fake_url_launcher_platform.dart';
import '../support/fake_webview_platform.dart';

void main() {
  late FakeWebViewPlatform fakeWebView;
  late FakeUrlLauncherPlatform fakeLauncher;
  late StreamController<Uri> appLinkController;

  setUp(() {
    fakeWebView = FakeWebViewPlatform();
    fakeLauncher = FakeUrlLauncherPlatform();
    appLinkController = StreamController<Uri>.broadcast();
    WebViewPlatform.instance = fakeWebView;
    UrlLauncherPlatform.instance = fakeLauncher;
  });

  tearDown(() async {
    await appLinkController.close();
  });

  for (final environment in UaePassEnvironment.values) {
    group('on ${environment.name}', () {
      final config = UaePassConfig(
        clientId: 'test-client',
        redirectUri: Uri.parse('https://example.com/uaepass/callback'),
        appCallbackScheme: 'testapp',
        environment: environment,
      );
      final interceptor = UaePassRedirectInterceptor(config);

      // Pushes the screen, awaits until setup (build + tap + settle) is
      // done, then hands back the still-pending pop-result future for the
      // caller to await later, once *they've* driven the rest of the
      // interaction and triggered completion. Callers must `await` this
      // function itself before touching `tester` again — but must not
      // await the future it returns until they're ready, since
      // WidgetTester isn't safe to drive concurrently from two in-flight
      // async chains.
      Future<Future<Uri?>> pumpFlow(
        WidgetTester tester, {
        required Uri initialUrl,
      }) async {
        late Future<Uri?> pushFuture;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  pushFuture = Navigator.of(context).push<Uri?>(
                    MaterialPageRoute<Uri?>(
                      builder: (_) => UaePassWebFlowScreen(
                        initialUrl: initialUrl,
                        isNativeAppLaunchUrl: interceptor.isNativeAppLaunchUrl,
                        rewriteForNativeAppHandoff:
                            interceptor.rewriteForNativeAppHandoff,
                        isAppCallbackUrl: interceptor.isAppCallbackUrl,
                        extractOriginalUrl: interceptor.extractOriginalUrl,
                        isFinalUrl: interceptor.isFinalRedirect,
                        appLinkStream: appLinkController.stream,
                      ),
                    ),
                  );
                },
                child: const Text('start'),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(ElevatedButton));
        await tester.pumpAndSettle();
        return pushFuture;
      }

      testWidgets('loads the authorize URL on start', (tester) async {
        final authorizeUrl = interceptor.buildAuthorizeUrl(
          state: 'state-123',
          isAppInstalled: true,
        );

        final resultFuture = await pumpFlow(tester, initialUrl: authorizeUrl);

        expect(fakeWebView.lastController, isNotNull);
        expect(fakeWebView.lastController!.loadedUris, contains(authorizeUrl));

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(await resultFuture, isNull);
      });

      testWidgets('intercepts the native app deep link, rewrites the handoff, '
          'and launches it externally', (tester) async {
        final authorizeUrl = interceptor.buildAuthorizeUrl(
          state: 'state-123',
          isAppInstalled: true,
        );

        final resultFuture = await pumpFlow(tester, initialUrl: authorizeUrl);

        final deepLink = Uri(
          scheme: environment.iosUrlScheme,
          host: 'authenticate',
          queryParameters: {
            'successURL': 'https://stg-id.uaepass.ae/success',
            'failureURL': 'https://stg-id.uaepass.ae/failure',
          },
        );

        final decision = await fakeWebView.lastController!
            .simulateNavigationAttempt(deepLink);

        expect(decision, NavigationDecision.prevent);
        await tester.pump();

        expect(fakeLauncher.launchedUrls, hasLength(1));
        final launchedUri = Uri.parse(fakeLauncher.launchedUrls.single);
        expect(launchedUri.scheme, environment.iosUrlScheme);
        final rewrittenSuccess = Uri.parse(
          launchedUri.queryParameters['successURL']!,
        );
        expect(rewrittenSuccess.scheme, 'testapp');
        expect(
          rewrittenSuccess.queryParameters['url'],
          'https://stg-id.uaepass.ae/success',
        );

        // Clean up: close the still-open screen.
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(await resultFuture, isNull);
      });

      testWidgets(
        'resumes into the WebView when the app-callback scheme fires',
        (tester) async {
          final authorizeUrl = interceptor.buildAuthorizeUrl(
            state: 'state-123',
            isAppInstalled: true,
          );

          final resultFuture = await pumpFlow(tester, initialUrl: authorizeUrl);

          final callback = Uri(
            scheme: 'testapp',
            host: 'resume_authn',
            queryParameters: {
              'url': config.redirectUri
                  .replace(queryParameters: {'code': 'abc', 'state': 'xyz'})
                  .toString(),
            },
          );
          appLinkController.add(callback);
          await tester.pump();
          await tester.pump();

          expect(
            fakeWebView.lastController!.loadedUris.last.queryParameters['code'],
            'abc',
          );

          await tester.tap(find.byIcon(Icons.close));
          await tester.pumpAndSettle();
          expect(await resultFuture, isNull);
        },
      );

      testWidgets('pops with the redirect URI once the final redirect loads', (
        tester,
      ) async {
        final authorizeUrl = interceptor.buildAuthorizeUrl(
          state: 'state-123',
          isAppInstalled: true,
        );

        final resultFuture = await pumpFlow(tester, initialUrl: authorizeUrl);

        final finalUri = config.redirectUri.replace(
          queryParameters: {'code': 'abc123', 'state': 'state-123'},
        );
        await fakeWebView.lastController!.simulateNavigationAttempt(finalUri);
        await tester.pumpAndSettle();

        final result = await resultFuture;
        expect(result, finalUri);
      });

      testWidgets('pops with null when the user closes the screen', (
        tester,
      ) async {
        final authorizeUrl = interceptor.buildAuthorizeUrl(
          state: 'state-123',
          isAppInstalled: true,
        );

        final resultFuture = await pumpFlow(tester, initialUrl: authorizeUrl);

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        final result = await resultFuture;
        expect(result, isNull);
      });
    });
  }
}
