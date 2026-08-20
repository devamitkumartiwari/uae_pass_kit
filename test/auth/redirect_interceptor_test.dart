import 'package:flutter_test/flutter_test.dart';
import 'package:uae_pass_kit/uae_pass_kit.dart';

void main() {
  // Run every case against both staging and production so the environment
  // switch can never silently break install detection or the WebView
  // interception — the direct structural fix for GitHub issue #2's
  // sandbox_stage-in-production incident.
  for (final environment in UaePassEnvironment.values) {
    group('UaePassRedirectInterceptor on ${environment.name}', () {
      final config = UaePassConfig(
        clientId: 'test-client-id',
        redirectUri: Uri.parse('https://example.com/uaepass/callback'),
        appCallbackScheme: 'testapp',
        environment: environment,
      );
      final interceptor = UaePassRedirectInterceptor(config);

      test('buildAuthorizeUrl targets the correct environment host', () {
        final uri = interceptor.buildAuthorizeUrl(
          state: 'state-1',
          isAppInstalled: true,
        );
        expect(uri.host, Uri.parse(environment.identityBaseUrl).host);
        expect(uri.path, '/idshub/authorize');
        expect(uri.queryParameters['client_id'], 'test-client-id');
        expect(uri.queryParameters['state'], 'state-1');
        expect(uri.queryParameters['response_type'], 'code');
      });

      test('selects the mobile-on-device acr_values when the app is '
          'installed', () {
        final uri = interceptor.buildAuthorizeUrl(
          state: 's',
          isAppInstalled: true,
        );
        expect(uri.queryParameters['acr_values'], kUaePassAcrMobileOnDevice);
      });

      test('selects the push-notification fallback acr_values when the '
          'app is not installed', () {
        final uri = interceptor.buildAuthorizeUrl(
          state: 's',
          isAppInstalled: false,
        );
        expect(
          uri.queryParameters['acr_values'],
          kUaePassAcrPushNotificationFallback,
        );
      });

      test('recognizes this environment\'s native app deep link scheme', () {
        final deepLink = Uri.parse('${environment.iosUrlScheme}://auth');
        expect(interceptor.isNativeAppLaunchUrl(deepLink), isTrue);
      });

      test('does not mistake the other environment\'s scheme for this one', () {
        final otherEnvironment = environment == UaePassEnvironment.staging
            ? UaePassEnvironment.production
            : UaePassEnvironment.staging;
        final otherDeepLink = Uri.parse(
          '${otherEnvironment.iosUrlScheme}://auth',
        );
        expect(interceptor.isNativeAppLaunchUrl(otherDeepLink), isFalse);
      });

      test('rewrites successURL/failureURL to this app\'s callback scheme', () {
        final deepLink = Uri.parse(
          '${environment.iosUrlScheme}://authenticate'
          '?successURL=${Uri.encodeComponent('https://stg-id.uaepass.ae/s')}'
          '&failureURL=${Uri.encodeComponent('https://stg-id.uaepass.ae/f')}',
        );

        final rewritten = interceptor.rewriteForNativeAppHandoff(deepLink);

        expect(rewritten.scheme, environment.iosUrlScheme);
        final success = Uri.parse(rewritten.queryParameters['successURL']!);
        final failure = Uri.parse(rewritten.queryParameters['failureURL']!);
        expect(success.scheme, 'testapp');
        expect(success.queryParameters['url'], 'https://stg-id.uaepass.ae/s');
        expect(failure.scheme, 'testapp');
        expect(failure.queryParameters['url'], 'https://stg-id.uaepass.ae/f');
      });

      test('recognizes this app\'s own callback scheme', () {
        final callback = Uri.parse('testapp://resume_authn?url=https://x');
        expect(interceptor.isAppCallbackUrl(callback), isTrue);
        expect(
          interceptor.isAppCallbackUrl(Uri.parse('otherapp://resume')),
          isFalse,
        );
      });

      test('extracts the original wrapped URL from an app-callback link', () {
        final callback = Uri(
          scheme: 'testapp',
          host: 'resume_authn',
          queryParameters: {'url': 'https://stg-id.uaepass.ae/success?a=b'},
        );
        final original = interceptor.extractOriginalUrl(callback);
        expect(original.toString(), 'https://stg-id.uaepass.ae/success?a=b');
      });

      test('returns null when there is nothing to extract', () {
        final callback = Uri.parse('testapp://resume_authn');
        expect(interceptor.extractOriginalUrl(callback), isNull);
      });

      test('recognizes the configured redirect URI as the final redirect', () {
        final finalUri = config.redirectUri.replace(
          queryParameters: {'code': 'abc', 'state': 's'},
        );
        expect(interceptor.isFinalRedirect(finalUri), isTrue);
      });

      test('does not treat an unrelated URL as the final redirect', () {
        expect(
          interceptor.isFinalRedirect(Uri.parse('https://example.com/other')),
          isFalse,
        );
      });

      group('parseFinalRedirect', () {
        test('returns success when code and state match', () {
          final uri = config.redirectUri.replace(
            queryParameters: {'code': 'the-code', 'state': 'expected'},
          );
          final result = interceptor.parseFinalRedirect(
            uri,
            expectedState: 'expected',
          );
          expect(result, isA<UaePassAuthSuccess>());
          expect((result as UaePassAuthSuccess).code, 'the-code');
          expect(result.state, 'expected');
        });

        test('fails with a state-mismatch exception rather than '
            'proceeding, on a state mismatch', () {
          final uri = config.redirectUri.replace(
            queryParameters: {'code': 'the-code', 'state': 'tampered'},
          );
          final result = interceptor.parseFinalRedirect(
            uri,
            expectedState: 'expected',
          );
          expect(result, isA<UaePassAuthFailure>());
          expect(
            (result as UaePassAuthFailure).exception,
            isA<UaePassStateMismatchException>(),
          );
        });

        test('treats access_denied as cancellation, not an exception', () {
          final uri = config.redirectUri.replace(
            queryParameters: {'error': 'access_denied'},
          );
          final result = interceptor.parseFinalRedirect(
            uri,
            expectedState: 'expected',
          );
          expect(result, isA<UaePassAuthCancelled>());
        });

        test('treats a missing code as cancellation, never as a crash', () {
          final uri = config.redirectUri.replace(queryParameters: {});
          final result = interceptor.parseFinalRedirect(
            uri,
            expectedState: 'expected',
          );
          expect(result, isA<UaePassAuthCancelled>());
        });

        test('surfaces a non-cancellation server error as a failure', () {
          final uri = config.redirectUri.replace(
            queryParameters: {
              'error': 'invalid_scope',
              'error_description': 'The requested scope is invalid.',
            },
          );
          final result = interceptor.parseFinalRedirect(
            uri,
            expectedState: 'expected',
          );
          expect(result, isA<UaePassAuthFailure>());
          final failure = result as UaePassAuthFailure;
          expect(failure.exception, isA<UaePassServerException>());
          expect(
            (failure.exception as UaePassServerException).errorCode,
            'invalid_scope',
          );
        });
      });
    });
  }
}
