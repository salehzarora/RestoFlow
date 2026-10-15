import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'guarded_kitchen_ack_transport.dart';
import 'sync_rpc_transport.dart';

/// Injected BELOW the SDK's AuthHttpClient. The locked SDK prepares the request
/// body and awaits its access token before calling this client's [send].
/// Bookkeeping is local to one invocation's Zone, never HTTP metadata.
class KitchenAckHttpBoundary extends http.BaseClient {
  KitchenAckHttpBoundary(Uri supabaseUrl, {http.Client? inner})
    : _endpoint = Uri.parse(
        '$supabaseUrl/rest/v1/rpc/acknowledge_kitchen_print_dispatch',
      ),
      _inner = inner ?? http.Client();

  final Uri _endpoint;
  final http.Client _inner;
  final Object _zoneKey = Object();
  bool _closed = false;

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
