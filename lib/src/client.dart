import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:webview_flutter/webview_flutter.dart';

import '../uae_pass_kit_platform_interface.dart';
import 'api/uae_pass_http.dart';
import 'auth/redirect_interceptor.dart';
import 'auth/state_generator.dart';
import 'auth/uae_pass_web_flow_screen.dart';
import 'config.dart';
import 'exceptions.dart';
import 'models/auth_result.dart';
import 'models/document_share.dart';
import 'models/profile.dart';
import 'models/signing.dart';
import 'models/token_response.dart';
import 'token_exchanger.dart';

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
  /// [tokenExchanger] performs the login token exchange — supply a
  /// backend-proxying implementation in production (see
  /// [UaePassTokenExchanger]). [signingTokenExchanger] and
  /// [documentShareBackend] are optional and only required if you call
  /// [signDocument] or [requestDocumentShare] respectively.
  UaePassKit({
    required this.config,
    required this.tokenExchanger,
    this.signingTokenExchanger,
    this.documentShareBackend,
    UaePassHttpClient? httpClient,
  }) : _http = httpClient ?? UaePassHttpClient(),
       _interceptor = UaePassRedirectInterceptor(config);

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
  final UaePassRedirectInterceptor _interceptor;

  /// Returns whether the native UAE Pass app is installed for
  /// [UaePassConfig.environment].
  Future<bool> isUaePassAppInstalled() {
    return UaePassKitPlatform.instance.isUaePassAppInstalled(
      androidPackageId: config.environment.androidPackageId,
      iosUrlScheme: config.environment.iosUrlScheme,
    );
  }

  /// Starts the UAE Pass app-to-app sign-in flow, pushing a full-screen
  /// WebView route on [context]'s navigator.
  ///
  /// Returns a [UaePassAuthResult]: [UaePassAuthSuccess] with an
  /// authorization code to exchange via [tokenExchanger], or
  /// [UaePassAuthCancelled] if the user backed out or declined — this
  /// method never throws for a plain user cancellation.
  Future<UaePassAuthResult> signIn(BuildContext context) async {
    final isInstalled = await isUaePassAppInstalled();
    final state = UaePassStateGenerator.generate();
    final authorizeUrl = _interceptor.buildAuthorizeUrl(
      state: state,
      isAppInstalled: isInstalled,
    );

    if (!context.mounted) return const UaePassAuthCancelled();
    final resultUri = await Navigator.of(context).push<Uri?>(
      MaterialPageRoute<Uri?>(
        fullscreenDialog: true,
        builder: (_) => UaePassWebFlowScreen(
          initialUrl: authorizeUrl,
          isNativeAppLaunchUrl: _interceptor.isNativeAppLaunchUrl,
          rewriteForNativeAppHandoff: _interceptor.rewriteForNativeAppHandoff,
          isAppCallbackUrl: _interceptor.isAppCallbackUrl,
          extractOriginalUrl: _interceptor.extractOriginalUrl,
          isFinalUrl: _interceptor.isFinalRedirect,
        ),
      ),
    );

    if (resultUri == null) return const UaePassAuthCancelled();
    return _interceptor.parseFinalRedirect(resultUri, expectedState: state);
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

  /// Best-effort UAE Pass sign-out: clears every cookie stored by this
  /// plugin's WebView (terminating the local SSO session) and notifies
  /// UAE Pass's `/idshub/logout` endpoint.
  ///
  /// Note this is a real improvement over prior community wrappers' plain
  /// `signOut()`, which only clears local state and never calls
  /// `/idshub/logout` at all — but true single-logout on UAE Pass's side
  /// is only guaranteed if [logoutUrl] is actually navigated to inside the
  /// same browser/WebView session that authenticated (its session cookie
  /// lives there, not in this plugin's plain HTTP client). If your app
  /// needs a stronger guarantee, navigate the user to [logoutUrl] directly
  /// instead of relying on this method alone.
  Future<void> logout({Uri? postLogoutRedirectUri}) async {
    await WebViewCookieManager().clearCookies();
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

  /// Starts UAE Pass's PDF e-signature flow for [request], pushing the
  /// same full-screen WebView flow used by [signIn] once UAE Pass returns
  /// a signing URL.
  ///
  /// Requires [signingTokenExchanger]. Returns
  /// [UaePassSigningOutcome.cancelled] if the user backs out.
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

    if (!context.mounted) return UaePassSigningOutcome.cancelled;
    final resultUri = await Navigator.of(context).push<Uri?>(
      MaterialPageRoute<Uri?>(
        fullscreenDialog: true,
        builder: (_) => UaePassWebFlowScreen(
          title: 'UAE PASS SIGNING',
          initialUrl: signingUrl,
          isNativeAppLaunchUrl: _interceptor.isNativeAppLaunchUrl,
          rewriteForNativeAppHandoff: _interceptor.rewriteForNativeAppHandoff,
          isAppCallbackUrl: _interceptor.isAppCallbackUrl,
          extractOriginalUrl: _interceptor.extractOriginalUrl,
          isFinalUrl: (uri) =>
              uri.scheme == request.finishCallbackUrl.scheme &&
              uri.host == request.finishCallbackUrl.host &&
              uri.path == request.finishCallbackUrl.path,
        ),
      ),
    );

    if (resultUri == null) return UaePassSigningOutcome.cancelled;
    return UaePassSigningOutcome.fromStatusParam(
      resultUri.queryParameters['status'],
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
