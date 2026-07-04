import 'dart:convert';
import 'dart:typed_data';

import '../print_result.dart';

/// A LOCAL print-bridge client (RF-115).
///
/// A Flutter-web POS/KDS app cannot open a raw TCP/USB socket to a receipt
/// printer, so a real "bridge" is a small LOOPBACK companion HTTP service the
/// app POSTs jobs to; the service holds the printer's LAN target in ITS OWN
/// local config (the app/server never learn the printer IP — this respects the
/// security model where `get_device_printer_assignments` deliberately omits
/// `connection_config`). This client talks to that bridge and maps its replies
/// to HONEST outcomes.
///
/// CRITICAL HONESTY: ESC/POS over a socket has NO paper-level acknowledgement.
/// The strongest truthful terminal state is "**sent to the printer**" (bytes
/// delivered to the transport), NOT "printed & confirmed by the hardware". A
/// demo/sink bridge returns [BridgeSubmitOutcome.accepted] and must never be
/// presented as a physical print.

/// The tiny HTTP response the bridge seam returns (status + body only).
class BridgeHttpResponse {
  const BridgeHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

/// The HTTP seam the [PrintBridgeClient] talks through. Injected so the client
/// is fully unit-testable with NO sockets; the app wires the `package:http`
/// implementation ([HttpBridgeHttpClient]).
abstract class BridgeHttpClient {
  Future<BridgeHttpResponse> getUrl(Uri url);
  Future<BridgeHttpResponse> postJson(Uri url, String body);
}

/// The reachability of a configured bridge.
enum BridgeHealth {
  /// The bridge answered `/health` with `{ok:true}`.
  connected,

  /// The bridge could not be reached at all (connection refused / timeout).
  unreachable,

  /// The bridge answered but not as a valid RestoFlow print bridge.
  misconfigured,
}

/// The honest outcome of submitting a job to the bridge.
enum BridgeSubmitOutcome {
  /// The bridge RECEIVED the job but did NOT confirm delivery to a printer
  /// (a demo/sink bridge). NEVER present this as a physical print.
  accepted,

  /// The bridge CONFIRMED it wrote the bytes to the printer transport (RAW
  /// 9100 socket write succeeded). This is the strongest truthful terminal
  /// state — it is still NOT a hardware "paper printed" acknowledgement.
  sentToPrinter,

  /// The submit failed; see [BridgeSubmitResult.category]/`message`.
  failed,
}

/// The result of a [PrintBridgeClient.submit] call.
class BridgeSubmitResult {
  const BridgeSubmitResult._(
    this.outcome, {
    this.category,
    this.message,
    this.mode,
  });

  /// The bridge received the job but did not reach hardware (e.g. sink mode).
  const BridgeSubmitResult.accepted({String? mode})
    : this._(BridgeSubmitOutcome.accepted, mode: mode);

  /// The bridge confirmed the bytes were written to the printer transport.
  const BridgeSubmitResult.sentToPrinter({String? mode})
    : this._(BridgeSubmitOutcome.sentToPrinter, mode: mode);

  /// The submit failed with a mappable [category] + optional diagnostic.
  const BridgeSubmitResult.failed(
    PrinterErrorCategory category, [
    String? message,
  ]) : this._(BridgeSubmitOutcome.failed, category: category, message: message);

  final BridgeSubmitOutcome outcome;

  /// The failure category when [outcome] is [BridgeSubmitOutcome.failed].
  final PrinterErrorCategory? category;

  /// A developer-facing diagnostic (never UI chrome).
  final String? message;

  /// The bridge's reported delivery mode (`'tcp'` / `'sink'`), if any.
  final String? mode;

  /// Whether the bridge accepted the job (received or sent) rather than failed.
  bool get ok => outcome != BridgeSubmitOutcome.failed;

  @override
  String toString() => outcome == BridgeSubmitOutcome.failed
      ? 'BridgeSubmitResult.failed($category, $message)'
      : 'BridgeSubmitResult.${outcome.name}(mode: $mode)';
}

/// Thrown when a configured bridge base URL is NOT loopback (local-only).
///
/// Mirrors the e2e `assertLocalOnly` fence: the app may only POST print jobs to
/// a loopback address (127.0.0.1 / localhost / [::1] / *.localhost), never a
/// remote host. Fails clearly rather than silently pointing at the network.
class NonLoopbackBridgeUrlException implements Exception {
  const NonLoopbackBridgeUrlException(this.url, this.reason);

  final String url;
  final String reason;

