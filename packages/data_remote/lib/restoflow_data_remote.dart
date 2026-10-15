/// RestoFlow data_remote package - Supabase client wrappers + RPC call sites.
///
/// Owns (per docs/ARCHITECTURE.md section 3) the Supabase RPC call sites. RF-063
/// adds the polling-first `app.sync_pull` wrapper: typed request/response
/// models, a transport seam, and the Supabase-backed transport that accepts an
/// INJECTED `SupabaseClient` (approved decision A2). R4 also provides an opt-in
/// SDK/client HTTP-boundary factory using public configuration only. Session
/// establishment (login/pairing/PIN) remains in auth bootstrap (DECISION D-011).
library;

export 'src/invalidation_hint.dart';
export 'src/guarded_kitchen_ack_transport.dart';
export 'src/kitchen_ack_http_boundary.dart';
export 'src/invalidation_source.dart';
export 'src/realtime_invalidation_source.dart';
export 'src/supabase_sync_rpc_transport.dart';
export 'src/sync_cursor.dart';
export 'src/sync_failure.dart';
export 'src/sync_pull_api.dart';
export 'src/sync_pull_request.dart';
export 'src/sync_pull_response.dart';
export 'src/sync_rpc_transport.dart';
export 'src/sync_session.dart';
// [POS-OFFLINE-OPERATIONS-002] Pass A: the hold-then-upgrade transport for the
// degraded offline boot (zero-IO transient hold; permanent in-place upgrade).
export 'src/upgradable_sync_transport.dart';
