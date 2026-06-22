/// RestoFlow data_remote package - Supabase client wrappers + RPC call sites.
///
/// Owns (per docs/ARCHITECTURE.md section 3) the Supabase RPC call sites. RF-063
/// adds the polling-first `app.sync_pull` wrapper: typed request/response
/// models, a transport seam, and the Supabase-backed transport that accepts an
/// INJECTED `SupabaseClient` (approved decision A2). This package holds NO URLs,
/// keys, or secrets and never constructs a client (DECISION D-011); session
/// establishment (login/pairing/PIN) is out of RF-063 scope.
library;

export 'src/supabase_sync_rpc_transport.dart';
export 'src/sync_cursor.dart';
export 'src/sync_failure.dart';
export 'src/sync_pull_api.dart';
export 'src/sync_pull_request.dart';
export 'src/sync_pull_response.dart';
export 'src/sync_rpc_transport.dart';
export 'src/sync_session.dart';
