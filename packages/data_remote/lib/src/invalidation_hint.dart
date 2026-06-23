/// A minimal KDS realtime invalidation HINT (RF-058).
///
/// Realtime is an enhancement only (DECISION D-010): a hint never carries row
/// data and never carries money — it only nudges the client to call `sync_pull`
/// (the source of truth). This model holds ONLY the allowed fields; the parser
/// reads nothing else, so a payload that (wrongly) contained money/raw/customer
/// fields could never be exposed through this type.
class InvalidationHint {
  const InvalidationHint({
    required this.organizationId,
    required this.branchId,
    required this.entity,
    required this.entityId,
    this.revision,
    this.updatedAt,
    this.serverTs,
  });

  /// Tenant scope (opaque ids).
  final String organizationId;
  final String branchId;

  /// The changed entity type — one of [allowedEntities].
  final String entity;

  /// The changed entity's id (opaque; not a row, not money).
  final String entityId;

  /// Server revision where the entity has one (`orders`); null otherwise.
  final int? revision;

  /// The entity's server `updated_at` (raw ISO), advisory only.
  final String? updatedAt;

  /// The server clock when the hint was emitted (raw ISO), advisory only.
  final String? serverTs;

  /// The only entity types a KDS hint may reference.
  static const Set<String> allowedEntities = {
    'orders',
    'order_items',
    'order_item_modifiers',
  };

  /// Parse a broadcast payload into a hint, reading ONLY the allowed keys.
  ///
  /// Returns null (ignored safely) when required fields are missing/mistyped or
  /// the entity is not allow-listed. Any extra keys in [json] — including money
  /// or raw-row fields that must never be present — are NEVER read and so can
  /// never surface on the model.
  static InvalidationHint? tryParse(Map<String, dynamic> json) {
    final org = json['organization_id'];
    final branch = json['branch_id'];
    final entity = json['entity'];
    final entityId = json['entity_id'];
    if (org is! String ||
        branch is! String ||
        entity is! String ||
        entityId is! String) {
      return null;
    }
    if (!allowedEntities.contains(entity)) return null;

    final rawRev = json['revision'];
    final updatedAt = json['updated_at'];
    final serverTs = json['server_ts'];
    return InvalidationHint(
      organizationId: org,
      branchId: branch,
      entity: entity,
      entityId: entityId,
      revision: rawRev is int
          ? rawRev
          : (rawRev is num ? rawRev.toInt() : null),
      updatedAt: updatedAt is String ? updatedAt : null,
      serverTs: serverTs is String ? serverTs : null,
    );
  }

  @override
  String toString() =>
      'InvalidationHint($entity/$entityId @ branch $branchId, rev=$revision)';
}
