import 'package:flutter_test/flutter_test.dart';
import 'package:uae_pass_kit/uae_pass_kit.dart';

void main() {
  group('UaePassEnvironment', () {
    test('exposes exactly staging and production — no qa/dev', () {
      expect(UaePassEnvironment.values.map((e) => e.name).toSet(), {
        'staging',
        'production',
      });
    });

    test('staging points at the documented staging host and package', () {
      const env = UaePassEnvironment.staging;
      expect(env.identityBaseUrl, 'https://stg-id.uaepass.ae');
      expect(env.androidPackageId, 'ae.uaepass.mainapp.stg');
      expect(env.iosUrlScheme, 'uaepassstg');
    });

    test('production points at the documented production host and package', () {
      const env = UaePassEnvironment.production;
      expect(env.identityBaseUrl, 'https://id.uaepass.ae');
      expect(env.androidPackageId, 'ae.uaepass.mainapp');
      expect(env.iosUrlScheme, 'uaepass');
    });

    for (final environment in UaePassEnvironment.values) {
      group('${environment.name} endpoints', () {
        final endpoints = environment.endpoints;

        test('every identity endpoint stays on the identity base URL', () {
          for (final uri in [
            endpoints.authorize,
            endpoints.token,
            endpoints.userInfo,
            endpoints.logout,
            endpoints.introspect,
          ]) {
            expect(
              uri.toString(),
              startsWith(environment.identityBaseUrl),
              reason: '$uri should be under ${environment.identityBaseUrl}',
            );
          }
        });

        test('authorize/token/userinfo/logout use the documented paths', () {
          expect(endpoints.authorize.path, '/idshub/authorize');
          expect(endpoints.token.path, '/idshub/token');
          expect(endpoints.userInfo.path, '/idshub/userinfo');
          expect(endpoints.logout.path, '/idshub/logout');
          expect(endpoints.introspect.path, '/idshub/introspect');
        });

        test('signing endpoints use the documented esignsp/v2 paths', () {
          expect(
            endpoints.signingToken.path,
            '/trustedx-authserver/oauth/main-as/token',
          );
          expect(
            endpoints.signerProcesses.path,
            '/trustedx-resources/esignsp/v2/signer_processes',
          );
          expect(
            endpoints.signerProcess('abc-123').path,
            '/trustedx-resources/esignsp/v2/signer_processes/abc-123',
          );
          expect(
            endpoints.signedDocument('doc-1').path,
            '/trustedx-resources/esignsp/v2/documents/doc-1/content',
          );
        });
      });
    }
  });
}
