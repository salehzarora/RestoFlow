import '../models/menu_scope.dart';
import '../models/menu_snapshot.dart';

/// The menu read seam (RF-111): loads the full menu tree for a [MenuScope].
///
/// Concrete sources: the in-memory/demo store, and the REAL
/// `RpcMenuReadSource` over `public.list_menu` (sprint — the GUC-free,
/// manager+ management read that made a plain owner JWT viable).
abstract class MenuReadSource {
  Future<MenuSnapshot> load(MenuScope scope);
}
