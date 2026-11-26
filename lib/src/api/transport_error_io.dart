import 'dart:io';

import 'package:http/http.dart' as http;

/// Returns the `UaePassNetworkException` message for a transport-level
/// failure, or `null` when [error] is not one.
///
/// This is the native version (Android/iOS), which can also tell
/// `dart:io`'s socket and HTTP errors apart. The checks run in this order
/// because `package:http` may throw an error that is both a
/// [SocketException] and an [http.ClientException].
String? transportErrorMessage(Object error) {
  if (error is SocketException) return 'No network connection.';
  if (error is HttpException) return 'HTTP transport error.';
  if (error is http.ClientException) return 'HTTP client error.';
  return null;
}
