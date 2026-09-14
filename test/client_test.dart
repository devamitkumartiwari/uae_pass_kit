import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uae_pass_kit/src/api/uae_pass_http.dart';
import 'package:uae_pass_kit/uae_pass_kit.dart';
import 'package:uae_pass_kit/uae_pass_kit_platform_interface.dart';

import 'support/fake_uae_pass_kit_platform.dart';
import 'support/multipart_mock_client.dart';

class _FakeTokenExchanger implements UaePassTokenExchanger {
  _FakeTokenExchanger({
    this._onExchangeAuthorizationCode,
    this._onRefreshToken,
  });

  final Future<UaePassTokenResponse> Function({
    required String code,
    required Uri redirectUri,
  })?
  _onExchangeAuthorizationCode;
  final Future<UaePassTokenResponse> Function({required String refreshToken})?
  _onRefreshToken;

  int exchangeAuthorizationCodeCallCount = 0;
  String? lastCode;
  Uri? lastRedirectUri;

  int refreshTokenCallCount = 0;
  String? lastRefreshToken;

  @override
  Future<UaePassTokenResponse> exchangeAuthorizationCode({
    required String code,
    required Uri redirectUri,
  }) {
    exchangeAuthorizationCodeCallCount++;
    lastCode = code;
    lastRedirectUri = redirectUri;
    return _onExchangeAuthorizationCode!(code: code, redirectUri: redirectUri);
  }

  @override
  Future<UaePassTokenResponse> refreshToken({required String refreshToken}) {
    refreshTokenCallCount++;
    lastRefreshToken = refreshToken;
    return _onRefreshToken!(refreshToken: refreshToken);
  }
}

class _FakeDocumentShareBackend implements UaePassDocumentShareBackend {
  _FakeDocumentShareBackend({
    required this.shareHandle,
    required this.statusesById,
  });

  final UaePassDocumentShareHandle shareHandle;
  final Map<String, List<UaePassDocumentShareItem>> statusesById;

  UaePassDocumentShareRequest? lastRequest;

  @override
  Future<UaePassDocumentShareHandle> createShareRequest(
    UaePassDocumentShareRequest request,
  ) async {
    lastRequest = request;
    return shareHandle;
  }

  @override
  Future<List<UaePassDocumentShareItem>> fetchStatus(
    String proofOfPresentationRequestId,
  ) async {
    return statusesById[proofOfPresentationRequestId] ?? const [];
  }
}

