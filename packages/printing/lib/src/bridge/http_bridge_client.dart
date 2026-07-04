import 'package:http/http.dart' as http;

import 'print_bridge_client.dart';

/// The real [BridgeHttpClient] over `package:http` (RF-115).
///
/// `package:http`'s `Client()` is cross-platform: on Flutter web it uses the
/// browser (fetch/XHR), on the Dart VM it uses `dart:io`. The [PrintBridgeClient]
/// itself stays HTTP-agnostic (this seam is injected) so its logic is unit-
/// testable with no sockets; this is the ONLY place that touches the network.
class HttpBridgeHttpClient implements BridgeHttpClient {
  HttpBridgeHttpClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 5),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  @override
  Future<BridgeHttpResponse> getUrl(Uri url) async {
    final res = await _client.get(url).timeout(timeout);
    return BridgeHttpResponse(statusCode: res.statusCode, body: res.body);
  }

  @override
  Future<BridgeHttpResponse> postJson(Uri url, String body) async {
    final res = await _client
        .post(
          url,
          headers: const {'content-type': 'application/json'},
          body: body,
        )
        .timeout(timeout);
    return BridgeHttpResponse(statusCode: res.statusCode, body: res.body);
  }

  /// Releases the underlying HTTP client.
  void close() => _client.close();
}
