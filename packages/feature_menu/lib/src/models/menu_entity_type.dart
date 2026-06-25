/// The six menu entity kinds RF-111 manages, with the exact wire keys the
/// RF-109 backend uses for `public.menu_soft_delete(p_entity)` and the
/// `{ok:true, entity:'<wire>'}` success envelope (DECISION D-031).
enum MenuEntityType {
  category('menu_category'),
  item('menu_item'),
  size('item_size'),
  variant('item_variant'),
  modifier('modifier'),
  modifierOption('modifier_option');

  const MenuEntityType(this.wire);

  /// The exact server wire key (e.g. `menu_item`).
  final String wire;

  /// Maps a wire key to a type, or `null` for any unknown value (fail-closed).
  static MenuEntityType? tryFromWire(String value) {
    for (final type in MenuEntityType.values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}
