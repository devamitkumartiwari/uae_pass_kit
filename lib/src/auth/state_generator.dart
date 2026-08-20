import 'dart:convert';
import 'dart:math';

/// Generates cryptographically random `state` values for CSRF protection.
///
/// `flutter_uae_pass` defaults `state` to a hardcoded literal
/// (`"HnlHOJTkTb66Y5H"` in `setUpEnvironment`, `"123123213"` in
/// `setUpSandbox`) unless the caller overrides it — meaning most
/// integrators get effectively no CSRF protection by default. This plugin
/// generates a fresh random value for every sign-in attempt instead, with
/// no way to accidentally fall back to a static default.
abstract final class UaePassStateGenerator {
  static final Random _random = Random.secure();

  /// Generates a URL-safe random state string of [byteLength] random bytes
  /// (32 bytes of entropy by default), base64url-encoded without padding.
  static String generate({int byteLength = 32}) {
    final bytes = List<int>.generate(byteLength, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
