import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uae_pass_kit/src/api/uae_pass_http.dart';
import 'package:uae_pass_kit/uae_pass_kit.dart';
import 'package:uae_pass_kit/uae_pass_kit_platform_interface.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'support/fake_uae_pass_kit_platform.dart';
import 'support/fake_webview_platform.dart';
import 'support/multipart_mock_client.dart';

class _MockTokenExchanger extends Mock implements UaePassTokenExchanger {}

class _MockDocumentShareBackend extends Mock
    implements UaePassDocumentShareBackend {}

void main() {
  setUp(() {
    // requestDocumentShare()/signIn()/signDocument() check install status
    // via UaePassKitPlatform.instance, which defaults to a real method
    // channel — unavailable without TestWidgetsFlutterBinding. A fake
    // keeps these tests plugin-logic-only.
    UaePassKitPlatform.instance = FakeUaePassKitPlatform();
  });

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
    registerFallbackValue(
      UaePassDocumentShareRequest(
        accessToken: 't',
        emiratesId: 'e',
        uuid: 'u',
        documents: const [],
        successUrl: Uri.parse('testapp://success'),
        failureUrl: Uri.parse('testapp://failure'),
        origin: UaePassDocumentShareOrigin.mobile,
      ),
    );
  });

  final config = UaePassConfig(
    clientId: 'client-1',
    redirectUri: Uri.parse('https://example.com/cb'),
    appCallbackScheme: 'testapp',
    environment: UaePassEnvironment.staging,
  );

  UaePassKit buildClient({
    required MockClient mockClient,
    UaePassTokenExchanger? tokenExchanger,
    UaePassSigningTokenExchanger? signingTokenExchanger,
    UaePassDocumentShareBackend? documentShareBackend,
  }) {
    return UaePassKit(
      config: config,
      tokenExchanger: tokenExchanger ?? _MockTokenExchanger(),
      signingTokenExchanger: signingTokenExchanger,
      documentShareBackend: documentShareBackend,
      httpClient: UaePassHttpClient(client: mockClient),
    );
  }

  group('getProfile', () {
    test(
      'calls /idshub/userinfo with the token\'s Authorization header',
      () async {
        http.BaseRequest? captured;
        final mock = MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({'sub': 'sub-1', 'fullnameEN': 'Test User'}),
            200,
          );
        });
        final client = buildClient(mockClient: mock);

        final profile = await client.getProfile(
          const UaePassTokenResponse(accessToken: 'tok', tokenType: 'Bearer'),
        );

        expect(profile.sub, 'sub-1');
        expect(captured!.url, config.environment.endpoints.userInfo);
        expect(captured!.headers['Authorization'], 'Bearer tok');
      },
    );
  });

  group('exchangeAuthorizationCode / refreshAccessToken', () {
    test('delegates to the injected tokenExchanger with the configured '
        'redirectUri', () async {
      final exchanger = _MockTokenExchanger();
      when(
        () => exchanger.exchangeAuthorizationCode(
          code: any(named: 'code'),
          redirectUri: any(named: 'redirectUri'),
        ),
      ).thenAnswer(
        (_) async =>
            const UaePassTokenResponse(accessToken: 'a', tokenType: 'Bearer'),
      );

      final client = buildClient(
        mockClient: MockClient((_) async => http.Response('{}', 200)),
        tokenExchanger: exchanger,
      );

      final result = await client.exchangeAuthorizationCode('code-1');
      expect(result.accessToken, 'a');
      verify(
        () => exchanger.exchangeAuthorizationCode(
          code: 'code-1',
          redirectUri: config.redirectUri,
        ),
      ).called(1);
    });

    test('delegates refresh to the injected tokenExchanger', () async {
      final exchanger = _MockTokenExchanger();
      when(
        () => exchanger.refreshToken(refreshToken: any(named: 'refreshToken')),
      ).thenAnswer(
        (_) async =>
            const UaePassTokenResponse(accessToken: 'b', tokenType: 'Bearer'),
      );

      final client = buildClient(
        mockClient: MockClient((_) async => http.Response('{}', 200)),
        tokenExchanger: exchanger,
      );

      final result = await client.refreshAccessToken('refresh-1');
      expect(result.accessToken, 'b');
      verify(() => exchanger.refreshToken(refreshToken: 'refresh-1')).called(1);
    });
  });

  group('logoutUrl / logout', () {
    test('logoutUrl carries the redirect_uri UAE Pass documents', () {
      final client = buildClient(
        mockClient: MockClient((_) async => http.Response('{}', 200)),
      );
      final uri = client.logoutUrl();
      expect(uri.path, '/idshub/logout');
      expect(
        uri.queryParameters['redirect_uri'],
        config.redirectUri.toString(),
      );
    });

    test('logout clears WebView cookies and best-effort hits the logout '
        'endpoint, never throwing on a non-JSON response', () async {
      final fakeWebView = FakeWebViewPlatform();
      WebViewPlatform.instance = fakeWebView;

      var logoutCalled = false;
      final mock = MockClient((request) async {
        logoutCalled = true;
        return http.Response('not-json', 200);
      });
      final client = buildClient(mockClient: mock);

      await client.logout();

      expect(logoutCalled, isTrue);
      expect(fakeWebView.lastController, isNull); // no webview created
    });
  });

  group('requestDocumentShare', () {
    test('throws UaePassConfigurationException without a backend', () {
      final client = buildClient(
        mockClient: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        () => client
            .requestDocumentShare(
              UaePassDocumentShareRequest(
                accessToken: 't',
                emiratesId: 'e',
                uuid: 'u',
                documents: const [],
                successUrl: Uri.parse('testapp://success'),
                failureUrl: Uri.parse('testapp://failure'),
                origin: UaePassDocumentShareOrigin.mobile,
              ),
            )
            .drain<void>(),
        throwsA(isA<UaePassConfigurationException>()),
      );
    });

    test('emits DocumentShareComplete once every item reaches a terminal '
        'state', () async {
      final backend = _MockDocumentShareBackend();
      when(() => backend.createShareRequest(any())).thenAnswer(
        (_) async => const UaePassDocumentShareHandle(
          proofOfPresentationRequestId: 'pop-1',
        ),
      );
      when(() => backend.fetchStatus('pop-1')).thenAnswer(
        (_) async => [
          UaePassDocumentShareItem.fromJson({
            'documentType': 'EmiratesId',
            'reqAuthorized': 'Y',
          }),
        ],
      );

      final client = buildClient(
        mockClient: MockClient((_) async => http.Response('{}', 200)),
        documentShareBackend: backend,
      );

      final request = UaePassDocumentShareRequest(
        accessToken: 'tok',
        emiratesId: 'eid',
        uuid: 'uuid-1',
        documents: const [
          UaePassDocumentRequestItem(documentType: 'EmiratesId'),
        ],
        successUrl: Uri.parse('testapp://doc/success'),
        failureUrl: Uri.parse('testapp://doc/failure'),
        origin: UaePassDocumentShareOrigin.web,
      );

      final statuses = await client.requestDocumentShare(request).toList();
      expect(statuses.last, isA<DocumentShareComplete>());
      final complete = statuses.last as DocumentShareComplete;
      expect(
        complete.items.single.state,
        UaePassDocumentAuthorizationState.authorized,
      );
    });

    test('emits DocumentShareTimedOut once the deadline passes without a '
        'terminal state', () async {
      final backend = _MockDocumentShareBackend();
      when(() => backend.createShareRequest(any())).thenAnswer(
        (_) async => const UaePassDocumentShareHandle(
          proofOfPresentationRequestId: 'pop-1',
        ),
      );
      when(() => backend.fetchStatus('pop-1')).thenAnswer(
        (_) async => [
          UaePassDocumentShareItem.fromJson({
            'documentType': 'EmiratesId',
            'reqAuthorized': 'P',
          }),
        ],
      );

      final client = buildClient(
        mockClient: MockClient((_) async => http.Response('{}', 200)),
        documentShareBackend: backend,
      );

      final request = UaePassDocumentShareRequest(
        accessToken: 'tok',
        emiratesId: 'eid',
        uuid: 'uuid-1',
        documents: const [
          UaePassDocumentRequestItem(documentType: 'EmiratesId'),
        ],
        successUrl: Uri.parse('testapp://doc/success'),
        failureUrl: Uri.parse('testapp://doc/failure'),
        origin: UaePassDocumentShareOrigin.web,
      );

      final statuses = await client
          .requestDocumentShare(
            request,
            timeout: const Duration(milliseconds: 1),
            pollInterval: const Duration(milliseconds: 1),
          )
          .toList();
      expect(statuses.last, isA<DocumentShareTimedOut>());
    });
  });

  group('signing process calls', () {
    test('createSigningProcess uploads a multipart request with the '
        'process JSON and document bytes', () async {
      http.MultipartRequest? captured;
      final mock = mockMultipartClient(
        onRequest: (request) => captured = request,
        jsonBody: jsonEncode({
          'id': 'proc-1',
          'Tasks': {'pending': <dynamic>[]},
          'documents': <dynamic>[],
        }),
      );
      final client = buildClient(mockClient: mock);

      final process = await client.createSigningProcess(
        signingToken: const UaePassTokenResponse(
          accessToken: 'sign-tok',
          tokenType: 'Bearer',
        ),
        request: UaePassSigningRequest(
          documentBytes: Uint8List.fromList([1, 2, 3]),
          documentFileName: 'doc.pdf',
          finishCallbackUrl: Uri.parse('testapp://sign/finish'),
          signer: const UaePassSigner(
            fields: [
              UaePassSignatureField(
                name: 's1',
                pageNumber: 1,
                rectangle: UaePassSignatureRectangle(
                  x: 0,
                  y: 0,
                  width: 10,
                  height: 10,
                ),
              ),
            ],
          ),
        ),
      );

      expect(process.id, 'proc-1');
      expect(captured!.url, config.environment.endpoints.signerProcesses);
      expect(captured!.headers['Authorization'], 'Bearer sign-tok');
      expect(captured!.files.single.field, 'document');
      expect(captured!.files.single.filename, 'doc.pdf');
    });

    test(
      'deleteSigningProcess issues a DELETE against the process id',
      () async {
        http.BaseRequest? captured;
        final mock = MockClient((request) async {
          captured = request;
          return http.Response('', 200);
        });
        final client = buildClient(mockClient: mock);

        await client.deleteSigningProcess(
          signingToken: const UaePassTokenResponse(
            accessToken: 'sign-tok',
            tokenType: 'Bearer',
          ),
          processId: 'proc-1',
        );

        expect(captured!.method, 'DELETE');
        expect(
          captured!.url,
          config.environment.endpoints.deleteSignerProcess('proc-1'),
        );
      },
    );

    test('downloadSignedDocument returns the raw signed PDF bytes', () async {
      final mock = MockClient((request) async {
        return http.Response.bytes([9, 9, 9], 200);
      });
      final client = buildClient(mockClient: mock);

      final bytes = await client.downloadSignedDocument(
        signingToken: const UaePassTokenResponse(
          accessToken: 'sign-tok',
          tokenType: 'Bearer',
        ),
        documentId: 'doc-1',
      );

      expect(bytes, [9, 9, 9]);
    });
  });
}
