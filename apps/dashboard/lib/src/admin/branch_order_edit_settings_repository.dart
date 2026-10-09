import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'branch_kitchen_workflow_repository.dart' show KitchenWorkflowMode;

/// ORDER-EDIT-001G — one branch's two order-editing switches (API_CONTRACT
/// §4.45.8, §4.47a) as the SERVER has them.
class OrderEditSettings {
  const OrderEditSettings({
    required this.enabled,
    required this.finishedFoodManagerOnly,
    this.kitchenMode,
  });

  /// `branches.order_edit_enabled`: cashiers may edit sent, unpaid orders.
  final bool enabled;

  /// `branches.order_edit_finished_food_manager_only`.
  final bool finishedFoodManagerOnly;

  /// The branch's kitchen workflow as the reader reported it, or null when not
  /// read (a write echo carries no mode). Used only as a fallback for the
  /// printer-only note; the Settings screen's own workflow card is the primary
  /// source.
  final KitchenWorkflowMode? kitchenMode;
}

/// The outcome of a read or a write, mapped 1:1 from the RPCs' typed envelopes.
enum OrderEditSettingsStatus {
  /// Read, or applied (the setter is idempotent per request key).
  ok,

  /// `permission_denied` — a covering membership below restaurant_owner. The
  /// server is authoritative; the UI lock is advisory.
  denied,

  /// `not_found` — no membership covers the branch, or it does not exist.
  /// Deliberately indistinguishable from "another tenant's branch" (R-003).
  notFound,

  /// A transport/session failure (including the setter's 42501 raises), a
  /// missing reader on an older database, or any envelope this client does not
  /// recognise. NOTHING is assumed to have changed.
  unavailable,
}

/// A read or write result: the status plus, on [OrderEditSettingsStatus.ok],
/// what the SERVER says the switches now are. The UI adopts [settings], never
/// the value it requested.
class OrderEditSettingsResult {
  const OrderEditSettingsResult(this.status, {this.settings});

  final OrderEditSettingsStatus status;
  final OrderEditSettings? settings;
}

/// Reads and writes ONE branch's order-editing switches over the authenticated
/// Dashboard transport, pre-scoped to a single (org, restaurant, branch).
///
/// The server derives the actor from the JWT and enforces the owner gate; this
/// seam never sends an identity and never touches `public.branches` directly
/// (D-011). Faked in widget tests.
abstract interface class BranchOrderEditSettingsRepository {
  /// The branch's current switches (`get_branch_order_edit_settings`).
  Future<OrderEditSettingsResult> read();

  /// Writes BOTH switches through the guarded owner RPC
  /// (`set_branch_order_edit_settings`); the caller sends the toggled value
  /// plus the other switch's current server value.
  Future<OrderEditSettingsResult> write({
    required bool enabled,
    required bool finishedFoodManagerOnly,
  });
}

/// The real implementation over `public.get_branch_order_edit_settings`
/// (ORDER-EDIT-001G) and `public.set_branch_order_edit_settings`
/// (ORDER-EDIT-001A). Both are `authenticated`-only.
class SupabaseBranchOrderEditSettingsRepository
    implements BranchOrderEditSettingsRepository {
  SupabaseBranchOrderEditSettingsRepository({
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

  Map<String, dynamic> get _scope => <String, dynamic>{
    'p_organization_id': organizationId,
    'p_restaurant_id': restaurantId,
    'p_branch_id': branchId,
  };

  @override
  Future<OrderEditSettingsResult> read() async {
    final Object? raw;
    try {
      raw = await _t.invoke('get_branch_order_edit_settings', _scope);
    } catch (_) {
      return const OrderEditSettingsResult(OrderEditSettingsStatus.unavailable);
    }
    return _map(raw, readsMode: true);
  }

  @override
  Future<OrderEditSettingsResult> write({
    required bool enabled,
    required bool finishedFoodManagerOnly,
  }) async {
    final Object? raw;
    try {
      raw = await _t.invoke('set_branch_order_edit_settings', <String, dynamic>{
        'p_client_request_id': _requestId(enabled, finishedFoodManagerOnly),
        ..._scope,
        'p_order_edit_enabled': enabled,
        'p_finished_food_manager_only': finishedFoodManagerOnly,
      });
    } catch (_) {
      // Includes the 42501 the setter raises for an unauthenticated caller or
      // a branch it cannot see.
      return const OrderEditSettingsResult(OrderEditSettingsStatus.unavailable);
    }
    return _map(raw, readsMode: false);
  }

  static OrderEditSettingsResult _map(Object? raw, {required bool readsMode}) {
    if (raw is! Map) {
      return const OrderEditSettingsResult(OrderEditSettingsStatus.unavailable);
    }
    if (raw['ok'] == true) {
      final enabled = raw['order_edit_enabled'];
      final finished = raw['order_edit_finished_food_manager_only'];
      // A success envelope without readable switches is not adopted: the
      // write may well have landed, but this client will not claim a value it
      // cannot read back, and the caller re-reads anyway.
      if (enabled is! bool || finished is! bool) {
        return const OrderEditSettingsResult(
          OrderEditSettingsStatus.unavailable,
        );
      }
      return OrderEditSettingsResult(
        OrderEditSettingsStatus.ok,
        settings: OrderEditSettings(
          enabled: enabled,
          finishedFoodManagerOnly: finished,
          kitchenMode: readsMode
              ? KitchenWorkflowMode.fromWire(raw['kitchen_workflow_mode'])
              : null,
        ),
      );
    }
    return switch (raw['error']) {
      'permission_denied' => const OrderEditSettingsResult(
        OrderEditSettingsStatus.denied,
      ),
      'not_found' => const OrderEditSettingsResult(
        OrderEditSettingsStatus.notFound,
      ),
      _ => const OrderEditSettingsResult(OrderEditSettingsStatus.unavailable),
    };
  }

  /// A fresh v5-style idempotency key per deliberate toggle press: the server
  /// ledger keys retries, and a per-press nonce makes each press its own
  /// request (the RF-113 pattern).
  String _requestId(bool enabled, bool finishedFoodManagerOnly) {
    final seed = [
      branchId,
      enabled.toString(),
      finishedFoodManagerOnly.toString(),
      _nonce().toString(),
    ].join('|');
    final bytes = sha256
        .convert(utf8.encode('order-edit-001g:settings:$seed'))
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
