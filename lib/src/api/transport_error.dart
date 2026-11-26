import 'package:http/http.dart' as http;

/// Returns the `UaePassNetworkException` message for a transport-level
/// failure, or `null` when [error] is not one.
///
/// This is the web/WASM version: there is no `dart:io`, so every transport
/// failure arrives as an [http.ClientException]. Native platforms use
/// `transport_error_io.dart` instead.
String? transportErrorMessage(Object error) =>
    error is http.ClientException ? 'HTTP client error.' : null;
