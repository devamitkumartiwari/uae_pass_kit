import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uae_pass_kit/uae_pass_kit.dart';
import 'package:uae_pass_kit/src/api/uae_pass_http.dart';

void main() {
  group('UaePassHttpClient', () {
    test('getJson decodes a JSON object response', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'GET');
        return http.Response(jsonEncode({'ok': true}), 200);
      });
      final client = UaePassHttpClient(client: mock);
      final result = await client.getJson(Uri.parse('https://x/y'));
      expect(result, {'ok': true});
    });

    test('translates a 4xx response into UaePassServerException with the '
        'parsed error/error_description', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'invalid_grant',
            'error_description': 'The code has expired.',
          }),
          400,
        );
      });
      final client = UaePassHttpClient(client: mock);

      await expectLater(
        client.getJson(Uri.parse('https://x/y')),
        throwsA(
          isA<UaePassServerException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.errorCode, 'errorCode', 'invalid_grant')
              .having(
                (e) => e.errorDescription,
                'errorDescription',
                'The code has expired.',
              ),
        ),
      );
    });

    test('translates a non-JSON body into UaePassParsingException', () async {
      final mock = MockClient((request) async {
        return http.Response('not json', 200);
      });
      final client = UaePassHttpClient(client: mock);

      await expectLater(
        client.getJson(Uri.parse('https://x/y')),
        throwsA(isA<UaePassParsingException>()),
      );
    });

    test(
      'translates a transport-level failure into UaePassNetworkException',
      () async {
        final mock = MockClient((request) async {
          throw http.ClientException('boom');
        });
        final client = UaePassHttpClient(client: mock);

        await expectLater(
          client.getJson(Uri.parse('https://x/y')),
          throwsA(isA<UaePassNetworkException>()),
        );
      },
    );

    test('postMultipart sends multipart/form-data, matching UAE Pass\'s '
        'documented token-endpoint requirement', () async {
      final mock = MockClient((request) async {
        expect(
          request.headers['content-type'],
          contains('multipart/form-data'),
        );
        return http.Response(jsonEncode({'access_token': 'abc'}), 200);
      });
      final client = UaePassHttpClient(client: mock);
      final result = await client.postMultipart(
        Uri.parse('https://x/token'),
        fields: {'grant_type': 'authorization_code'},
      );
      expect(result['access_token'], 'abc');
    });

    test(
      'getBytes returns raw response bytes for a successful response',
      () async {
        final mock = MockClient((request) async {
          return http.Response.bytes([1, 2, 3], 200);
        });
        final client = UaePassHttpClient(client: mock);
        final bytes = await client.getBytes(Uri.parse('https://x/file'));
        expect(bytes, [1, 2, 3]);
      },
    );

    test(
      'delete throws UaePassServerException on a 4xx/5xx response',
      () async {
        final mock = MockClient((request) async {
          expect(request.method, 'DELETE');
          return http.Response('', 500);
        });
        final client = UaePassHttpClient(client: mock);
        await expectLater(
          client.delete(Uri.parse('https://x/y')),
          throwsA(isA<UaePassServerException>()),
        );
      },
    );
  });
}
