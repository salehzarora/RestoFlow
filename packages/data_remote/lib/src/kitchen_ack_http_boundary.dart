import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'card_charge_transport.dart';
import 'guarded_kitchen_ack_transport.dart';
import 'sync_rpc_transport.dart';

/// Injected BELOW the SDK's AuthHttpClient. The locked SDK prepares the request
/// body and awaits its access token before calling this client's [send].
/// Bookkeeping is local to one invocation's Zone, never HTTP metadata.
///
/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C: the same boundary gates the
/// `pos-card-charge` route; it is what grants the card capability, so only
/// the POS client of `createKitchenAckClient` can make a card exchange.
class KitchenAckHttpBoundary extends http.BaseClient {
  KitchenAckHttpBoundary(Uri supabaseUrl, {http.Client? inner})
    : _endpoint = Uri.parse(
        '$supabaseUrl/rest/v1/rpc/acknowledge_kitchen_print_dispatch',
      ),
      _cardChargeEndpoint = Uri.parse(
        '$supabaseUrl/functions/v1/$posCardChargeFunction',
      ),
      _inner = inner ?? http.Client();

  final Uri _endpoint;
  final Uri _cardChargeEndpoint;
  final http.Client _inner;
  final Object _zoneKey = Object();
  final Object _cardZoneKey = Object();
  bool _closed = false;

  /// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C: runs [send] as the ONE exchange of
  /// [exchange]. Inside its Zone the card route reaches the HTTP client at most
  /// once, only as exactly the exchange's POST and bytes to the card endpoint,
  /// while the exchange is active and its composed handoff check holds (the
  /// device-session guard's and, when given, the caller's) — asked at the
  /// handoff itself, after the SDK prepared the access token. Outside such a
  /// Zone the card route is refused: a plain SDK call is no fallback.
  Future<T> runCardCharge<T>(
    CardChargeExchange exchange,
    Future<T> Function() send,
  ) => runZoned(send, zoneValues: {_cardZoneKey: exchange});

  /// Both invocation kinds traverse SDK authentication. Existing direct/local
  /// ACKs use an exact invocation context without an imported-spool permit;
  /// guarded spool ACKs must provide [isCurrent]. Neither kind can borrow the
  /// context of another client or concurrent call.
  Future<Object?> invokeAck(
    Future<Object?> Function() invoke,
    Map<String, dynamic> params, {
    required String schema,
    bool Function()? isCurrent,
  }) async {
    final context = _AckInvocation(
      Map<String, dynamic>.unmodifiable(params),
      schema,
      isCurrent,
    );
    try {
      final result = await runZoned(invoke, zoneValues: {_zoneKey: context});
      if (!context.delegated) {
        throw const KitchenAckDispatchDeferred();
      }
      return result;
    } catch (_) {
      // SDK/repository layers may wrap the original local exception. The
      // per-call flag survives without manufacturing a response or outcome.
      if (context.denied && !context.delegated) {
        throw const KitchenAckDispatchDeferred();
      }
      rethrow;
    } finally {
      // Future.timeout does not cancel the SDK's authentication Future. A late
      // continuation must never resurrect an invocation that already ended.
      context.active = false;
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_isCardChargeRoute(request.url)) return _sendCardCharge(request);
    // Auth refresh, policy reads, storage and unrelated RPCs remain independent
    // of the ACK permit, including when started in an ACK invocation's Zone.
    if (!_isAckRoute(request.url)) return _inner.send(request);
    final context = Zone.current[_zoneKey];
    var allowed = false;
    if (context is _AckInvocation) {
      try {
        allowed =
            !_closed &&
            context.active &&
            !context.delegated &&
            request.url == _endpoint &&
            request.method == 'POST' &&
            context.schema == 'public' &&
            request.headers['Content-Profile'] == 'public' &&
            request is http.Request &&
            _matchesParams(request.body, context.params) &&
            (context.isCurrent?.call() ?? true);
      } catch (_) {
        allowed = false;
      }
    }
    if (!allowed) {
      if (context is _AckInvocation && context.delegated) {
        // A blocked redispatch cannot turn an earlier real handoff into a
        // claim that nothing was sent. Preserve uncertainty and its evidence.
        return Future.error(
          const SyncTransportException(
            SyncTransportErrorKind.transient,
            code: 'kitchen_ack_redispatch_blocked',
          ),
        );
      }
      if (context is _AckInvocation && !context.delegated) {
        context.denied = true;
      }
      return Future.error(const KitchenAckDispatchDeferred());
    }
    final invocation = context as _AckInvocation;
    if (invocation.isCurrent != null) {
      // IOClient otherwise follows redirects below this adapter. Protected ACKs
      // have one HTTP handoff, with no redirect/retry redispatch below the guard.
      request.followRedirects = false;
    }
    invocation.delegated = true;
    // No await follows validation before this effective HTTP transport handoff.
    // Socket connection/writes below it cannot be revoked by a later policy read.
    return _inner.send(request);
  }

