import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uae_pass_kit/src/api/uae_pass_http.dart';
import 'package:uae_pass_kit/uae_pass_kit.dart';

import 'support/multipart_mock_client.dart';

void main() {
  group('UaePassDirectTokenExchanger', () {
    test('exchangeAuthorizationCode sends the documented grant_type/code/'
        'redirect_uri fields with HTTP Basic auth', () async {
      http.MultipartRequest? captured;
      final mock = mockMultipartClient(
        onRequest: (request) => captured = request,
        jsonBody: jsonEncode({'access_token': 'tok', 'token_type': 'Bearer'}),
      );

      final exchanger = UaePassDirectTokenExchanger(
        clientId: 'client-1',
        clientSecret: 'secret-1',
        environment: UaePassEnvironment.staging,
        httpClient: UaePassHttpClient(client: mock),
      );

      final response = await exchanger.exchangeAuthorizationCode(
        code: 'auth-code',
        redirectUri: Uri.parse('https://example.com/cb'),
      );

      expect(response.accessToken, 'tok');
      expect(
        captured!.url.toString(),
        UaePassEnvironment.staging.endpoints.token.toString(),
      );
      expect(captured!.fields['grant_type'], 'authorization_code');
      expect(captured!.fields['code'], 'auth-code');
      expect(captured!.fields['redirect_uri'], 'https://example.com/cb');

      final authHeader = captured!.headers['Authorization']!;
      expect(authHeader, startsWith('Basic '));
      final decoded = utf8.decode(
        base64Decode(authHeader.substring('Basic '.length)),
      );
      expect(decoded, 'client-1:secret-1');
    });

    test('refreshToken sends grant_type=refresh_token', () async {
      http.MultipartRequest? captured;
      final mock = mockMultipartClient(
        onRequest: (request) => captured = request,
        jsonBody: jsonEncode({
          'access_token': 'new-tok',
          'token_type': 'Bearer',
        }),
      );

      final exchanger = UaePassDirectTokenExchanger(
        clientId: 'client-1',
        clientSecret: 'secret-1',
        environment: UaePassEnvironment.production,
        httpClient: UaePassHttpClient(client: mock),
      );

      final response = await exchanger.refreshToken(refreshToken: 'refresh-1');

      expect(response.accessToken, 'new-tok');
      expect(captured!.fields['grant_type'], 'refresh_token');
      expect(captured!.fields['refresh_token'], 'refresh-1');
      expect(
        captured!.url.toString(),
        UaePassEnvironment.production.endpoints.token.toString(),
      );
    });
  });

  group('UaePassDirectSigningTokenExchanger', () {
    test('obtainSigningToken sends grant_type=client_credentials against '
        'the signing token endpoint', () async {
      http.MultipartRequest? captured;
      final mock = mockMultipartClient(
        onRequest: (request) => captured = request,
        jsonBody: jsonEncode({
          'access_token': 'sign-tok',
          'token_type': 'Bearer',
        }),
      );

      final exchanger = UaePassDirectSigningTokenExchanger(
        clientId: 'client-1',
        clientSecret: 'secret-1',
        environment: UaePassEnvironment.staging,
        httpClient: UaePassHttpClient(client: mock),
      );

      final response = await exchanger.obtainSigningToken(
        signingScope: 'urn:safelayer:eidas:sign:process:document',
      );

      expect(response.accessToken, 'sign-tok');
      expect(captured!.fields['grant_type'], 'client_credentials');
      expect(
        captured!.url.toString(),
        UaePassEnvironment.staging.endpoints.signingToken.toString(),
      );
    });
  });
}
