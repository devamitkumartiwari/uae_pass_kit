import '../exceptions.dart';

/// The outcome of a [UaePassKit] sign-in attempt.
///
/// This is a sealed type specifically so cancellation and decline are
/// first-class, exhaustively-handled outcomes rather than exceptions or
/// null returns — `flutter_uae_pass` issue #7 documented a full host-app
/// crash from an unguarded null callback on cancel, which this design
/// makes structurally impossible: there is no code path where a cancelled
/// or declined flow reaches calling code as anything other than
/// [UaePassAuthCancelled].
sealed class UaePassAuthResult {
  const UaePassAuthResult();
}

/// The user completed authentication and UAE Pass returned an
/// authorization [code] and the [state] it was issued with (already
/// verified to match the request).
final class UaePassAuthSuccess extends UaePassAuthResult {
  /// Creates a successful auth result.
  const UaePassAuthSuccess({required this.code, required this.state});

  /// The OAuth2 authorization code. This is short-lived (UAE Pass's own
  /// documentation is inconsistent about whether it is 10 seconds or 10
  /// minutes) — exchange it for a token immediately.
  final String code;

  /// The `state` value the authorization was completed with.
  final String state;
}

/// The user cancelled or was declined during the UAE Pass authentication
/// screen. This is a normal, expected outcome — not an error — and callers
/// should treat it as such (e.g. return to the previous screen silently).
final class UaePassAuthCancelled extends UaePassAuthResult {
  /// Creates a cancelled auth result.
  const UaePassAuthCancelled();
}

/// Authentication failed for a reason other than user cancellation.
final class UaePassAuthFailure extends UaePassAuthResult {
  /// Creates a failed auth result wrapping the [exception] that caused it.
  const UaePassAuthFailure(this.exception);

  /// The exception describing what went wrong.
  final UaePassException exception;
}
