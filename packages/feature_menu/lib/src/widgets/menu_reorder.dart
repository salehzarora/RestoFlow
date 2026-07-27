/// MENU-ORDER-001: drag-and-drop reorder helpers shared by the menu lists.
///
/// [menuReorderedIds] computes the new id sequence after a `ReorderableListView`
/// drag using the classic `onReorder(oldIndex, newIndex)` convention, where
/// `newIndex` is in the PRE-removal coordinate space (so it is decremented when
/// an item moves down). Kept pure + separate so the index math is unit-tested
/// independently of the widget layer.
List<String> menuReorderedIds(List<String> ids, int oldIndex, int newIndex) {
  if (oldIndex < 0 || oldIndex >= ids.length) return List<String>.of(ids);
  final result = List<String>.of(ids);
  var target = newIndex;
  if (target > oldIndex) target -= 1;
  if (target < 0) target = 0;
  if (target > result.length - 1) target = result.length - 1;
  final moved = result.removeAt(oldIndex);
  result.insert(target, moved);
  return result;
}
