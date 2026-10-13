import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../uae_pass_kit_platform_interface.dart';
import 'api/uae_pass_http.dart';
import 'auth/state_generator.dart';
import 'config.dart';
import 'environment.dart';
import 'exceptions.dart';
import 'models/auth_result.dart';
import 'models/document_share.dart';
import 'models/profile.dart';
import 'models/signing.dart';
import 'models/token_response.dart';
import 'token_exchanger.dart';

/// The acr_values that trigger UAE Pass's native same-device app-to-app
/// handoff, used when the UAE Pass app is installed.
const String kUaePassAcrMobileOnDevice =
    'urn:digitalid:authentication:flow:mobileondevice';

/// The acr_values that trigger UAE Pass's push-notification fallback flow,
/// used when the UAE Pass app is not installed.
const String kUaePassAcrPushNotificationFallback =
    'urn:safelayer:tws:policies:authentication:level:low';

/// The main entry point for this plugin.
///
/// Owns one [UaePassConfig] and coordinates every UAE Pass capability this
/// plugin exposes: app-to-app sign-in, token exchange/refresh, profile
/// retrieval, logout, document sharing, and e-signature. Create one
/// instance per environment/config your app needs (typically one) and
/// reuse it — call [dispose] when you're done with it (e.g. in a
/// `GetxService.onClose()` or equivalent).
class UaePassKit {
  /// Creates a UAE Pass client for [config].
  ///
  /// Provide exactly one of [tokenExchanger] or [clientSecret]:
  /// - [tokenExchanger] performs the login token exchange against your own
  ///   backend (see [UaePassTokenExchanger]) — the recommended approach for
  ///   production, since `client_secret` never has to ship in this app.
  /// - [clientSecret] is a shortcut that builds a [UaePassDirectTokenExchanger]
  ///   for you, calling UAE Pass's token endpoint directly from this app with
  ///   [UaePassConfig.clientId]/[clientSecret] for [UaePassConfig.environment]
  ///   — works against both `staging` and `production`, but see
  ///   [UaePassDirectTokenExchanger]'s warning before using it for the latter.
  ///
  /// [signingTokenExchanger] (or its [signingClientSecret] shortcut) is
  /// only required if you call [signDocument]; [documentShareBackend] only
  /// if you call [requestDocumentShare].
  UaePassKit({
    required this.config,
    UaePassTokenExchanger? tokenExchanger,
    String? clientSecret,
    UaePassSigningTokenExchanger? signingTokenExchanger,
    String? signingClientSecret,
    this.documentShareBackend,
    UaePassHttpClient? httpClient,
  }) : tokenExchanger = _resolveTokenExchanger(
         tokenExchanger: tokenExchanger,
         clientSecret: clientSecret,
         config: config,
       ),
       signingTokenExchanger = _resolveSigningTokenExchanger(
         signingTokenExchanger: signingTokenExchanger,
         signingClientSecret: signingClientSecret,
         config: config,
       ),
       _http = httpClient ?? UaePassHttpClient();

  static UaePassTokenExchanger _resolveTokenExchanger({
    required UaePassTokenExchanger? tokenExchanger,
    required String? clientSecret,
    required UaePassConfig config,
  }) {
    if (tokenExchanger != null && clientSecret != null) {
      throw const UaePassConfigurationException(
        'Provide only one of tokenExchanger or clientSecret, not both.',
      );
    }
    if (tokenExchanger != null) return tokenExchanger;
    if (clientSecret != null) {
      return UaePassDirectTokenExchanger(
        clientId: config.clientId,
        clientSecret: clientSecret,
        environment: config.environment,
      );
    }
    throw const UaePassConfigurationException(
      'Provide either tokenExchanger or clientSecret.',
    );
  }

  static UaePassSigningTokenExchanger? _resolveSigningTokenExchanger({
    required UaePassSigningTokenExchanger? signingTokenExchanger,
    required String? signingClientSecret,
    required UaePassConfig config,
  }) {
    if (signingTokenExchanger != null && signingClientSecret != null) {
      throw const UaePassConfigurationException(
        'Provide only one of signingTokenExchanger or signingClientSecret, '
        'not both.',
      );
    }
    if (signingTokenExchanger != null) return signingTokenExchanger;
    if (signingClientSecret != null) {
      return UaePassDirectSigningTokenExchanger(
        clientId: config.clientId,
        clientSecret: signingClientSecret,
        environment: config.environment,
      );
    }
    return null;
  }

