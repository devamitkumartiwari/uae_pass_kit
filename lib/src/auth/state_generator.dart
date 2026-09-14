import 'dart:convert';
import 'dart:math';

/// Generates cryptographically random `state` values for CSRF protection.
///
/// A fresh random value is generated for every sign-in attempt, with no
/// static default to accidentally fall back to.
abstract final class UaePassStateGenerator {
  static final Random _random = Random.secure();

  /// Generates a URL-safe random state string of [byteLength] random bytes
  /// (32 bytes of entropy by default), base64url-encoded without padding.
  static String generate({int byteLength = 32}) {
    final bytes = List<int>.generate(byteLength, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
