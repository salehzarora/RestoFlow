/// MENU-CATEGORY-ICON-PICKER-OPS-044 — what a category write should do to the
/// stored icon key.
///
/// `menu_upsert_category` is a FULL-STATE upsert, so "the caller sent nothing"
/// and "the caller wants no icon" must not look alike on the wire. The server
/// (migration `20260820090000`) therefore reads three distinct instructions
/// from one text argument:
///
/// | intent   | `p_icon_key` | effect                       |
/// |----------|--------------|------------------------------|
/// | preserve | `null`       | the stored key is left alone |
/// | reset    | `''`         | the stored key becomes NULL  |
/// | set      | a key        | the stored key becomes that  |
///
/// A plain `String?` can encode that, but only by convention — and the one
/// convention that matters here ("null means keep, not clear") is the exact
/// opposite of every other optional field on this seam, where null clears. One
/// caller reading it the ordinary way silently wipes an owner's chosen icon on
/// an unrelated rename. This type makes the instruction explicit and
/// unmissable at every call site instead.
library;

/// The three instructions the server distinguishes.
enum MenuIconKeyWriteKind {
  /// Leave whatever is stored exactly as it is.
  ///
  /// This is what an edit that never touched the icon field must send — and it
  /// is also how a key this build does not recognise survives: it is never
  /// re-sent, so it cannot be mangled by a binary that cannot draw it.
  preserve,

  /// Clear the stored key: back to "no explicit icon".
  reset,

  /// Store this key.
  set,
}

/// An instruction for the `icon_key` column. See the library doc.
class MenuIconKeyWrite {
  /// Leave the stored key untouched.
  const MenuIconKeyWrite.preserve()
    : kind = MenuIconKeyWriteKind.preserve,
      key = null;

  /// Clear the stored key.
  const MenuIconKeyWrite.reset()
    : kind = MenuIconKeyWriteKind.reset,
      key = null;

  /// Store [key].
  const MenuIconKeyWrite.set(String this.key) : kind = MenuIconKeyWriteKind.set;

  /// Derives the instruction a form should send from what the owner has
  /// selected against what was loaded.
  ///
  /// The comparison is the whole safety story:
  ///  * unchanged → [MenuIconKeyWriteKind.preserve], so an unrelated rename
  ///    cannot disturb the icon AND an unrecognised key is never re-sent;
  ///  * cleared → [MenuIconKeyWriteKind.reset];
  ///  * changed → [MenuIconKeyWriteKind.set].
  ///
  /// On create [original] is null, so "Automatic" naturally sends preserve and
  /// the row is inserted with no key.
  factory MenuIconKeyWrite.fromSelection({
    required String? selected,
    required String? original,
  }) {
    if (selected == original) return const MenuIconKeyWrite.preserve();
    if (selected == null) return const MenuIconKeyWrite.reset();
    return MenuIconKeyWrite.set(selected);
  }

  final MenuIconKeyWriteKind kind;

  /// The key to store; non-null only for [MenuIconKeyWriteKind.set].
  final String? key;

  /// The value for the RPC's `p_icon_key` argument.
  ///
  /// `null` = preserve, `''` = reset, otherwise the key.
  String? get wireValue => switch (kind) {
    MenuIconKeyWriteKind.preserve => null,
    MenuIconKeyWriteKind.reset => '',
    MenuIconKeyWriteKind.set => key,
  };

  /// Applies this instruction to a locally held value — the in-memory store's
  /// mirror of what the server would do.
  String? applyTo(String? stored) => switch (kind) {
    MenuIconKeyWriteKind.preserve => stored,
    MenuIconKeyWriteKind.reset => null,
    MenuIconKeyWriteKind.set => key,
  };

  @override
  bool operator ==(Object other) =>
      other is MenuIconKeyWrite && other.kind == kind && other.key == key;

  @override
  int get hashCode => Object.hash(kind, key);

  @override
  String toString() =>
      kind == MenuIconKeyWriteKind.set ? 'iconKey.set($key)' : 'iconKey.$kind';
}
