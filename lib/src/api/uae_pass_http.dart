import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../exceptions.dart';

/// A thin HTTP helper shared by every UAE Pass API call in this plugin.
///
/// Centralizes error translation (network failure vs. non-2xx server
/// response vs. unparseable body) into the typed [UaePassException]
/// hierarchy, so no call site has to reimplement it, and every UAE Pass
/// call raises a consistent, catchable failure type.
class UaePassHttpClient {
  /// Creates an HTTP client wrapper. Supply [client] in tests to inject a
  /// mock `http.Client`.
  UaePassHttpClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Performs a `GET` request and decodes the JSON response body.
  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final response = await _guard(() => _client.get(uri, headers: headers));
    return _decode(response);
  }

  /// Performs a `multipart/form-data` `POST` request with the given
  /// [fields] and optional [files], and decodes the JSON response body.
  ///
  /// UAE Pass's token endpoint explicitly requires `multipart/form-data`
  /// rather than the more common `application/x-www-form-urlencoded` — a
  /// commonly-cited source of integration bugs per UAE Pass's own "Common
  /// Integration Issues" documentation page.
  Future<Map<String, dynamic>> postMultipart(
    Uri uri, {
    required Map<String, String> fields,
    List<http.MultipartFile> files = const [],
    Map<String, String>? headers,
  }) async {
    final request = http.MultipartRequest('POST', uri)
      ..fields.addAll(fields)
      ..files.addAll(files);
    if (headers != null) request.headers.addAll(headers);

    final response = await _guard(() async {
      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    });
    return _decode(response);
  }

  /// Performs a `DELETE` request, ignoring any response body.
  Future<void> delete(Uri uri, {Map<String, String>? headers}) async {
    final response = await _guard(() => _client.delete(uri, headers: headers));
    if (response.statusCode >= 400) {
      throw _serverException(response);
    }
  }

  /// Performs a `GET` request and returns the raw response bytes, for
  /// downloading binary content such as a signed PDF.
  Future<List<int>> getBytes(Uri uri, {Map<String, String>? headers}) async {
    final response = await _guard(() => _client.get(uri, headers: headers));
    if (response.statusCode >= 400) {
      throw _serverException(response);
    }
    return response.bodyBytes;
  }

  Future<http.Response> _guard(Future<http.Response> Function() send) async {
    try {
      return await send();
    } on SocketException catch (e) {
      throw UaePassNetworkException('No network connection.', cause: e);
    } on HttpException catch (e) {
      throw UaePassNetworkException('HTTP transport error.', cause: e);
    } on http.ClientException catch (e) {
      throw UaePassNetworkException('HTTP client error.', cause: e);
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode >= 400) {
      throw _serverException(response);
    }
    if (response.body.isEmpty) return const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const UaePassParsingException(
        'Expected a JSON object in the UAE Pass response body.',
      );
    } on FormatException catch (e) {
      throw UaePassParsingException(
        'Could not parse UAE Pass response as JSON: ${e.message}',
      );
    }
  }

  UaePassServerException _serverException(http.Response response) {
    String? errorCode;
    String? errorDescription;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        errorCode = decoded['error'] as String?;
        errorDescription =
            decoded['error_description'] as String? ??
            decoded['errorDescription'] as String?;
      }
    } on FormatException {
      // Body wasn't JSON; fall through with no parsed error detail.
    }
    return UaePassServerException(
      errorDescription ??
          'UAE Pass request failed with status ${response.statusCode}.',
      statusCode: response.statusCode,
      errorCode: errorCode,
      errorDescription: errorDescription,
    );
  }

  /// Releases the underlying HTTP client's resources.
  void close() => _client.close();
}
