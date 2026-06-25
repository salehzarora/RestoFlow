import 'menu_entity_type.dart';

/// What a successful RF-109 menu write did to the row.
enum MenuWriteAction {
  created('created'),
  updated('updated'),
  softDeleted('soft_deleted');

  const MenuWriteAction(this.wire);

  final String wire;

  static MenuWriteAction? tryFromWire(String value) {
    for (final action in MenuWriteAction.values) {
      if (action.wire == value) return action;
    }
    return null;
  }
}

/// The parsed success envelope of an RF-109 menu write RPC:
/// `{ok:true, entity:'<entity>', id:<uuid>, action:'created'|'updated'|'soft_deleted'}`.
class MenuWriteResult {
  const MenuWriteResult({
    required this.entity,
    required this.id,
    required this.action,
  });

  final MenuEntityType entity;
  final String id;
  final MenuWriteAction action;

  /// Parses the `{ok:true, ...}` body. Throws [FormatException] on a malformed
  /// envelope; the writer maps that to a `MenuInvalidResponseFailure`.
  factory MenuWriteResult.fromOkEnvelope(Map<String, dynamic> json) {
    final entityWire = json['entity'];
    final id = json['id'];
    final actionWire = json['action'];
    if (entityWire is! String) {
      throw const FormatException('menu write result: entity missing');
    }
    if (id is! String || id.isEmpty) {
      throw const FormatException('menu write result: id missing');
    }
    if (actionWire is! String) {
      throw const FormatException('menu write result: action missing');
    }
    final entity = MenuEntityType.tryFromWire(entityWire);
    final action = MenuWriteAction.tryFromWire(actionWire);
    if (entity == null) {
      throw FormatException('menu write result: unknown entity $entityWire');
    }
    if (action == null) {
      throw FormatException('menu write result: unknown action $actionWire');
    }
    return MenuWriteResult(entity: entity, id: id, action: action);
  }
}