  Future<http.StreamedResponse> _sendCardCharge(http.BaseRequest request) {
    final exchange = Zone.current[_cardZoneKey];
    final refusal = _cardRefusal(request, exchange);
    if (refusal != null) return Future.error(refusal);
    final permit = exchange as CardChargeExchange;
    final exact = request as http.Request;
    // The handoff, with no await after the checks. Redirects are never
    // followed (IOClient would answer a 303 with a second, GET request), and
    // the exchange's end aborts a connection still opening before any byte of
    // the request is written. Same method, URL, headers and bytes.
    final handoff =
        http.AbortableRequest(
            exact.method,
            exact.url,
            abortTrigger: permit._ended.future,
          )
          ..followRedirects = false
          ..persistentConnection = exact.persistentConnection
          ..headers.addAll(exact.headers)
          ..bodyBytes = exact.bodyBytes;
    permit._handedOff = true;
    return _inner.send(handoff);
  }

  /// Why the card route may not be handed off now, or null when it may.
  CardChargeHandoffRefused? _cardRefusal(
    http.BaseRequest request,
    Object? exchange,
  ) {
    const other = CardChargeHandoffRefused(deviceSessionUnverified: false);
    if (exchange is! CardChargeExchange) return other;
    try {
      if (_closed || !exchange._active || exchange._handedOff) return other;
      if (request is! http.Request ||
          request.method != 'POST' ||
          request.url.hasQuery ||
          request.url.hasFragment ||
          request.url != _cardChargeEndpoint ||
          !_sameBytes(request.bodyBytes, exchange._bytes)) {
        return other;
      }
      if (!exchange._isCurrent()) {
        return const CardChargeHandoffRefused(deviceSessionUnverified: true);
      }
      return null;
    } catch (_) {
      return other;
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Any request that names the card-charge function as a `/`-separated
  /// component of its decoded path, query or fragment, in any letter case, on
  /// any origin: fail closed. It is handed off only as exactly this client's
  /// endpoint, with no query or fragment ([_cardRefusal]), and never passed
  /// through — also where the SDK's URL and [_cardChargeEndpoint] are derived
  /// differently, or where a base URL with a query or a fragment moves the
  /// function's name out of the path.
  static bool _isCardChargeRoute(Uri uri) => [uri.path, uri.query, uri.fragment]
      .expand((part) => _decoded(part).split('/'))
      .any((component) => component.toLowerCase() == posCardChargeFunction);

  /// [part] percent-decoded, or as it is when it cannot be decoded.
  static String _decoded(String part) {
    try {
      return Uri.decodeComponent(part);
    } catch (_) {
      return part;
    }
  }

  static bool _isAckRoute(Uri uri) =>
      uri.pathSegments.length >= 2 &&
      uri.pathSegments[uri.pathSegments.length - 2] == 'rpc' &&
      uri.pathSegments.last == 'acknowledge_kitchen_print_dispatch';

  static bool _matchesParams(String body, Map<String, dynamic> expected) {
    final actual = jsonDecode(body);
    if (actual is! Map || actual.length != expected.length) return false;
    // ACK parameters are scalars. Reject mutable nested payloads rather than
    // permitting a shallow snapshot to change after authorization.
    return expected.entries.every(
      (entry) =>
          (entry.value == null || entry.value is String) &&
          actual.containsKey(entry.key) &&
          actual[entry.key] == entry.value,
    );
  }

  @override
  void close() {
    _closed = true;
    _inner.close();
  }
}

class _AckInvocation {
  _AckInvocation(this.params, this.schema, this.isCurrent);

  final Map<String, dynamic> params;
  final String schema;
  final bool Function()? isCurrent;
  bool active = true, delegated = false, denied = false;
}

/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C: the permit of ONE card-charge exchange,
/// shared with the boundary through [KitchenAckHttpBoundary.runCardCharge].
final class CardChargeExchange {
  CardChargeExchange(List<int> bytes, this._isCurrent)
    : _bytes = List<int>.unmodifiable(bytes);

  final List<int> _bytes;
  final bool Function() _isCurrent;
  final Completer<void> _ended = Completer<void>();
  bool _handedOff = false;

  /// True once the request was handed to the HTTP client.
  bool get handedOff => _handedOff;

  /// Ends the exchange — at its answer, its failure or its deadline. No handoff
  /// can follow, and a connection still opening is aborted before any byte of
  /// the request is written.
  void end() {
    if (!_ended.isCompleted) _ended.complete();
  }

  bool get _active => !_ended.isCompleted;
}

/// The boundary refused a card handoff: nothing of this request reached the
/// HTTP client. Local; carries no request or credentials.
final class CardChargeHandoffRefused implements Exception {
  const CardChargeHandoffRefused({required this.deviceSessionUnverified});

  /// The exchange's composed check refused at the handoff (the device-session
  /// guard's and, when given, the caller's own `isCurrent`).
  final bool deviceSessionUnverified;

  @override
  String toString() => 'CardChargeHandoffRefused';
}
