import 'dart:async';

import 'package:supabase/supabase.dart';

import 'sync_rpc_transport.dart';

/// The Supabase-backed [SyncRpcTransport] (RF-063): the ONLY file that imports
/// the Supabase SDK.
///
/// It accepts an INJECTED [SupabaseClient] (approved decision A2) — it never
/// constructs a client and never holds a URL, anon key, or any secret
/// (DECISION D-011). The client must already carry an authenticated session;
/// establishing that session is out of RF-063 scope.
///
/// The default schema is `public` (RF-064): the client calls
/// `client.schema('public').rpc('sync_pull', ...)`, hitting `public.sync_pull` —
/// a narrow SECURITY INVOKER wrapper that delegates verbatim to `app.sync_pull`.
/// This keeps the `app` schema UNEXPOSED in PostgREST (so no other app RPC is
/// reachable over HTTP) while `app.sync_pull` stays the server source of truth.
/// The schema is configurable for tests/alternate deployments, but production
/// targets `public`.
class SupabaseSyncRpcTransport implements SyncRpcTransport {
  const SupabaseSyncRpcTransport(this._client, {String schema = 'public'})
    : _schema = schema;

  final SupabaseClient _client;
  final String _schema;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    try {
      return await _client.schema(_schema).rpc(function, params: params);
    } on PostgrestException catch (e) {
      throw SyncTransportException(
        classifyPostgrestCode(e.code),
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
