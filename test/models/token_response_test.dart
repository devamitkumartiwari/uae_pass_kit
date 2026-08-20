import 'package:flutter_test/flutter_test.dart';
import 'package:uae_pass_kit/uae_pass_kit.dart';

void main() {
  group('UaePassTokenResponse.fromJson', () {
    test('parses the documented response shape', () {
      final response = UaePassTokenResponse.fromJson({
        'access_token': '67f2536e-abcd',
        'token_type': 'Bearer',
        'expires_in': 3600,
        'scope': 'urn:uae:digitalid:profile:general',
      });
      expect(response.accessToken, '67f2536e-abcd');
      expect(response.tokenType, 'Bearer');
      expect(response.expiresIn, 3600);
      expect(response.refreshToken, isNull);
      expect(response.idToken, isNull);
      expect(response.authorizationHeaderValue, 'Bearer 67f2536e-abcd');
    });

    test('defaults token_type to Bearer when absent', () {
      final response = UaePassTokenResponse.fromJson({'access_token': 'abc'});
      expect(response.tokenType, 'Bearer');
    });

    test('captures refresh_token/id_token defensively when present, even '
        'though UAE Pass\'s documented response omits them', () {
      final response = UaePassTokenResponse.fromJson({
        'access_token': 'abc',
        'token_type': 'Bearer',
        'refresh_token': 'refresh-1',
        'id_token': 'id-1',
      });
      expect(response.refreshToken, 'refresh-1');
      expect(response.idToken, 'id-1');
    });
  });
}