  /// This client's configuration.
  final UaePassConfig config;

  /// Performs login token exchange/refresh.
  final UaePassTokenExchanger tokenExchanger;

  /// Performs signing-token exchange, required by [signDocument].
  final UaePassSigningTokenExchanger? signingTokenExchanger;

  /// Delegates document-share creation/polling to your backend, required
  /// by [requestDocumentShare].
  final UaePassDocumentShareBackend? documentShareBackend;

  final UaePassHttpClient _http;

  /// Returns whether the native UAE Pass app is installed for
  /// [UaePassConfig.environment].
  Future<bool> isUaePassAppInstalled() {
    return UaePassKitPlatform.instance.isUaePassAppInstalled(
      androidPackageId: config.environment.androidPackageId,
      iosUrlScheme: config.environment.iosUrlScheme,
    );
  }

  /// Starts the UAE Pass app-to-app sign-in flow.
  ///
  /// The entire browser/native-app hand-off and deep-link return is
  /// performed natively (an in-app `WebView` on Android, an in-app
  /// `WKWebView` on iOS) — see [UaePassKitPlatform.nativeSignIn] — rather
  /// than in Dart, which proved unreliable at surviving that hand-off.
  ///
  /// Returns a [UaePassAuthResult]: [UaePassAuthSuccess] with an
  /// authorization code to exchange via [tokenExchanger], or
  /// [UaePassAuthCancelled] if the user backed out or declined — this
  /// method never throws for a plain user cancellation.
  ///
  /// [context] is currently unused (native code owns the UI) but kept for
  /// API stability and any future UI-adjacent behavior.
  Future<UaePassAuthResult> signIn(BuildContext context) async {
    final state = UaePassStateGenerator.generate();
    await _configureNativeEnvironment();

    final isInstalled = await isUaePassAppInstalled();
    final authorizeUrl = _buildAuthorizeUrl(
      state: state,
      isAppInstalled: isInstalled,
    );

    final String? code;
    try {
      code = await UaePassKitPlatform.instance.nativeSignIn(
        state: state,
        authorizeUrl: authorizeUrl,
      );
    } on PlatformException catch (e) {
      return _interpretNativeAuthFailure(e);
    }

    if (code == null || code.isEmpty) return const UaePassAuthCancelled();
    return UaePassAuthSuccess(code: code, state: state);
  }

