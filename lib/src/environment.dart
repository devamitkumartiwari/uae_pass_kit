/// The UAE Pass environment to integrate against.
///
/// UAE Pass only issues integration credentials for two environments during
/// onboarding: staging (development/testing) and production (go-live).
/// Internal UAE Pass environments such as `qa` and `dev` are used by UAE
/// Pass itself and are intentionally not exposed here, so an integrator can
/// never be misconfigured against an environment they were never given
/// credentials for.
enum UaePassEnvironment {
  /// The staging (pre-production) environment, used during development and
  /// UAE Pass's onboarding assessment. UAE Pass publishes a shared public
  /// POC credential pair (`client_id`/`client_secret` = `sandbox_stage`)
  /// that is only valid here.
  staging(
    identityBaseUrl: 'https://stg-id.uaepass.ae',
    signingBaseUrl: 'https://stg-id.uaepass.ae',
    androidPackageId: 'ae.uaepass.mainapp.stg',
    iosUrlScheme: 'uaepassstg',
  ),

  /// The production (go-live) environment. Requires credentials issued to
  /// you specifically by UAE Pass during the Go-Live phase of onboarding.
  production(
    identityBaseUrl: 'https://id.uaepass.ae',
    signingBaseUrl: 'https://id.uaepass.ae',
    androidPackageId: 'ae.uaepass.mainapp',
    iosUrlScheme: 'uaepass',
  );

  const UaePassEnvironment({
    required this.identityBaseUrl,
    required this.signingBaseUrl,
    required this.androidPackageId,
    required this.iosUrlScheme,
  });

  /// Base URL for the identity/OIDC hub (`/idshub/*` endpoints).
  final String identityBaseUrl;

  /// Base URL for the trust/e-signature service
  /// (`/trustedx-authserver/*`, `/trustedx-resources/esignsp/*`).
  final String signingBaseUrl;

  /// The Android package name of the native UAE Pass app for this
  /// environment, used for install-detection and package-visibility
  /// `<queries>` declarations.
  final String androidPackageId;

  /// The custom URL scheme (without `://`) the native UAE Pass app
  /// registers on iOS for this environment.
  final String iosUrlScheme;

  /// The full `scheme://` prefix used to detect and launch the native app.
  String get iosUrlSchemePrefix => '$iosUrlScheme://';

  Uri get _authorizeEndpoint => Uri.parse('$identityBaseUrl/idshub/authorize');

  Uri get _tokenEndpoint => Uri.parse('$identityBaseUrl/idshub/token');

  Uri get _userInfoEndpoint => Uri.parse('$identityBaseUrl/idshub/userinfo');

  Uri get _logoutEndpoint => Uri.parse('$identityBaseUrl/idshub/logout');

  Uri get _introspectEndpoint =>
      Uri.parse('$identityBaseUrl/idshub/introspect');

  Uri get _signingTokenEndpoint =>
      Uri.parse('$signingBaseUrl/trustedx-authserver/oauth/main-as/token');

  Uri get _signerProcessesEndpoint => Uri.parse(
    '$signingBaseUrl/trustedx-resources/esignsp/v2/signer_processes',
  );

  Uri _signerProcessEndpoint(String processId) => Uri.parse(
    '$signingBaseUrl/trustedx-resources/esignsp/v2/signer_processes/$processId',
  );

  Uri _signedDocumentEndpoint(String documentId) => Uri.parse(
    '$signingBaseUrl/trustedx-resources/esignsp/v2/documents/$documentId/content',
  );

  /// Endpoints for this environment, grouped for discoverability.
  UaePassEndpoints get endpoints => UaePassEndpoints._(this);
}

/// The concrete UAE Pass endpoint URLs for a given [UaePassEnvironment].
///
/// Grouped behind one accessor so no other part of the plugin (or a
/// consuming app) ever needs to hand-build or hardcode a UAE Pass URL.
class UaePassEndpoints {
  UaePassEndpoints._(this._environment);

  final UaePassEnvironment _environment;

  /// `GET /idshub/authorize` — starts the OAuth2 authorization-code flow.
  Uri get authorize => _environment._authorizeEndpoint;

  /// `POST /idshub/token` — exchanges an authorization code (or refresh
  /// token) for an access token.
  Uri get token => _environment._tokenEndpoint;

  /// `GET /idshub/userinfo` — fetches the authenticated user's profile.
  Uri get userInfo => _environment._userInfoEndpoint;

  /// `GET /idshub/logout` — terminates the UAE Pass IdP session.
  Uri get logout => _environment._logoutEndpoint;

  /// `POST /idshub/introspect` — validates/introspects a token.
  Uri get introspect => _environment._introspectEndpoint;

  /// `POST /trustedx-authserver/oauth/main-as/token` — obtains a
  /// `client_credentials` signing token, distinct from the login access
  /// token, required before starting an e-signature process.
  Uri get signingToken => _environment._signingTokenEndpoint;

  /// `POST /trustedx-resources/esignsp/v2/signer_processes` — creates a
  /// new document-signing process.
  Uri get signerProcesses => _environment._signerProcessesEndpoint;

  /// `GET /trustedx-resources/esignsp/v2/signer_processes/{id}` — polls the
  /// status of a document-signing process.
  Uri signerProcess(String processId) =>
      _environment._signerProcessEndpoint(processId);

  /// `DELETE /trustedx-resources/esignsp/v2/signer_processes/{id}` — cleans
  /// up a finished or abandoned signing process.
  Uri deleteSignerProcess(String processId) =>
      _environment._signerProcessEndpoint(processId);

  /// `GET /trustedx-resources/esignsp/v2/documents/{id}/content` —
  /// downloads the signed document content.
  Uri signedDocument(String documentId) =>
      _environment._signedDocumentEndpoint(documentId);
}
