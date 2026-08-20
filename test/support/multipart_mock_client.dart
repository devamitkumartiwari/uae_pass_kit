import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Builds a [MockClient] that captures the original [http.MultipartRequest]
/// sent through it and responds with [jsonBody].
///
/// `MockClient`'s plain (non-streaming) constructor always reconstructs a
/// finalized `http.Request` from the raw body bytes before invoking its
/// handler — so a request built as `http.MultipartRequest` is never
/// observable as one through it (`.fields`/`.files` are gone by the time
/// the handler sees it). `MockClient.streaming` instead hands the handler
/// the exact `BaseRequest` instance that was sent, before finalization
/// destroys that type information, which is what lets these tests assert
/// on the real fields/files UAE Pass's multipart token/signing endpoints
/// receive.
MockClient mockMultipartClient({
  required void Function(http.MultipartRequest request) onRequest,
  required String jsonBody,
  int statusCode = 200,
}) {
  return MockClient.streaming((request, bodyStream) async {
    onRequest(request as http.MultipartRequest);
    final bodyBytes = jsonBody.codeUnits;
    return http.StreamedResponse(
      Stream.value(bodyBytes),
      statusCode,
      headers: const {'content-type': 'application/json'},
    );
  });
}
