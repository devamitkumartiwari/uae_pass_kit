/// A single document type requested as part of a document-share (proof of
/// presentation) request, e.g. `EmiratesId`.
class UaePassDocumentRequestItem {
  /// Creates a requested-document descriptor.
  const UaePassDocumentRequestItem({
    required this.documentType,
    this.required = false,
  });

  /// The UAE Pass document type identifier (e.g. `EmiratesId`).
  final String documentType;

  /// Whether UAE Pass should treat sharing this document as mandatory.
  final bool required;

  /// Serializes this item to the wire shape UAE Pass's Data Sharing
  /// Authorization API expects.
  Map<String, dynamic> toJson() => {
    'documentType': documentType,
    'required': required,
  };
}

/// Where the document-share request originated from, mirrored to UAE Pass
/// so it can pick the right hand-off UI.
enum UaePassDocumentShareOrigin {
  /// The native UAE Pass app is installed and will be launched directly.
  mobile,

  /// The native UAE Pass app is not installed; UAE Pass falls back to a
  /// browser/notification-based flow.
  web;

  /// The wire value UAE Pass expects (`MOBILE` / `WEB`).
  String get wireValue => name.toUpperCase();
}

/// A request to ask the user to share one or more documents (a "proof of
/// presentation" request) via UAE Pass, e.g. as part of KYC.
///
/// UAE Pass's Data Sharing Authorization API is a server-to-server API
/// secured with `X-API-Key` and HMAC-SHA256 request signing — it must be
/// called from your backend, never directly from the mobile app. This
/// model is the payload shape; see [UaePassDocumentShareBackend] for how
/// the plugin delegates the actual call to your backend.
class UaePassDocumentShareRequest {
  /// Creates a document-share request.
  const UaePassDocumentShareRequest({
    required this.accessToken,
    required this.emiratesId,
    required this.uuid,
    required this.documents,
    required this.successUrl,
    required this.failureUrl,
    required this.origin,
  });

  /// The UAE Pass login access token for the user this request is on
  /// behalf of.
  final String accessToken;

  /// The user's Emirates ID number.
  final String emiratesId;

  /// The user's UAE Pass UUID.
  final String uuid;

  /// The documents being requested.
  final List<UaePassDocumentRequestItem> documents;

  /// Where to redirect on successful sharing.
  final Uri successUrl;

  /// Where to redirect on failed/declined sharing.
  final Uri failureUrl;

  /// Whether this request originates from a device with the native app
  /// installed, or should fall back to a web-based flow.
  final UaePassDocumentShareOrigin origin;

  /// Serializes this request to the wire shape UAE Pass's Data Sharing
  /// Authorization API expects.
  Map<String, dynamic> toJson() => {
    'authToken': accessToken,
    'requestedDocuments': documents.map((d) => d.toJson()).toList(),
    'emiratesId': emiratesId,
    'uuId': uuid,
    'successUrl': successUrl.toString(),
    'failureUrl': failureUrl.toString(),
    'origin': origin.wireValue,
  };
}

/// The handle returned after successfully creating a document-share
/// request, used both to launch the native app and to poll for a result.
class UaePassDocumentShareHandle {
  /// Creates a document-share handle.
  const UaePassDocumentShareHandle({
    required this.proofOfPresentationRequestId,
    this.androidTransitionUrl,
    this.iosTransitionUrl,
  });

  /// The identifier used to poll for the sharing outcome.
  final String proofOfPresentationRequestId;

  /// The URL to launch the native UAE Pass app with, on Android.
  final Uri? androidTransitionUrl;

  /// The URL to launch the native UAE Pass app with, on iOS.
  final Uri? iosTransitionUrl;
}

/// The authorization state of a single requested document, as reported by
/// UAE Pass while polling.
enum UaePassDocumentAuthorizationState {
  /// The user has not yet responded.
  pending,

  /// The user authorized sharing this document.
  authorized,

  /// The user declined sharing this document.
  rejected,

  /// The request is no longer valid (e.g. it expired).
  invalid,

  /// A status code UAE Pass returned that this plugin doesn't recognize.
  unknown;