  @override
  String toString() =>
      'NonLoopbackBridgeUrlException: the print bridge URL "$url" is not '
      'LOCAL-ONLY ($reason). The bridge must be a loopback address '
      '(127.0.0.1 / localhost / [::1]).';
}

/// Validates that [url] is a loopback (local-only) bridge base URL and returns
/// the parsed [Uri]. Throws [NonLoopbackBridgeUrlException] otherwise.
///
/// Allowed: `localhost`, `*.localhost`, `::1`, and the `127.0.0.0/8` loopback
/// block. Explicitly rejected: any other host, including `0.0.0.0` (that binds
/// all interfaces — it is never a valid loopback *client* target).
Uri assertLoopbackBridgeUrl(String url) {
  final Uri uri;
  try {
    uri = Uri.parse(url);
  } on FormatException {
    throw NonLoopbackBridgeUrlException(url, 'not a valid URL');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw NonLoopbackBridgeUrlException(url, 'scheme must be http or https');
  }
  final host = uri.host;
  if (host.isEmpty) {
    throw NonLoopbackBridgeUrlException(url, 'missing host');
  }
  final normalized = host.replaceAll(RegExp(r'^\[|\]$'), '').toLowerCase();
  final isLoopback =
      normalized == 'localhost' ||
      normalized == '::1' ||
      normalized.endsWith('.localhost') ||
      normalized == '127.0.0.1' ||
      normalized.startsWith('127.');
  if (!isLoopback) {
    throw NonLoopbackBridgeUrlException(url, 'host "$host" is not loopback');
  }
  return uri;
}

/// The default local bridge endpoint (loopback, RF-115).
const String kDefaultPrintBridgeUrl = 'http://127.0.0.1:8787';

/// Talks to a LOCAL loopback print bridge over HTTP and maps its replies to
/// honest [BridgeHealth] / [BridgeSubmitResult] values.
class PrintBridgeClient {
  /// Builds a client for [baseUrl] (validated loopback) over [httpClient].
  /// [maxPayloadBytes] guards against pathological payloads (1 MiB default).
  PrintBridgeClient({
    required String baseUrl,
    required BridgeHttpClient httpClient,
    this.role,
    this.maxPayloadBytes = 1024 * 1024,
  }) : baseUrl = assertLoopbackBridgeUrl(baseUrl),
       _http = httpClient;

  /// The validated loopback base URL.
  final Uri baseUrl;

  /// The optional printer role this client targets (`'receipt'`/`'kitchen'`),
  /// forwarded to the bridge so it can pick the configured target.
  final String? role;

  final BridgeHttpClient _http;
  final int maxPayloadBytes;

  Uri _resolve(String path) => baseUrl.replace(path: path);

  /// Probes the bridge's `/health` endpoint.
  Future<BridgeHealth> health() async {
    final BridgeHttpResponse res;
    try {
      res = await _http.getUrl(_resolve('/health'));
    } catch (_) {
      return BridgeHealth.unreachable;
    }
    if (res.statusCode != 200) return BridgeHealth.misconfigured;
    final decoded = _tryDecode(res.body);
    if (decoded is Map && decoded['ok'] == true) return BridgeHealth.connected;
    return BridgeHealth.misconfigured;
  }

  /// Submits already-encoded ESC/POS [bytes] to the bridge.
  ///
  /// Returns [BridgeSubmitOutcome.sentToPrinter] only when the bridge CONFIRMS
  /// it wrote the bytes to the printer transport; [BridgeSubmitOutcome.accepted]
  /// for a demo/sink bridge; and [BridgeSubmitOutcome.failed] on any transport
  /// or protocol error. Never fabricates a success.
  Future<BridgeSubmitResult> submit({
    required Uint8List bytes,
    String? role,
  }) async {
    if (bytes.isEmpty) {
      return const BridgeSubmitResult.failed(
        PrinterErrorCategory.unknown,
        'empty payload',
      );
    }
    if (bytes.length > maxPayloadBytes) {
      return const BridgeSubmitResult.failed(
        PrinterErrorCategory.unsupported,
        'payload exceeds bridge limit',
      );
    }
    final body = jsonEncode(<String, Object?>{
      'format': 'escpos',
      if ((role ?? this.role) != null) 'role': role ?? this.role,
      'payloadBase64': base64Encode(bytes),
    });
    final BridgeHttpResponse res;
    try {
      res = await _http.postJson(_resolve('/print'), body);
    } catch (e) {
      return BridgeSubmitResult.failed(
        PrinterErrorCategory.unreachable,
        'bridge unreachable: $e',
      );
    }
    final decoded = _tryDecode(res.body);
    if (decoded is! Map) {
      return const BridgeSubmitResult.failed(
        PrinterErrorCategory.unknown,
        'invalid bridge response',
      );
    }
    if (res.statusCode != 200 || decoded['ok'] != true) {
      return BridgeSubmitResult.failed(
        _categoryFrom(decoded['category']),
        decoded['error']?.toString(),
      );
    }
    final status = decoded['status']?.toString();
    final mode = decoded['mode']?.toString();
    switch (status) {
      case 'sent':
        return BridgeSubmitResult.sentToPrinter(mode: mode);
      case 'accepted_sink':
        return BridgeSubmitResult.accepted(mode: mode ?? 'sink');
      default:
        // An `ok` response with an unknown status: stay conservative — the
        // bridge received it, but we cannot claim it reached a printer.
        return BridgeSubmitResult.accepted(mode: mode);
    }
  }

  static PrinterErrorCategory _categoryFrom(Object? raw) {
    switch (raw?.toString()) {
      case 'unreachable':
        return PrinterErrorCategory.unreachable;
      case 'unsupported':
        return PrinterErrorCategory.unsupported;
      case 'paper_out':
      case 'paperOut':
        return PrinterErrorCategory.paperOut;
      case 'cover_open':
      case 'coverOpen':
        return PrinterErrorCategory.coverOpen;
      default:
        return PrinterErrorCategory.unknown;
    }
  }

  static Object? _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
}
