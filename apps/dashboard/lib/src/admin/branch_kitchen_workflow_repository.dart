import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// DASHBOARD-PRINTER-ONLY-MODE-TOGGLE-010 — the branch's kitchen workflow.
///
/// The wire values are the branch column's own CHECK value space
/// (`branches.kitchen_workflow_mode`); nothing else is accepted by the server.
enum KitchenWorkflowMode {
  /// A separate KDS screen drives the kitchen lifecycle (the platform default).
  kds('kds'),

  /// No KDS: the POS prints kitchen tickets and may finish confirmed rounds.
  printerOnly('printer_only');

  const KitchenWorkflowMode(this.wire);

  final String wire;

  /// Parses the server's token. Returns null for anything unrecognised — the
  /// caller then shows an honest "couldn't read" state rather than guessing a
  /// mode, because guessing `kds` would hide a real printer_only branch and
  /// guessing `printer_only` would misdescribe a KDS one.
  static KitchenWorkflowMode? fromWire(Object? value) {
    for (final m in KitchenWorkflowMode.values) {
      if (m.wire == value) return m;
    }
    return null;
  }
}

/// The outcome of a workflow-mode write, mapped 1:1 from the RPC's typed
/// envelope so the UI can say something true about each case.
enum KitchenWorkflowWrite {
  /// Applied (or already at the requested value — the RPC is idempotent).
  ok,

  /// `permission_denied` — an active membership exists but its rank is below
  /// restaurant_owner. The server is authoritative; the UI gate is advisory.
  denied,

  /// `not_found` — no membership covers this branch, or it does not exist.
  /// Deliberately indistinguishable from "wrong tenant" (no scope leak).
  notFound,

  /// `invalid_mode` — unreachable from this UI (it only ever sends the two
  /// enum values) but mapped rather than swallowed.
  invalidMode,

  /// Transport/session failure, or any envelope this client does not recognise.
  /// NOTHING was changed; the caller keeps the value it was already showing.
  unavailable,
}

/// The authoritative result of a write: the status plus what the SERVER says the
/// branch's mode now is. The UI adopts [mode] rather than the value it
/// requested, so the control can never claim a change the server did not make.
class KitchenWorkflowWriteResult {
  const KitchenWorkflowWriteResult(this.status, {this.mode, this.revision});

  final KitchenWorkflowWrite status;

  /// The stored mode as reported by the server on success; null otherwise.
  final KitchenWorkflowMode? mode;

  /// `kitchen_workflow_mode_revision` after the write (monotonic; bumped only on
  /// a real change). Surfaced for diagnostics — this RPC takes no expected
  /// revision, it serialises with a row lock instead.
  final int? revision;
}

/// Reads + writes ONE branch's `kitchen_workflow_mode` over the authenticated
/// dashboard transport, pre-scoped to a single (org, restaurant, branch).
///
/// The server derives the actor from the JWT and enforces the owner gate; this
/// seam never sends an identity, never sends an organization override, and
/// never touches `public.branches` directly (D-011). Faked in widget tests.
abstract interface class BranchKitchenWorkflowRepository {
  /// The branch's CURRENT stored mode, or null when it cannot be read
  /// (fail-soft: the caller shows an honest unavailable state, never a
  /// fabricated default).
  Future<KitchenWorkflowMode?> read();

  /// Sets the mode through the guarded owner RPC.
  Future<KitchenWorkflowWriteResult> setMode(KitchenWorkflowMode mode);
}

/// The real implementation over `public.get_branch_kitchen_workflow_mode` and
/// the guarded `public.set_kitchen_workflow_mode` added by migration
/// 20260807090000. Both are `authenticated`-only; neither is reachable by anon.
class SupabaseBranchKitchenWorkflowRepository
    implements BranchKitchenWorkflowRepository {
  SupabaseBranchKitchenWorkflowRepository({
    required SyncRpcTransport transport,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
  }) : _t = transport;

  final SyncRpcTransport _t;
  final String organizationId;
  final String restaurantId;
  final String branchId;

  Map<String, dynamic> get _scope => <String, dynamic>{
    'p_organization_id': organizationId,
    'p_restaurant_id': restaurantId,
    'p_branch_id': branchId,
  };

  @override
  Future<KitchenWorkflowMode?> read() async {
    final Object? raw;
    try {
      raw = await _t.invoke('get_branch_kitchen_workflow_mode', _scope);
    } catch (_) {
      return null;
    }
    if (raw is! Map || raw['ok'] != true) return null;
    return KitchenWorkflowMode.fromWire(raw['kitchen_workflow_mode']);
  }

  @override
  Future<KitchenWorkflowWriteResult> setMode(KitchenWorkflowMode mode) async {
    final Object? raw;
    try {
      raw = await _t.invoke('set_kitchen_workflow_mode', <String, dynamic>{
        ..._scope,
        'p_mode': mode.wire,
      });
    } catch (_) {
      // Includes the 42501 the RPC raises for an unauthenticated caller.
      return const KitchenWorkflowWriteResult(KitchenWorkflowWrite.unavailable);
    }
    if (raw is! Map) {
      return const KitchenWorkflowWriteResult(KitchenWorkflowWrite.unavailable);
    }
    if (raw['ok'] == true) {
      // The SERVER's stored value, not the requested one. A success envelope
      // that does not carry a readable mode is treated as unavailable: the write
      // may well have landed, but this client will not claim a value it cannot
      // read back, and the caller re-reads authoritatively anyway.
      final stored = KitchenWorkflowMode.fromWire(raw['kitchen_workflow_mode']);
      if (stored == null) {
        return const KitchenWorkflowWriteResult(
          KitchenWorkflowWrite.unavailable,
        );
      }
      final rev = raw['kitchen_workflow_mode_revision'];
      return KitchenWorkflowWriteResult(
        KitchenWorkflowWrite.ok,
        mode: stored,
        revision: rev is int ? rev : null,
      );
    }
    return switch (raw['error']) {
      'permission_denied' => const KitchenWorkflowWriteResult(
        KitchenWorkflowWrite.denied,
      ),
      'not_found' => const KitchenWorkflowWriteResult(
        KitchenWorkflowWrite.notFound,
      ),
      'invalid_mode' => const KitchenWorkflowWriteResult(
        KitchenWorkflowWrite.invalidMode,
      ),
      // Any error this client does not know (a newer server, a future
      // concurrency refusal) is UNAVAILABLE: nothing is assumed to have changed
      // and the caller keeps showing the value it already had.
      _ => const KitchenWorkflowWriteResult(KitchenWorkflowWrite.unavailable),
    };
  }
}
