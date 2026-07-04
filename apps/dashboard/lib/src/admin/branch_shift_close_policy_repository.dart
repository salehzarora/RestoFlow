import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// The outcome of writing the branch shift-close policy.
enum BranchPolicyWrite {
  /// The owner's change was applied.
  ok,

  /// The caller's role may not change branch settings (rank < restaurant_owner).
  denied,

  /// A transport/session/validation failure — nothing changed; show an honest
  /// error and keep the displayed value.
  unavailable,
}

/// Reads + writes ONE branch's `pos_shift_close_enabled` policy (RF-113) over the
/// authenticated dashboard transport. Pre-scoped to a single (org, restaurant,
/// branch); the server derives the actor from `auth.uid()` and enforces the
/// owner gate — this seam never sends identity or a service-role key (D-011).
/// Faked in widget tests.
abstract interface class BranchShiftClosePolicyRepository {
  /// The current policy, or null when it cannot be read (fail-soft — the caller
  /// then shows an honest unavailable state, never a fabricated default).
  Future<bool?> read();

  /// Sets the policy; the result distinguishes applied / role-denied / failed.
  Future<BranchPolicyWrite> setEnabled(bool enabled);
}

/// The real, Supabase-backed implementation over `public.get_branch_pos_shift_close_enabled`
/// and `public.set_branch_pos_shift_close_enabled`.
class SupabaseBranchShiftClosePolicyRepository
    implements BranchShiftClosePolicyRepository {
  SupabaseBranchShiftClosePolicyRepository({
    required SyncRpcTransport transport,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    int Function()? nonce,
  }) : _t = transport,
       _nonce = nonce ?? _microNonce;

  final SyncRpcTransport _t;
  final String organizationId;
  final String restaurantId;
  final String branchId;
  final int Function() _nonce;

  static int _microNonce() => DateTime.now().microsecondsSinceEpoch;

  @override
  Future<bool?> read() async {
    final Object? raw;
    try {
      raw = await _t
          .invoke('get_branch_pos_shift_close_enabled', <String, dynamic>{
            'p_organization_id': organizationId,
            'p_restaurant_id': restaurantId,
            'p_branch_id': branchId,
          });
    } catch (_) {
      return null;
    }
    if (raw is! Map || raw['ok'] != true) return null;
    return raw['pos_shift_close_enabled'] == true;
  }

  @override
  Future<BranchPolicyWrite> setEnabled(bool enabled) async {
    final Object? raw;
    try {
      raw = await _t
          .invoke('set_branch_pos_shift_close_enabled', <String, dynamic>{
            'p_client_request_id': _requestId(enabled),
            'p_organization_id': organizationId,
            'p_restaurant_id': restaurantId,
            'p_branch_id': branchId,
            'p_enabled': enabled,
          });
    } catch (_) {
      return BranchPolicyWrite.unavailable;
    }
    if (raw is! Map) return BranchPolicyWrite.unavailable;
    if (raw['ok'] == true) return BranchPolicyWrite.ok;
    return raw['error'] == 'permission_denied'
        ? BranchPolicyWrite.denied
        : BranchPolicyWrite.unavailable;
  }

  /// A fresh v5-style idempotency key per deliberate toggle press (the server
  /// ledger keys retries; a per-press nonce makes each press its own request,
  /// mirroring the device create/issue pattern).
  String _requestId(bool enabled) {
    final seed = [branchId, enabled.toString(), _nonce().toString()].join('|');
    final bytes = sha256
        .convert(utf8.encode('rf113:shift-close:$seed'))
        .bytes
        .sublist(0, 16);
    bytes[6] = (bytes[6] & 0x0f) | 0x50; // version 5 (name-based)
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC-4122 variant
    String hx(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hx(0, 4)}-${hx(4, 6)}-${hx(6, 8)}-${hx(8, 10)}-${hx(10, 16)}';
  }
}