  /// Parses UAE Pass's single-letter status codes (`Y`/`N`/`I`/`P`).
  static UaePassDocumentAuthorizationState fromCode(String? code) {
    switch (code) {
      case 'Y':
        return UaePassDocumentAuthorizationState.authorized;
      case 'N':
        return UaePassDocumentAuthorizationState.rejected;
      case 'I':
        return UaePassDocumentAuthorizationState.invalid;
      case 'P':
        return UaePassDocumentAuthorizationState.pending;
      default:
        return UaePassDocumentAuthorizationState.unknown;
    }
  }

  /// Whether this state means polling should stop.
  bool get isTerminal => this != UaePassDocumentAuthorizationState.pending;
}

/// A single document result returned while polling a document-share
/// request.
class UaePassDocumentShareItem {
  /// Creates a document-share result item.
  const UaePassDocumentShareItem({
    required this.documentType,
    required this.state,
    this.notificationExpiry,
    this.raw = const {},
  });

  /// Parses a [UaePassDocumentShareItem] from a single element of the
  /// polling response.
  factory UaePassDocumentShareItem.fromJson(Map<String, dynamic> json) {
    return UaePassDocumentShareItem(
      documentType: json['documentType'] as String? ?? '',
      state: UaePassDocumentAuthorizationState.fromCode(
        json['reqAuthorized'] as String?,
      ),
      notificationExpiry: _parseExpiry(json['NotificationExpiry']),
      raw: json,
    );
  }

  static DateTime? _parseExpiry(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    final normalized = value.trim().replaceFirst(' ', 'T');
    return DateTime.tryParse(
      normalized.endsWith('Z') ? normalized : '${normalized}Z',
    );
  }

  /// The document type this result is for.
  final String documentType;

  /// The current authorization state.
  final UaePassDocumentAuthorizationState state;

  /// When the pending notification expires, if reported and parseable.
  final DateTime? notificationExpiry;

  /// The complete, unmodified JSON this item was parsed from.
  final Map<String, dynamic> raw;

  /// Whether [notificationExpiry] has passed.
  bool get isExpired =>
      notificationExpiry != null &&
      notificationExpiry!.isBefore(DateTime.now().toUtc());
}

/// A snapshot emitted while polling a document-share request via
/// [UaePassKit.requestDocumentShare].
sealed class DocumentShareStatus {
  const DocumentShareStatus();
}

/// Still waiting for the user to respond in the UAE Pass app.
final class DocumentSharePending extends DocumentShareStatus {
  /// Creates a pending status snapshot.
  const DocumentSharePending(this.items);

  /// The latest known state of each requested document.
  final List<UaePassDocumentShareItem> items;
}

/// Polling reached a terminal state (authorized, rejected, invalid, or
/// expired) for at least one requested document.
final class DocumentShareComplete extends DocumentShareStatus {
  /// Creates a completed status snapshot.
  const DocumentShareComplete(this.items);

  /// The final state of each requested document.
  final List<UaePassDocumentShareItem> items;
}

/// Polling exceeded the configured timeout before reaching a terminal
/// state.
final class DocumentShareTimedOut extends DocumentShareStatus {
  /// Creates a timed-out status snapshot.
  const DocumentShareTimedOut();
}

/// Delegates the two server-to-server calls a document-share request
/// requires to your backend, since UAE Pass's Data Sharing Authorization
/// API is HMAC-signed and must never be called with your API key directly
/// from a mobile app.
///
/// This mirrors the pattern your apps already use: `ApiService` proxies
/// `postUAEPassDocumentDetails` and `fetchUAEPassDoc` through your own
/// server. Implement this interface against those same endpoints (or
/// equivalents) to plug your backend into [UaePassKit.requestDocumentShare].
abstract class UaePassDocumentShareBackend {
  /// Creates the document-share request on UAE Pass via your backend and
  /// returns the handle used to launch the app and poll for a result.
  Future<UaePassDocumentShareHandle> createShareRequest(
    UaePassDocumentShareRequest request,
  );

  /// Fetches the current status of a previously created request.
  Future<List<UaePassDocumentShareItem>> fetchStatus(
    String proofOfPresentationRequestId,
  );
}
