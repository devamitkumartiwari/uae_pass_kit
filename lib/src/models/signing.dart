import 'dart:typed_data';

/// The UAE Pass process type for a standard PDF advanced/qualified
/// signature, as found in both official native SDKs.
const String kUaePassSignProcessType =
    'urn:safelayer:eidas:processes:document:sign:esigp';

/// The UAE Pass signature policy for standard PDF document signing.
const String kUaePassSignPolicyId =
    'urn:safelayer:eidas:policies:sign:document:pdf';

/// The pixel rectangle a visible signature field occupies on a page,
/// mirroring the decompiled `RectangleBean`.
class UaePassSignatureRectangle {
  /// Creates a signature rectangle in PDF page pixel coordinates.
  const UaePassSignatureRectangle({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// X offset.
  final double x;

  /// Y offset.
  final double y;

  /// Width.
  final double width;

  /// Height.
  final double height;

  /// Serializes to the wire shape.
  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}

/// A single visible detail line (e.g. signer name, date) shown inside a
/// signature's visual appearance, mirroring the decompiled `DetailsBean`.
class UaePassSignatureAppearanceDetail {
  /// Creates an appearance detail line.
  const UaePassSignatureAppearanceDetail({
    required this.type,
    required this.title,
  });

  /// The detail type UAE Pass recognizes (e.g. `signerName`, `date`).
  final String type;

  /// The label shown for this detail.
  final String title;

  /// Serializes to the wire shape.
  Map<String, dynamic> toJson() => {'type': type, 'title': title};
}

/// A single named signature field placed on a document, mirroring the
/// decompiled `SignatureFieldBean` → `LocationBean`/`AppearanceBean` tree.
class UaePassSignatureField {
  /// Creates a signature field.
  const UaePassSignatureField({
    required this.name,
    required this.pageNumber,
    required this.rectangle,
    this.appearanceDetails = const [],
    this.showCardHolderSignatureImage = false,
  });

  /// A unique name for this field within the process (required for
  /// multi-signer documents).
  final String name;

  /// The 1-based PDF page number the field appears on.
  final int pageNumber;

  /// The field's position and size on the page.
  final UaePassSignatureRectangle rectangle;

  /// Visible detail lines (e.g. signer name/date) rendered inside the
  /// signature appearance.
  final List<UaePassSignatureAppearanceDetail> appearanceDetails;

  /// Whether to embed the signer's Emirates ID card signature image in the
  /// visible signature. Subject to UAE Pass/ICP approval for your
  /// integration — do not enable without confirming this is authorized.
  final bool showCardHolderSignatureImage;

  /// Serializes to the wire shape UAE Pass's `esignsp/v2` API expects.
  Map<String, dynamic> toJson() => {
    'name': name,
    'location': {
      'page': {'number': pageNumber},
      'rectangle': rectangle.toJson(),
    },
    if (appearanceDetails.isNotEmpty || showCardHolderSignatureImage)
      'appearance': {
        'signatureDetails': appearanceDetails.map((d) => d.toJson()).toList(),
        'showCardHolderSignatureImage': showCardHolderSignatureImage,
      },
  };
}

/// A single signer participating in a signing process, mirroring the
/// decompiled `SignerBean`.
class UaePassSigner {
  /// Creates a signer entry.
  const UaePassSigner({
    this.signaturePolicyId = kUaePassSignPolicyId,
    required this.fields,
    this.skipDocumentAgreement = false,
  });

  /// The signature policy to apply.
  final String signaturePolicyId;

  /// Where this signer's signature(s) should be placed.
  final List<UaePassSignatureField> fields;

  /// Whether to skip UAE Pass's document-agreement confirmation step.
  final bool skipDocumentAgreement;

  /// Serializes to the wire shape.
  Map<String, dynamic> toJson() => {
    'signaturePolicyId': signaturePolicyId,
    'parameters': {
      'type': 'pades-baseline',
      'signatureField': fields.map((f) => f.toJson()).toList(),
    },
    'views': [
      {
        'documentAgreement': {'skipServerId': skipDocumentAgreement},
      },
    ],
  };
}

/// A request to sign one PDF document via UAE Pass's e-signature service.
///
/// Wraps the `esignsp/v2/signer_processes` flow verified in both official
/// native SDKs: a `client_credentials` signing token is obtained
/// separately (see `UaePassSigningTokenExchanger`), then this request's
/// process JSON and the document bytes are uploaded together as
/// `multipart/form-data`.
class UaePassSigningRequest {
  /// Creates a signing request for [documentBytes].
  const UaePassSigningRequest({
    required this.documentBytes,
    required this.documentFileName,
    required this.signer,
    required this.finishCallbackUrl,
    this.uiLocales = 'en',
    this.timestampProviderId,
    this.processType = kUaePassSignProcessType,
  });

  /// The raw PDF bytes to sign.
  final Uint8List documentBytes;

  /// The file name to associate with the uploaded document.
  final String documentFileName;

  /// The signer configuration.
  final UaePassSigner signer;

  /// The URL UAE Pass redirects back to (loaded in the same WebView used
  /// for login) once the user finishes or cancels signing.
  final Uri finishCallbackUrl;

  /// The UAE Pass signing UI language (`en`/`ar`).
  final String uiLocales;

  /// An optional timestamp authority provider ID.
  final String? timestampProviderId;

  /// The UAE Pass process type.
  final String processType;

  /// Serializes the process metadata (not the document bytes) to the JSON
  /// part of the multipart upload.
  Map<String, dynamic> toProcessJson() => {
    'processType': processType,
    'signer': signer.toJson(),
    'finishCallbackUrl': finishCallbackUrl.toString(),
    'uiLocales': uiLocales,
    if (timestampProviderId != null)
      'timestamp': {'providerId': timestampProviderId},
  };
}

/// A pending task UAE Pass expects the signer to complete, mirroring the
/// decompiled `Pending` model.
class UaePassSigningPendingTask {
  /// Creates a pending signing task.
  const UaePassSigningPendingTask({
    required this.type,
    required this.id,
    required this.url,
  });

  /// Parses a pending task from JSON.
  factory UaePassSigningPendingTask.fromJson(Map<String, dynamic> json) {
    return UaePassSigningPendingTask(
      type: json['type'] as String? ?? '',
      id: json['id'] as String? ?? '',
      url: Uri.tryParse(json['url'] as String? ?? '') ?? Uri(),
    );
  }

  /// The task type (e.g. a signing UI step).
  final String type;

  /// The task identifier.
  final String id;

  /// The URL to present to the user — load this in the shared auth/signing
  /// WebView controller to let them complete the task.
  final Uri url;
}

/// A document attached to a signing process, mirroring the decompiled
/// `Document` model.
class UaePassSigningDocument {
  /// Creates a signing-process document reference.
  const UaePassSigningDocument({required this.url});

  /// Parses a document reference from JSON.
  factory UaePassSigningDocument.fromJson(Map<String, dynamic> json) {
    return UaePassSigningDocument(
      url: Uri.tryParse(json['url'] as String? ?? '') ?? Uri(),
    );
  }

  /// The URL to fetch this document's content from.
  final Uri url;
}

/// The response returned by `POST /esignsp/v2/signer_processes`, mirroring
/// the decompiled `DocSignatureProcessModel`.
class UaePassSigningProcess {
  /// Creates a signing-process result.
  const UaePassSigningProcess({
    required this.id,
    required this.pendingTasks,
    required this.documents,
  });

  /// Parses a signing-process result from JSON.
  factory UaePassSigningProcess.fromJson(Map<String, dynamic> json) {
    final tasksJson = json['Tasks'] as Map<String, dynamic>? ?? const {};
    final pendingJson = tasksJson['pending'] as List? ?? const [];
    final documentsJson = json['documents'] as List? ?? const [];
    return UaePassSigningProcess(
      id: json['id'] as String? ?? '',
      pendingTasks: pendingJson
          .cast<Map<String, dynamic>>()
          .map(UaePassSigningPendingTask.fromJson)
          .toList(growable: false),
      documents: documentsJson
          .cast<Map<String, dynamic>>()
          .map(UaePassSigningDocument.fromJson)
          .toList(growable: false),
    );
  }

  /// The process identifier, used to poll status, download the result, and
  /// clean up.
  final String id;

  /// Tasks the signer still needs to complete.
  final List<UaePassSigningPendingTask> pendingTasks;

  /// Documents attached to this process, once signing has produced output.
  final List<UaePassSigningDocument> documents;

  /// The URL to present to the user to complete signing, if any task is
  /// still pending.
  Uri? get signingUiUrl => pendingTasks.isEmpty ? null : pendingTasks.first.url;
}

/// The terminal outcome of a signing flow driven via the shared WebView
/// controller's `status` callback parameter.
enum UaePassSigningOutcome {
  /// Signing completed successfully.
  finished,

  /// The user cancelled or signing otherwise did not complete.
  cancelled;

  /// Parses UAE Pass's `status` query parameter values.
  static UaePassSigningOutcome fromStatusParam(String? value) {
    switch (value) {
      case 'finished':
      case 'success':
        return UaePassSigningOutcome.finished;
      default:
        return UaePassSigningOutcome.cancelled;
    }
  }
}
