import '../models/menu_scope.dart';
import '../models/menu_snapshot.dart';

/// The menu read seam (RF-111): loads the full menu tree for a [MenuScope].
///
/// Today the concrete source is the in-memory/demo store. A real online source
/// (RLS-scoped direct table SELECT, or `sync_pull`) is DEFERRED until the
/// auth/org-context bridge exists (D1/D3) — the RF-109 menu SELECT/RPC paths are
/// gated on `app.current_org_id()`, which a plain owner JWT does not set.
abstract class MenuReadSource {
  Future<MenuSnapshot> load(MenuScope scope);
}