  /// Builds the `/idshub/authorize` URL the native web flow starts from.
  Uri _buildAuthorizeUrl({
    required String state,
    required bool isAppInstalled,
  }) {
    return config.environment.endpoints.authorize.replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': config.clientId,
        'redirect_uri': config.redirectUri.toString(),
        'scope': config.scope,
        'state': state,
        'acr_values': isAppInstalled
            ? kUaePassAcrMobileOnDevice
            : kUaePassAcrPushNotificationFallback,
        'ui_locales': config.locale.wireValue,
        if (config.useFaceVerification) 'verificationType': 'face',
      },
    );
  }

  Future<void> _configureNativeEnvironment() {
    return UaePassKitPlatform.instance.setUpEnvironment(
      clientId: config.clientId,
      isProduction: config.environment == UaePassEnvironment.production,
      appCallbackScheme: config.appCallbackScheme,
      uaePassScheme: config.environment.iosUrlScheme,
      redirectUri: config.redirectUri,
      scope: config.scope,
      language: config.locale.wireValue,
    );
  }

  /// Classifies a native sign-in failure the same way prior Dart-side
  /// `UaePassRedirectInterceptor` parsing did: a plain user cancellation is
  /// [UaePassAuthCancelled], never an exception.
  UaePassAuthResult _interpretNativeAuthFailure(PlatformException e) {
    final message = e.message ?? '';
    if (_looksLikeCancellation(message)) return const UaePassAuthCancelled();
    return UaePassAuthFailure(
      UaePassServerException(
        message.isEmpty ? 'UAE Pass sign-in failed' : message,
        statusCode: 400,
        errorCode: e.code,
      ),
    );
  }

  bool _looksLikeCancellation(String message) {
    final lower = message.toLowerCase();
    return lower.contains('cancel') || lower.contains('access_denied');
  }

  /// Exchanges an authorization [code] (from [UaePassAuthSuccess]) for an
  /// access token, via [tokenExchanger].
  Future<UaePassTokenResponse> exchangeAuthorizationCode(String code) {
    return tokenExchanger.exchangeAuthorizationCode(
      code: code,
      redirectUri: config.redirectUri,
    );
  }

  /// Exchanges a [refreshToken] for a new access token, via
  /// [tokenExchanger]. Neither official UAE Pass native SDK implements
  /// this despite capturing `refresh_token` in their models.
  Future<UaePassTokenResponse> refreshAccessToken(String refreshToken) {
    return tokenExchanger.refreshToken(refreshToken: refreshToken);
  }

  /// Fetches the authenticated user's full profile from
  /// `GET /idshub/userinfo`.
  Future<UaePassProfile> getProfile(UaePassTokenResponse token) async {
    final json = await _http.getJson(
      config.environment.endpoints.userInfo,
      headers: {'Authorization': token.authorizationHeaderValue},
    );
    return UaePassProfile.fromJson(json);
  }

  /// Builds the `GET /idshub/logout` URL for [postLogoutRedirectUri]
  /// (defaults to [UaePassConfig.redirectUri]) — UAE Pass's logout
  /// endpoint only documents this one parameter.
  Uri logoutUrl({Uri? postLogoutRedirectUri}) {
    return config.environment.endpoints.logout.replace(
      queryParameters: {
        'redirect_uri': (postLogoutRedirectUri ?? config.redirectUri)
            .toString(),
      },
    );
  }

  /// Best-effort UAE Pass sign-out: clears every cookie stored by native
  /// code's own WebView (terminating the local SSO session) and notifies
  /// UAE Pass's `/idshub/logout` endpoint.
  ///
  /// True single-logout on UAE Pass's side is only guaranteed if
  /// [logoutUrl] is actually navigated to inside the same browser/WebView
  /// session that authenticated (its session cookie lives there, not in
  /// this plugin's plain HTTP client). If your app needs a stronger
  /// guarantee, navigate the user to [logoutUrl] directly instead of
  /// relying on this method alone.
  Future<void> logout({Uri? postLogoutRedirectUri}) async {
    await UaePassKitPlatform.instance.nativeSignOut();
    try {
      await _http.getJson(
        logoutUrl(postLogoutRedirectUri: postLogoutRedirectUri),
      );
    } on UaePassException {
      // Best-effort: UAE Pass's logout endpoint isn't guaranteed to return
      // JSON (it's designed to be browser-navigated), so a parse/HTTP
      // failure here doesn't mean logout failed — local state is already
      // cleared above.
    }
  }

  /// Requests the user share one or more documents (a "proof of
  /// presentation" request, e.g. for KYC) via UAE Pass, emitting a
  /// [DocumentShareStatus] on every poll until a terminal state is
  /// reached, an item expires, or [timeout] elapses.
  ///
  /// Requires [documentShareBackend] — UAE Pass's Data Sharing
  /// Authorization API is HMAC-signed and must be called from your
  /// backend, never directly from this plugin.
  Stream<DocumentShareStatus> requestDocumentShare(
    UaePassDocumentShareRequest request, {
    Duration pollInterval = const Duration(seconds: 10),
    Duration timeout = const Duration(minutes: 10),
  }) async* {
    final backend = documentShareBackend;
    if (backend == null) {
      throw const UaePassConfigurationException(
        'documentShareBackend must be provided to call requestDocumentShare.',
      );
    }

    final handle = await backend.createShareRequest(request);
    final isInstalled = await isUaePassAppInstalled();
    if (isInstalled) {
      final launchUri = defaultTargetPlatform == TargetPlatform.iOS
          ? handle.iosTransitionUrl
          : handle.androidTransitionUrl;
      if (launchUri != null) {
        await url_launcher.launchUrl(
          launchUri,
          mode: url_launcher.LaunchMode.externalApplication,
        );
      }
    }

    final deadline = DateTime.now().add(timeout);
    while (true) {
      final items = await backend.fetchStatus(
        handle.proofOfPresentationRequestId,
      );
      final anyExpired = items.any((item) => item.isExpired);
      final allTerminal =
          items.isNotEmpty &&
          items.every((item) => item.state.isTerminal || item.isExpired);

      if (allTerminal || anyExpired) {
        yield DocumentShareComplete(items);
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        yield const DocumentShareTimedOut();
        return;
      }
      yield DocumentSharePending(items);
      await Future<void>.delayed(pollInterval);
    }
  }

  /// Starts UAE Pass's PDF e-signature flow for [request]: uploads the
  /// document via [createSigningProcess] (plain HTTPS, unchanged), then —
  /// once UAE Pass returns a signing URL — presents it natively and applies
  /// the same app-switch/deep-link mechanics as [signIn] until a terminal
  /// status is reached.
  ///
  /// Requires [signingTokenExchanger]. Returns
  /// [UaePassSigningOutcome.cancelled] if the user backs out.
  ///
  /// [context] is currently unused (native code owns the UI) but kept for
  /// API stability and any future UI-adjacent behavior.
  Future<UaePassSigningOutcome> signDocument(
    BuildContext context,
    UaePassSigningRequest request,
  ) async {
    final exchanger = signingTokenExchanger;
    if (exchanger == null) {
      throw const UaePassConfigurationException(
        'signingTokenExchanger must be provided to call signDocument.',
      );
    }

    final signingToken = await exchanger.obtainSigningToken(
      signingScope: config.scope,
    );
    final process = await createSigningProcess(
      signingToken: signingToken,
      request: request,
    );
    final signingUrl = process.signingUiUrl;
    if (signingUrl == null) {
      // No pending task returned — UAE Pass considers this already final.
      return UaePassSigningOutcome.finished;
    }

    await _configureNativeEnvironment();
    final String? resultUrl;
    try {
      resultUrl = await UaePassKitPlatform.instance.openSigningUrl(
        url: signingUrl.toString(),
        finishUri: request.finishCallbackUrl,
      );
    } on PlatformException {
      return UaePassSigningOutcome.cancelled;
    }

    if (resultUrl == null) return UaePassSigningOutcome.cancelled;
    final resultUri = Uri.tryParse(resultUrl);
    return UaePassSigningOutcome.fromStatusParam(
      resultUri?.queryParameters['status'],
    );
  }

  /// Uploads [request]'s process metadata and document bytes to
  /// `POST /esignsp/v2/signer_processes`, using [signingToken] obtained
  /// from [signingTokenExchanger]. Exposed directly for callers who want
  /// to drive the signing WebView themselves.
  Future<UaePassSigningProcess> createSigningProcess({
    required UaePassTokenResponse signingToken,
    required UaePassSigningRequest request,
  }) async {
    final json = await _http.postMultipart(
      config.environment.endpoints.signerProcesses,
      fields: {'process': jsonEncode(request.toProcessJson())},
      files: [
        http.MultipartFile.fromBytes(
          'document',
          request.documentBytes,
          filename: request.documentFileName,
        ),
      ],
      headers: {'Authorization': signingToken.authorizationHeaderValue},
    );
    return UaePassSigningProcess.fromJson(json);
  }

  /// Polls `GET /esignsp/v2/signer_processes/{id}` for the current state
  /// of a signing process.
  Future<UaePassSigningProcess> getSigningProcess({
    required UaePassTokenResponse signingToken,
    required String processId,
  }) async {
    final json = await _http.getJson(
      config.environment.endpoints.signerProcess(processId),
      headers: {'Authorization': signingToken.authorizationHeaderValue},
    );
    return UaePassSigningProcess.fromJson(json);
  }

  /// Downloads the signed document content for [documentId] from
  /// `GET /esignsp/v2/documents/{id}/content`.
  Future<Uint8List> downloadSignedDocument({
    required UaePassTokenResponse signingToken,
    required String documentId,
  }) async {
    final bytes = await _http.getBytes(
      config.environment.endpoints.signedDocument(documentId),
      headers: {'Authorization': signingToken.authorizationHeaderValue},
    );
    return Uint8List.fromList(bytes);
  }

  /// Cleans up a finished or abandoned signing process via
  /// `DELETE /esignsp/v2/signer_processes/{id}`.
  Future<void> deleteSigningProcess({
    required UaePassTokenResponse signingToken,
    required String processId,
  }) {
    return _http.delete(
      config.environment.endpoints.deleteSignerProcess(processId),
      headers: {'Authorization': signingToken.authorizationHeaderValue},
    );
  }

  /// Releases resources held by this client. Call when you no longer need
  /// this instance.
  void dispose() => _http.close();
}
