/// A complete, unofficial Flutter plugin for UAE Pass.
///
/// Covers app-to-app sign-in, full profile retrieval, document sharing
/// (proof of presentation), PDF e-signature, token refresh and logout.
/// Sign-in and document-signing's browser/native-app hand-off run natively
/// (UAE Pass's official SDK on Android, an in-app WKWebView on iOS); every
/// other capability is plain Dart HTTPS calls. See the package README for
/// setup and usage.
library;

export 'src/auth/state_generator.dart' show UaePassStateGenerator;
export 'src/client.dart' show UaePassKit;
export 'src/config.dart' show UaePassConfig, kUaePassDefaultScope;
export 'src/environment.dart' show UaePassEnvironment, UaePassEndpoints;
export 'src/exceptions.dart'
    show
        UaePassException,
        UaePassConfigurationException,
        UaePassNetworkException,
        UaePassServerException,
        UaePassParsingException,
        UaePassStateMismatchException,
        UaePassAppNotInstalledException,
        UaePassTimeoutException;
export 'src/locale.dart' show UaePassLocale;
export 'src/models/auth_result.dart'
    show
        UaePassAuthResult,
        UaePassAuthSuccess,
        UaePassAuthCancelled,
        UaePassAuthFailure;
export 'src/models/document_share.dart'
    show
        UaePassDocumentRequestItem,
        UaePassDocumentShareOrigin,
        UaePassDocumentShareRequest,
        UaePassDocumentShareHandle,
        UaePassDocumentAuthorizationState,
        UaePassDocumentShareItem,
        DocumentShareStatus,
        DocumentSharePending,
        DocumentShareComplete,
        DocumentShareTimedOut,
        UaePassDocumentShareBackend;
export 'src/models/profile.dart' show UaePassProfile, UaePassHomeAddress;
export 'src/models/signing.dart'
    show
        UaePassSignatureRectangle,
        UaePassSignatureAppearanceDetail,
        UaePassSignatureField,
        UaePassSigner,
        UaePassSigningRequest,
        UaePassSigningPendingTask,
        UaePassSigningDocument,
        UaePassSigningProcess,
        UaePassSigningOutcome,
        kUaePassSignProcessType,
        kUaePassSignPolicyId;
export 'src/models/token_response.dart' show UaePassTokenResponse;
export 'src/token_exchanger.dart'
    show
        UaePassTokenExchanger,
        UaePassDirectTokenExchanger,
        UaePassSigningTokenExchanger,
        UaePassDirectSigningTokenExchanger;