void main() {
  setUp(() {
    // requestDocumentShare()/signIn()/signDocument() check install status
    // via UaePassKitPlatform.instance, which defaults to a real method
    // channel — unavailable without TestWidgetsFlutterBinding. A fake
    // keeps these tests plugin-logic-only.
    UaePassKitPlatform.instance = FakeUaePassKitPlatform();
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
      tokenExchanger: tokenExchanger ?? _FakeTokenExchanger(),
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
      final exchanger = _FakeTokenExchanger(
        onExchangeAuthorizationCode:
            ({required code, required redirectUri}) async =>
                const UaePassTokenResponse(
                  accessToken: 'a',
                  tokenType: 'Bearer',
                ),
      );

      final client = buildClient(
        mockClient: MockClient((_) async => http.Response('{}', 200)),
        tokenExchanger: exchanger,
      );

      final result = await client.exchangeAuthorizationCode('code-1');
      expect(result.accessToken, 'a');
      expect(exchanger.exchangeAuthorizationCodeCallCount, 1);
      expect(exchanger.lastCode, 'code-1');
      expect(exchanger.lastRedirectUri, config.redirectUri);
    });

    test('delegates refresh to the injected tokenExchanger', () async {
      final exchanger = _FakeTokenExchanger(
        onRefreshToken: ({required refreshToken}) async =>
            const UaePassTokenResponse(accessToken: 'b', tokenType: 'Bearer'),
      );

      final client = buildClient(
        mockClient: MockClient((_) async => http.Response('{}', 200)),
        tokenExchanger: exchanger,
      );

      final result = await client.refreshAccessToken('refresh-1');
      expect(result.accessToken, 'b');
      expect(exchanger.refreshTokenCallCount, 1);
      expect(exchanger.lastRefreshToken, 'refresh-1');
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

    test('logout clears native cookies and best-effort hits the logout '
        'endpoint, never throwing on a non-JSON response', () async {
      final fakePlatform = FakeUaePassKitPlatform();
      UaePassKitPlatform.instance = fakePlatform;

      var logoutCalled = false;
      final mock = MockClient((request) async {
        logoutCalled = true;
        return http.Response('not-json', 200);
      });
      final client = buildClient(mockClient: mock);

      await client.logout();

      expect(logoutCalled, isTrue);
      expect(fakePlatform.signOutCalled, isTrue);
    });
  });

  group('signIn', () {
    final androidSecretConfig = UaePassConfig(
      clientId: 'client-1',
      uaePassClientSecret: 'android-secret',
      redirectUri: Uri.parse('https://example.com/cb'),
      appCallbackScheme: 'testapp',
      environment: UaePassEnvironment.staging,
    );

    Future<BuildContext> pumpContext(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return context;
    }

    testWidgets('runs the flow natively and returns the resulting code', (
      tester,
    ) async {
      final fakePlatform = FakeUaePassKitPlatform()
        ..nextSignInCode = 'the-code';
      UaePassKitPlatform.instance = fakePlatform;
      final client = UaePassKit(
        config: androidSecretConfig,
        tokenExchanger: _FakeTokenExchanger(),
      );

      final result = await client.signIn(await pumpContext(tester));

      expect(result, isA<UaePassAuthSuccess>());
      final success = result as UaePassAuthSuccess;
      expect(success.code, 'the-code');
      expect(fakePlatform.signInStates, [success.state]);
      expect(fakePlatform.setUpEnvironmentCalls.single['clientId'], 'client-1');
      expect(
        fakePlatform.setUpEnvironmentCalls.single['clientSecret'],
        'android-secret',
      );
    });

    testWidgets(
      'treats a cancellation-flavored native error as UaePassAuthCancelled, '
      'not a thrown exception',
      (tester) async {
        final fakePlatform = FakeUaePassKitPlatform()
          ..nativeSignInError = PlatformException(
            code: 'ERROR',
            message: 'Authentication Process Canceled By User',
          );
        UaePassKitPlatform.instance = fakePlatform;
        final client = UaePassKit(
          config: androidSecretConfig,
          tokenExchanger: _FakeTokenExchanger(),
        );

        final result = await client.signIn(await pumpContext(tester));

        expect(result, isA<UaePassAuthCancelled>());
      },
    );

    testWidgets(
      'surfaces a non-cancellation native error as UaePassAuthFailure',
      (tester) async {
        final fakePlatform = FakeUaePassKitPlatform()
          ..nativeSignInError = PlatformException(
            code: 'ERROR',
            message: 'Unable to reach UAE Pass',
          );
        UaePassKitPlatform.instance = fakePlatform;
        final client = UaePassKit(
          config: androidSecretConfig,
          tokenExchanger: _FakeTokenExchanger(),
        );

        final result = await client.signIn(await pumpContext(tester));

        expect(result, isA<UaePassAuthFailure>());
        expect(
          (result as UaePassAuthFailure).exception,
          isA<UaePassServerException>(),
        );
      },
    );

    testWidgets('throws UaePassConfigurationException on Android without '
        'uaePassClientSecret', (tester) async {
      UaePassKitPlatform.instance = FakeUaePassKitPlatform();
      final client = UaePassKit(
        config: config, // no uaePassClientSecret
        tokenExchanger: _FakeTokenExchanger(),
      );

      final context = await pumpContext(tester);
      expect(
        () => client.signIn(context),
        throwsA(isA<UaePassConfigurationException>()),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
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
      final backend = _FakeDocumentShareBackend(
        shareHandle: const UaePassDocumentShareHandle(
          proofOfPresentationRequestId: 'pop-1',
        ),
        statusesById: {
          'pop-1': [
            UaePassDocumentShareItem.fromJson({
              'documentType': 'EmiratesId',
              'reqAuthorized': 'Y',
            }),
          ],
        },
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
      final backend = _FakeDocumentShareBackend(
        shareHandle: const UaePassDocumentShareHandle(
          proofOfPresentationRequestId: 'pop-1',
        ),
        statusesById: {
          'pop-1': [
            UaePassDocumentShareItem.fromJson({
              'documentType': 'EmiratesId',
              'reqAuthorized': 'P',
            }),
          ],
        },
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

  group('UaePassKit constructor', () {
    for (final environment in UaePassEnvironment.values) {
      test('clientSecret builds a UaePassDirectTokenExchanger for '
          '${environment.name}', () {
        final envConfig = UaePassConfig(
          clientId: 'client-1',
          redirectUri: Uri.parse('https://example.com/cb'),
          appCallbackScheme: 'testapp',
          environment: environment,
        );
        final client = UaePassKit(config: envConfig, clientSecret: 'secret-1');

        final exchanger = client.tokenExchanger as UaePassDirectTokenExchanger;
        expect(exchanger.clientId, 'client-1');
        expect(exchanger.clientSecret, 'secret-1');
        expect(exchanger.environment, environment);
      });
    }

    test('throws when both tokenExchanger and clientSecret are given', () {
      expect(
        () => UaePassKit(
          config: config,
          tokenExchanger: _FakeTokenExchanger(),
          clientSecret: 'secret-1',
        ),
        throwsA(isA<UaePassConfigurationException>()),
      );
    });

    test('throws when neither tokenExchanger nor clientSecret is given', () {
      expect(
        () => UaePassKit(config: config),
        throwsA(isA<UaePassConfigurationException>()),
      );
    });

    for (final environment in UaePassEnvironment.values) {
      test('signingClientSecret builds a UaePassDirectSigningTokenExchanger '
          'for ${environment.name}', () {
        final envConfig = UaePassConfig(
          clientId: 'client-1',
          redirectUri: Uri.parse('https://example.com/cb'),
          appCallbackScheme: 'testapp',
          environment: environment,
        );
        final client = UaePassKit(
          config: envConfig,
          clientSecret: 'secret-1',
          signingClientSecret: 'signing-secret-1',
        );

        final exchanger =
            client.signingTokenExchanger as UaePassDirectSigningTokenExchanger;
        expect(exchanger.clientId, 'client-1');
        expect(exchanger.clientSecret, 'signing-secret-1');
        expect(exchanger.environment, environment);
      });
    }

    test('signingTokenExchanger defaults to null when neither is given', () {
      final client = UaePassKit(config: config, clientSecret: 'secret-1');
      expect(client.signingTokenExchanger, isNull);
    });

    test('throws when both signingTokenExchanger and signingClientSecret '
        'are given', () {
      expect(
        () => UaePassKit(
          config: config,
          clientSecret: 'secret-1',
          signingTokenExchanger: UaePassDirectSigningTokenExchanger(
            clientId: 'client-1',
            clientSecret: 'signing-secret-1',
            environment: config.environment,
          ),
          signingClientSecret: 'signing-secret-1',
        ),
        throwsA(isA<UaePassConfigurationException>()),
      );
    });
  });
}
