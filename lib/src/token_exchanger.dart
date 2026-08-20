import 'dart:convert';

import 'api/uae_pass_http.dart';
import 'environment.dart';
import 'models/token_response.dart';

/// Exchanges a UAE Pass authorization code (or refresh token) for an access
/// token.
///
/// UAE Pass's token endpoint is a confidential-client endpoint — it
/// authenticates with `client_id`/`client_secret` via HTTP Basic auth, and
/// no PKCE alternative is documented anywhere on docs.uaepass.ae. That
/// means `client_secret` structurally does not belong in a shipped mobile
/// or web app. This interface exists so the exchange step is pluggable:
/// implement it against your own backend (mirroring the pattern your
/// existing apps already use — see `ApiService.createUaePassToken` in
/// `MobileApp-Casmex`/`Digital-MobileApp`) for any production integration.
///
/// [UaePassDirectTokenExchanger] is provided only for local development
/// against UAE Pass's public staging POC credentials — never ship it
/// against production credentials.
abstract class UaePassTokenExchanger {
  /// Exchanges [code] (obtained from [UaePassKit.signIn]) for an access
  /// token. [redirectUri] must match the one used to obtain [code].
  Future<UaePassTokenResponse> exchangeAuthorizationCode({
    required String code,
    required Uri redirectUri,
  });

  /// Exchanges a previously issued [refreshToken] for a new access token.
  /// Neither official UAE Pass native SDK implements this despite
  /// capturing `refresh_token` in their models.
  Future<UaePassTokenResponse> refreshToken({required String refreshToken});
}

/// A [UaePassTokenExchanger] that calls UAE Pass's `/idshub/token` endpoint
/// directly from the running app, using an embedded `client_secret`.
///
/// **Sandbox/development use only.** Embedding `client_secret` in a shipped
/// app or web bundle exposes it to anyone who inspects the binary or
/// network traffic — exactly the flaw found in prior community wrappers
/// (iOS embeds it on-device; the web implementation sends it from browser
/// JavaScript). For a production integration, implement
/// [UaePassTokenExchanger] against your backend instead.
class UaePassDirectTokenExchanger implements UaePassTokenExchanger {
  /// Creates a direct token exchanger for [environment] using [clientId]
  /// and [clientSecret].
  UaePassDirectTokenExchanger({
    required this.clientId,
    required this.clientSecret,
    required this.environment,
    UaePassHttpClient? httpClient,
  }) : _http = httpClient ?? UaePassHttpClient();

  /// The client ID this exchanger authenticates as.
  final String clientId;

  /// The client secret this exchanger authenticates with. Never ship this
  /// in a production build — see the class-level warning.
  final String clientSecret;

  /// The environment to exchange tokens against.
  final UaePassEnvironment environment;

  final UaePassHttpClient _http;

  String get _basicAuthHeader {
    final credentials = '$clientId:$clientSecret';
    final encoded = _base64Encode(credentials);
    return 'Basic $encoded';
  }

  @override
  Future<UaePassTokenResponse> exchangeAuthorizationCode({
    required String code,
    required Uri redirectUri,
  }) async {
    final json = await _http.postMultipart(
      environment.endpoints.token,
      fields: {
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri.toString(),
        'code': code,
      },
      headers: {'Authorization': _basicAuthHeader},
    );
    return UaePassTokenResponse.fromJson(json);
  }

  @override
  Future<UaePassTokenResponse> refreshToken({
    required String refreshToken,
  }) async {
    final json = await _http.postMultipart(
      environment.endpoints.token,
      fields: {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
      headers: {'Authorization': _basicAuthHeader},
    );
    return UaePassTokenResponse.fromJson(json);
  }
}

/// Obtains a separate `client_credentials` signing token, required before
/// starting an e-signature process. Distinct from
/// [UaePassTokenExchanger], which handles the login access token.
///
/// The same production-vs-sandbox guidance applies: prefer a backend
/// implementation over [UaePassDirectSigningTokenExchanger] outside of
/// local development.
abstract class UaePassSigningTokenExchanger {
  /// Obtains a signing token scoped to [signingScope].
  Future<UaePassTokenResponse> obtainSigningToken({
    required String signingScope,
  });
}

/// A [UaePassSigningTokenExchanger] that calls UAE Pass's signing token
/// endpoint directly. **Sandbox/development use only** — see
/// [UaePassDirectTokenExchanger].
class UaePassDirectSigningTokenExchanger
    implements UaePassSigningTokenExchanger {
  /// Creates a direct signing-token exchanger for [environment] using
  /// [clientId] and [clientSecret].
  UaePassDirectSigningTokenExchanger({
    required this.clientId,
    required this.clientSecret,
    required this.environment,
    UaePassHttpClient? httpClient,
  }) : _http = httpClient ?? UaePassHttpClient();

  /// The client ID this exchanger authenticates as.
  final String clientId;

  /// The client secret this exchanger authenticates with. Never ship this
  /// in a production build — see [UaePassDirectTokenExchanger].
  final String clientSecret;

  /// The environment to exchange tokens against.
  final UaePassEnvironment environment;

  final UaePassHttpClient _http;

  @override
  Future<UaePassTokenResponse> obtainSigningToken({
    required String signingScope,
  }) async {
    final credentials = '$clientId:$clientSecret';
    final json = await _http.postMultipart(
      environment.endpoints.signingToken,
      fields: {'grant_type': 'client_credentials', 'scope': signingScope},
      headers: {'Authorization': 'Basic ${_base64Encode(credentials)}'},
    );
    return UaePassTokenResponse.fromJson(json);
  }
}

String _base64Encode(String input) => base64Encode(utf8.encode(input));
