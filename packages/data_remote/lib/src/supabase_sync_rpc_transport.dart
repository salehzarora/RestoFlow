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
/// `app.sync_pull` lives in the `app` schema, so the call selects that schema
/// (`client.schema('app').rpc(...)`) — a bare `rpc('sync_pull')` would target
/// `public` and 404. NOTE: the server must also EXPOSE the `app` schema to
/// PostgREST (`[api] schemas` in supabase/config.toml) for the live path to
/// reach this function; that server/config change is OUT of RF-063 scope (which
/// stops at the injected session seam) and belongs to the live-wiring ticket.
class SupabaseSyncRpcTransport implements SyncRpcTransport {
  const SupabaseSyncRpcTransport(this._client, {String schema = 'app'})
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
