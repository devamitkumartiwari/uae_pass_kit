/// The response returned by `POST /idshub/token`.
///
/// UAE Pass's documented response only includes [accessToken], [tokenType],
/// [expiresIn] and [scope] — there is no `id_token`/JWKS, so UAE Pass
/// behaves as plain OAuth2 rather than full OIDC. [refreshToken] and
/// [idToken] are included here as nullable fields in case a given
/// deployment does return them, but neither should be assumed present.
class UaePassTokenResponse {
  /// Creates a token response.
  const UaePassTokenResponse({
    required this.accessToken,
    required this.tokenType,
    this.expiresIn,
    this.scope,
    this.refreshToken,
    this.idToken,
  });

  /// Parses a [UaePassTokenResponse] from a `/idshub/token` JSON body.
  factory UaePassTokenResponse.fromJson(Map<String, dynamic> json) {
    return UaePassTokenResponse(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresIn: json['expires_in'] as int?,
      scope: json['scope'] as String?,
      refreshToken: json['refresh_token'] as String?,
      idToken: json['id_token'] as String?,
    );
  }

  /// The opaque access token, used as a Bearer token against
  /// `/idshub/userinfo` and other authenticated endpoints.
  final String accessToken;

  /// The token type, normally `Bearer`.
  final String tokenType;

  /// Seconds until [accessToken] expires, if provided.
  final int? expiresIn;

  /// The scope actually granted, if provided.
  final String? scope;

  /// A refresh token, if provided. Neither official UAE Pass native SDK
  /// exposes a way to use this — see [UaePassKit.refreshToken].
  final String? refreshToken;

  /// An ID token, if provided (not documented by UAE Pass; present only
  /// defensively).
  final String? idToken;

  /// The value to send as the `Authorization` header when calling
  /// authenticated UAE Pass endpoints with this token.
  String get authorizationHeaderValue => '$tokenType $accessToken';
}
