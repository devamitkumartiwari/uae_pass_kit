/// Base class for every exception this plugin throws.
///
/// Unlike prior community wrappers, which rethrow `PlatformException`
/// messages as raw strings, every failure mode here is a distinct,
/// catchable type so callers can branch on what actually went wrong
/// instead of pattern matching on string content.
sealed class UaePassException implements Exception {
  /// Creates a UAE Pass exception with a human-readable [message].
  const UaePassException(this.message);

  /// A human-readable description of the failure.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The configuration supplied to the plugin is invalid (e.g. an empty
/// client ID, or a redirect URI that doesn't match what UAE Pass returned).
final class UaePassConfigurationException extends UaePassException {
  /// Creates a configuration exception.
  const UaePassConfigurationException(super.message);
}

/// A network-level failure occurred while calling a UAE Pass endpoint
/// (connectivity loss, timeout, DNS failure, etc.).
final class UaePassNetworkException extends UaePassException {
  /// Creates a network exception, optionally wrapping the [cause].
  const UaePassNetworkException(super.message, {this.cause});

  /// The underlying exception that triggered this failure, if any.
  final Object? cause;
}

/// UAE Pass returned a non-success HTTP response for a request.
final class UaePassServerException extends UaePassException {
  /// Creates a server exception carrying the response [statusCode] and, if
  /// present, an [errorCode]/[errorDescription] parsed from the response
  /// body.
  const UaePassServerException(
    super.message, {
    required this.statusCode,
    this.errorCode,
    this.errorDescription,
  });

  /// The HTTP status code UAE Pass responded with.
  final int statusCode;

  /// The machine-readable error code from the response body, if present.
  final String? errorCode;

  /// The human-readable error description from the response body, if
  /// present.
  final String? errorDescription;
}

/// The response returned by UAE Pass could not be parsed into the expected
/// model shape.
final class UaePassParsingException extends UaePassException {
  /// Creates a parsing exception.
  const UaePassParsingException(super.message);
}

/// The `state` parameter returned by UAE Pass did not match the one sent
/// with the authorization request — a possible CSRF/tampering signal. The
/// flow is aborted rather than proceeding.
final class UaePassStateMismatchException extends UaePassException {
  /// Creates a state-mismatch exception.
  const UaePassStateMismatchException(super.message);
}

/// The native UAE Pass app is required for this operation but is not
/// installed, and no fallback was possible.
final class UaePassAppNotInstalledException extends UaePassException {
  /// Creates an app-not-installed exception.
  const UaePassAppNotInstalledException(super.message);
}

/// A document-signing or document-sharing request timed out while polling
/// for a terminal status.
final class UaePassTimeoutException extends UaePassException {
  /// Creates a timeout exception.
  const UaePassTimeoutException(super.message);
}
