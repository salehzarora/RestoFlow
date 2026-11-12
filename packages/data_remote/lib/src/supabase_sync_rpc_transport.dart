import 'dart:async';
import 'dart:convert';

import 'package:supabase/supabase.dart';
import 'package:http/http.dart' as http;

import 'card_charge_transport.dart';
import 'sync_rpc_transport.dart';
import 'guarded_kitchen_ack_transport.dart';
import 'kitchen_ack_http_boundary.dart';

/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C: true in a browser build, where the card
/// capability refuses before any IO (the function serves native POS only).
const bool _onWeb = bool.fromEnvironment('dart.library.js_interop');

/// The Supabase-backed [SyncRpcTransport] (RF-063): the ONLY file that imports
/// the Supabase SDK.
///
/// Normal construction accepts an INJECTED [SupabaseClient] (decision A2).
/// R4's opt-in factory pairs an SDK client with its ACK HTTP boundary using
/// public client configuration only. Authentication remains in the SDK;
/// session establishment stays in the auth bootstrap (DECISION D-011).
///
/// The default schema is `public` (RF-064): the client calls
/// `client.schema('public').rpc('sync_pull', ...)`, hitting `public.sync_pull` —
/// a narrow SECURITY INVOKER wrapper that delegates verbatim to `app.sync_pull`.
/// This keeps the `app` schema UNEXPOSED in PostgREST (so no other app RPC is
/// reachable over HTTP) while `app.sync_pull` stays the server source of truth.
/// The schema is configurable for tests/alternate deployments, but production
/// targets `public`.
class SupabaseSyncRpcTransport
    implements
        GuardedKitchenAckTransport,
        AuthenticatedWebOrderDecisionTransport,
        AuthenticatedCardChargeTransport {
  const SupabaseSyncRpcTransport(
    this._client, {
    String schema = 'public',
    Duration timeout = const Duration(seconds: 15),
  }) : _schema = schema,
       _timeout = timeout,
       _kitchenAckBoundary = null;

  const SupabaseSyncRpcTransport._guarded(
    this._client,
    this._kitchenAckBoundary,
    this._timeout,
  ) : _schema = 'public';

  /// Constructs the SDK client and its guarded transport as one binding. A
  /// caller cannot label an arbitrary, unadapted SDK client as guard-capable.
  /// The SDK still owns authentication; only public client configuration enters.
  static ({
    SupabaseClient client,
    SupabaseSyncRpcTransport transport,
    KitchenAckHttpBoundary boundary,
  })
  createKitchenAckClient(
    String supabaseUrl,
    String publicKey, {
    http.Client? inner,
    AuthClientOptions authOptions = const AuthClientOptions(),
    Duration timeout = const Duration(seconds: 15),
  }) {
    final boundary = KitchenAckHttpBoundary(
      Uri.parse(supabaseUrl),
      inner: inner,
    );
    final client = SupabaseClient(
      supabaseUrl,
      publicKey,
      httpClient: boundary,
      authOptions: authOptions,
    );
    return (
      client: client,
      transport: SupabaseSyncRpcTransport._guarded(client, boundary, timeout),
      boundary: boundary,
    );
  }

  final SupabaseClient _client;
  final String _schema;
  final KitchenAckHttpBoundary? _kitchenAckBoundary;

  /// PILOT-OPERATIONS-CORRECTIONS-001: a BOUNDED request timeout. After an app
  /// resume the underlying TCP socket can be half-open (it died during suspend);
  /// without this the pull would hang on the SDK's default timeout, so a KDS/POS
  /// resume "stuck" window could stretch indefinitely. A bounded timeout turns
  /// that into a fast TimeoutException -> transient -> offlineStale + retry, so a
  /// resume-triggered refresh recovers promptly instead of hanging.
  final Duration _timeout;

  @override
  Future<Object?> decideWebOrder(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions
          .invoke('pos-web-order-decision', body: body)
          .timeout(_timeout);
      if (response.status != 200) {
        throw const SyncTransportException(SyncTransportErrorKind.transient);
      }
      return response.data;
    } on FunctionException catch (error) {
      // Never retain SDK details: they may contain device credentials or text.
      throw SyncTransportException(
        error.status == 401 || error.status == 403
            ? SyncTransportErrorKind.auth
            : SyncTransportErrorKind.transient,
      );
    } on SyncTransportException {
      rethrow;
    } catch (_) {
      // A timeout is uncertain, not permission to send a second decision.
      throw const SyncTransportException(SyncTransportErrorKind.transient);
    }
  }

  /// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C: one `pos-card-charge` exchange over
  /// the SAME authenticated client, with its own deadline (never [_timeout]).
  /// Only the POS client of [createKitchenAckClient] qualifies: its HTTP
  /// boundary is the exchange's one-handoff gate, so a plain SDK client is
  /// deliberately not a fallback. Native only: a browser would add the
  /// `Origin` the function refuses.
  @override
  Future<CardChargeTransportResult> sendCardCharge(
    Map<String, dynamic> body, {
    bool Function()? isCurrent,
  }) async {
    final boundary = _kitchenAckBoundary;
    if (_onWeb) {
      return const CardChargeTransportFailure.notSent(
        CardChargeFailureReason.unsupportedPlatform,
      );
    }
    if (boundary == null) {
      return const CardChargeTransportFailure.notSent(
        CardChargeFailureReason.capabilityUnavailable,
      );
    }
    // The exact bytes, fixed before the first await: the SDK sends a String
    // body as-is and the boundary hands off only these bytes. The transport
    // never adds, removes or rewrites a field.
    final String encoded;
    try {
      encoded = jsonEncode(body);
    } catch (_) {
      return const CardChargeTransportFailure.notSent(
        CardChargeFailureReason.unencodableBody,
      );
    }
    final attemptId = body['attempt_id'];
    final exchange = CardChargeExchange(
      utf8.encode(encoded),
      isCurrent ?? _always,
    );
    try {
      final response = await boundary
          .runCardCharge(
            exchange,
            () => _client.functions.invoke(
              posCardChargeFunction,
              body: encoded,
              headers: const {'Content-Type': 'application/json'},
            ),
          )
          .timeout(
            posCardChargeTimeout,
            onTimeout: () {
              // Synchronous with the deadline: no handoff can follow it.
              exchange.end();
              throw TimeoutException(null, posCardChargeTimeout);
            },
          );
      final data = response.data;
      if (data is Stream) {
        // An event stream is never the function's answer: close it unread.
        unawaited(data.listen(null).cancel());
      }
      return classifyCardChargeAnswer(
        response.status,
        data is Stream ? null : data,
        attemptId: attemptId is String ? attemptId : null,
      );
    } on FunctionException catch (error) {
      return classifyCardChargeAnswer(error.status, error.details);
    } catch (error) {
      return exchange.handedOff ? _afterHandoff(error) : _beforeHandoff(error);
    } finally {
      exchange.end();
    }
  }

  static bool _always() => true;

  /// The request was handed to the HTTP client: it may have executed. A late
  /// answer is never read and never causes a second send.
  static CardChargeTransportFailure _afterHandoff(Object error) =>
      CardChargeTransportFailure.uncertain(switch (error) {
        TimeoutException() => CardChargeFailureReason.timeout,
        FormatException() => CardChargeFailureReason.malformedAnswer,
        _ => CardChargeFailureReason.transport,
      });

  /// Nothing was handed to the HTTP client, and the ended exchange refuses any
  /// later handoff. Only the gate's own refusal is reported as not sent: a
  /// timeout or a lost connection stays transport-unknown (authorization §6)
  /// even here, so 001F handles every one of them the same way.
  static CardChargeTransportFailure _beforeHandoff(Object error) =>
      switch (error) {
        CardChargeHandoffRefused(deviceSessionUnverified: true) =>
          const CardChargeTransportFailure.notSent(
            CardChargeFailureReason.deviceSessionUnverified,
          ),
        CardChargeHandoffRefused() => const CardChargeTransportFailure.notSent(
          CardChargeFailureReason.handoffRefused,
        ),
        AuthException() => const CardChargeTransportFailure.uncertain(
          CardChargeFailureReason.accessTokenUnavailable,
        ),
        TimeoutException() => const CardChargeTransportFailure.uncertain(
          CardChargeFailureReason.timeout,
        ),
        _ => const CardChargeTransportFailure.uncertain(
          CardChargeFailureReason.transport,
        ),
      };

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) {
    final boundary = _kitchenAckBoundary;
    if (function == 'acknowledge_kitchen_print_dispatch' && boundary != null) {
      final frozen = Map<String, dynamic>.unmodifiable(params);
      return boundary.invokeAck(
        () => _invokeSdk(function, frozen),
        frozen,
        schema: _schema,
      );
    }
    return _invokeSdk(function, params);
  }

  @override
  Future<Object?> invokeGuardedKitchenAck(
    Map<String, dynamic> params, {
    required bool Function() isCurrent,
  }) {
    final boundary = _kitchenAckBoundary;
    if (boundary == null) {
      return Future.error(const KitchenAckDispatchDeferred());
    }
    final frozen = Map<String, dynamic>.unmodifiable(params);
    return boundary.invokeAck(
      () => _invokeSdk('acknowledge_kitchen_print_dispatch', frozen),
      frozen,
      schema: _schema,
      isCurrent: isCurrent,
    );
  }

  Future<Object?> _invokeSdk(
    String function,
    Map<String, dynamic> params,
  ) async {
    try {
      return await _client
          .schema(_schema)
          .rpc(function, params: params)
          .timeout(_timeout);
    } on KitchenAckDispatchDeferred {
      rethrow;
    } on PostgrestException catch (e) {
      // [POS-OFFLINE-OPERATIONS-002 Pass B] The MESSAGE participates in the
      // classification: 42501 is `auth` only for the session-class refusals
      // (see classifyPostgrestCode) — everything else lands `server`.
      throw SyncTransportException(
        classifyPostgrestCode(e.code, message: e.message),
        code: e.code,
        message: e.message,
      );
    } on TimeoutException catch (e) {
      throw SyncTransportException(
        SyncTransportErrorKind.transient,
        message: '$e',
      );
    } catch (e) {
      // Network failures, socket errors, and any other transport-level problem
      // are transient: keep the last good data and retry with backoff.
      throw SyncTransportException(
        SyncTransportErrorKind.transient,
        message: '$e',
      );
    }
  }
}
