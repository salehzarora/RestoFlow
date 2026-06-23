import 'invalidation_hint.dart';

/// The injected realtime SCOPE seam for KDS hints (RF-058, approved decision A3).
///
/// Supplied from outside (a future auth/session/bootstrap) — RF-058 builds no
/// login/pairing/PIN flow. When scope is absent the app uses a disabled source
/// and KDS stays polling-only.
class RealtimeScope {
  const RealtimeScope({required this.organizationId, required this.branchId});

  final String organizationId;
  final String branchId;

  /// The per-branch private broadcast topic (approved decision A2).
  String get branchTopic => 'kds:branch:$branchId';

  @override
  bool operator ==(Object other) =>
      other is RealtimeScope &&
      other.organizationId == organizationId &&
      other.branchId == branchId;

  @override
  int get hashCode => Object.hash(organizationId, branchId);
}

/// A source of KDS invalidation hints (RF-058).
///
/// Abstracted so the sync bridge can be unit-tested with a fake (no live
/// Supabase). Implementations carry NO data and apply nothing — they only
/// surface hints; the bridge reacts by calling the coordinator's `refresh()`.
abstract class InvalidationSource {
  /// A broadcast stream of parsed hints (drops/errors are handled internally;
  /// polling remains the source of truth regardless).
  Stream<InvalidationHint> get hints;

  /// Begin listening (idempotent). A no-op for a disabled source.
  Future<void> start();

  /// Stop listening and release resources.
  Future<void> dispose();
}

/// A source that emits nothing (RF-058): used when no realtime scope is injected
/// so the KDS runs polling-only without any special-casing in the bridge.
class DisabledInvalidationSource implements InvalidationSource {
  const DisabledInvalidationSource();

  @override
  Stream<InvalidationHint> get hints => const Stream<InvalidationHint>.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {}
}
