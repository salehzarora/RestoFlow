import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show
        AdminConflict,
        AdminFailure,
        AdminPermissionDenied,
        AdminResult,
        AdminScope,
        AdminTransient,
        AdminValidation;

import 'table_models.dart';

/// The dashboard Tables repository seam (sprint `dining_tables` backend).
/// Reuses the admin failure vocabulary ([AdminFailure]/[AdminResult]) so the
/// shared state views and snackbar mapping work unchanged.
abstract class TablesAdminRepository {
  /// `public.list_tables` — the branch's dining tables (inactive INCLUDED,
  /// tombstones excluded), label-ordered.
  Future<AdminResult<List<DashboardTable>>> load();

  /// `public.upsert_table` — create ([id] null) or update label/seats/area/
  /// active. The operational status is owned by [setStatus], never by upsert.
  Future<AdminResult<void>> upsertTable({
    String? id,
    required String label,
    int? seats,
    String? area,
    required bool isActive,
  });

  /// `public.set_table_status` — flips the operational status
  /// (available | occupied | reserved | out_of_service).
  Future<AdminResult<void>> setStatus(String id, DiningTableStatus status);

  /// `public.soft_delete_table` — tombstones the table (D-020); existing
  /// orders keep their table reference.
  Future<AdminResult<void>> deleteTable(String id);
}

/// A clearly-labelled in-memory demo store (demo mode only; the demo banner is
/// shown by the shell). Mirrors the backend semantics without a backend.
class InMemoryTablesStore implements TablesAdminRepository {
  InMemoryTablesStore()
    : _tables = [
        const DashboardTable(
          id: 'demo-table-1',
          label: 'T1',
          seats: 4,
          area: 'Main hall',
          status: DiningTableStatus.available,
          isActive: true,
          branchId: 'demo-branch',
        ),
        const DashboardTable(
          id: 'demo-table-2',
          label: 'T2',
          seats: 2,
          area: 'Main hall',
          status: DiningTableStatus.occupied,
          isActive: true,
          branchId: 'demo-branch',
        ),
        const DashboardTable(
          id: 'demo-table-3',
          label: 'T3',
          seats: 6,
          area: 'Main hall',
          status: DiningTableStatus.available,
          isActive: true,
          branchId: 'demo-branch',
        ),
        const DashboardTable(
          id: 'demo-table-4',
          label: 'P1',
          seats: 4,
          area: 'Terrace',
          status: DiningTableStatus.available,
          isActive: true,
          branchId: 'demo-branch',
        ),
        const DashboardTable(
          id: 'demo-table-5',
          label: 'P2',
          seats: 4,
          area: 'Terrace',
          status: DiningTableStatus.outOfService,
          isActive: true,
          branchId: 'demo-branch',
        ),
        const DashboardTable(
          id: 'demo-table-6',
          label: 'P3',
          seats: 2,
          area: 'Terrace',
          status: DiningTableStatus.available,
          isActive: false,
          branchId: 'demo-branch',
        ),
      ];

  final List<DashboardTable> _tables;
  int _seq = 0;

  @override
  Future<AdminResult<List<DashboardTable>>> load() async =>
      Success(List.unmodifiable(_tables));

  @override
  Future<AdminResult<void>> upsertTable({
    String? id,
    required String label,
    int? seats,
    String? area,
    required bool isActive,
  }) async {
    final name = label.trim();
    if (name.isEmpty) return const Failure(AdminValidation('label'));
    if (seats != null && seats < 1) {
      return const Failure(AdminValidation('seats'));
    }
    final index = _tables.indexWhere((t) => t.id == id);
    final trimmedArea = area?.trim();
    final table = DashboardTable(
      id: id ?? 'demo-table-new-${++_seq}',
      label: name,
      seats: seats,
      area: (trimmedArea?.isEmpty ?? true) ? null : trimmedArea,
      // Upsert never touches the operational status (setStatus owns it).
      status: index >= 0 ? _tables[index].status : DiningTableStatus.available,
      isActive: isActive,
      branchId: index >= 0 ? _tables[index].branchId : 'demo-branch',
    );
    if (index >= 0) {
      _tables[index] = table;
    } else {
      _tables.add(table);
    }
    return const Success(null);
  }

  @override
  Future<AdminResult<void>> setStatus(
    String id,
    DiningTableStatus status,
  ) async {
    final index = _tables.indexWhere((t) => t.id == id);
    if (index < 0) return const Failure(AdminTransient());
    final t = _tables[index];
    _tables[index] = DashboardTable(
      id: t.id,
      label: t.label,
      seats: t.seats,
      area: t.area,
      status: status,
      isActive: t.isActive,
      branchId: t.branchId,
    );
    return const Success(null);
  }

  @override
  Future<AdminResult<void>> deleteTable(String id) async {
    _tables.removeWhere((t) => t.id == id);
    return const Success(null);
  }
}

/// The real, Supabase-backed [TablesAdminRepository] over the sprint's
/// hardened table RPCs (`list_tables` / `upsert_table` / `set_table_status` /
/// `soft_delete_table`). Authenticated anon-key transport only (DECISION
/// D-011); identity server-derived from `auth.uid()`; scope from the ACTIVE
/// membership. Failures are safe, typed [AdminFailure]s.
class SupabaseTablesRepository implements TablesAdminRepository {
  SupabaseTablesRepository({
    required SyncRpcTransport transport,
    required AdminScope scope,
    required String? Function() currentUserId,
    int Function()? nonce,
  }) : _t = transport,
       _scope = scope,
       _uid = currentUserId,
       _nonce = nonce ?? _microNonce;

  final SyncRpcTransport _t;
  final AdminScope _scope;
  final String? Function() _uid;
  final int Function() _nonce;

  static int _microNonce() => DateTime.now().microsecondsSinceEpoch;

  @override
  Future<AdminResult<List<DashboardTable>>> load() async {
    final Object? raw;
    try {
      raw = await _t.invoke('list_tables', <String, dynamic>{
        'p_organization_id': _scope.organizationId,
        'p_restaurant_id': _scope.restaurantId,
        'p_branch_id': _scope.branchId,
      });
    } on SyncTransportException catch (e) {
      return Failure(_mapTransport(e));
    } catch (_) {
      return const Failure(AdminTransient());
    }
    if (raw is! Map || raw['ok'] != true) return Failure(_mapError(raw));
    return Success([
      for (final row in (raw['tables'] as List?) ?? const [])
        if (row is Map)
          if (_tableFrom(row) case final t?) t,
    ]);
  }

  static DashboardTable? _tableFrom(Map<dynamic, dynamic> row) {
    final status = DiningTableStatus.fromWire(row['status']?.toString());
    if (status == null) return null; // unknown -> skip
    final seats = row['seats'];
    final area = row['area']?.toString();
    // RESTAURANT-OPERATIONS-V1-001: server-derived occupancy; missing/malformed
    // degrades to 0 (display truth, never a gate).
    final activeOrders = row['active_order_count'];
    return DashboardTable(
      id: (row['id'] ?? '').toString(),
      label: (row['label'] ?? '').toString(),
      seats: seats is int ? seats : int.tryParse(seats?.toString() ?? ''),
      area: (area == null || area.isEmpty) ? null : area,
      status: status,
      isActive: row['is_active'] == true,
      branchId: (row['branch_id'] ?? '').toString(),
      activeOrderCount: activeOrders is int && activeOrders > 0
          ? activeOrders
          : 0,
    );
  }

  @override
  Future<AdminResult<void>> upsertTable({
    String? id,
    required String label,
    int? seats,
    String? area,
    required bool isActive,
  }) async {
    final name = label.trim();
    if (name.isEmpty) return const Failure(AdminValidation('label'));
    if (seats != null && seats < 1) {
      return const Failure(AdminValidation('seats'));
    }
    final restaurantId = _scope.restaurantId;
    final branchId = _scope.branchId;
    // dining_tables is branch-scoped (org/restaurant/branch NOT NULL): an
    // org-wide membership must pick a branch scope first (honest validation).
    if (restaurantId == null || branchId == null) {
      return const Failure(AdminValidation('scope'));
    }
    final trimmedArea = area?.trim();
    final Object? raw;
    try {
      raw = await _t.invoke('upsert_table', <String, dynamic>{
        'p_client_request_id': _requestId('upsert', [id ?? '', name]),
        'p_organization_id': _scope.organizationId,
        'p_restaurant_id': restaurantId,
        'p_branch_id': branchId,
        'p_id': id,
        'p_label': name,
        'p_seats': seats,
        'p_area': (trimmedArea?.isEmpty ?? true) ? null : trimmedArea,
        'p_is_active': isActive,
      });
    } on SyncTransportException catch (e) {
      return Failure(_mapTransport(e));
    } catch (_) {
      return const Failure(AdminTransient());
    }
    if (raw is! Map || raw['ok'] != true) return Failure(_mapError(raw));
    return const Success(null);
  }

  @override
  Future<AdminResult<void>> setStatus(
    String id,
    DiningTableStatus status,
  ) async {
    final restaurantId = _scope.restaurantId;
    final branchId = _scope.branchId;
    if (restaurantId == null || branchId == null) {
      return const Failure(AdminValidation('scope'));
    }
    final Object? raw;
    try {
      raw = await _t.invoke('set_table_status', <String, dynamic>{
        'p_client_request_id': _requestId('set-status', [id, status.wire]),
        'p_organization_id': _scope.organizationId,
        'p_table_id': id,
        'p_status': status.wire,
      });
    } on SyncTransportException catch (e) {
      return Failure(_mapTransport(e));
    } catch (_) {
      return const Failure(AdminTransient());
    }
    if (raw is! Map || raw['ok'] != true) return Failure(_mapError(raw));
    return const Success(null);
  }

  @override
  Future<AdminResult<void>> deleteTable(String id) async {
    final restaurantId = _scope.restaurantId;
    final branchId = _scope.branchId;
    if (restaurantId == null || branchId == null) {
      return const Failure(AdminValidation('scope'));
    }
    final Object? raw;
    try {
      raw = await _t.invoke('soft_delete_table', <String, dynamic>{
        'p_client_request_id': _requestId('delete', [id]),
        'p_organization_id': _scope.organizationId,
        'p_table_id': id,
      });
    } on SyncTransportException catch (e) {
      return Failure(_mapTransport(e));
    } catch (_) {
      return const Failure(AdminTransient());
    }
    if (raw is! Map || raw['ok'] != true) return Failure(_mapError(raw));
    return const Success(null);
  }

  AdminFailure _mapError(Object? raw) {
    if (raw is Map && raw['error'] == 'permission_denied') {
      return const AdminPermissionDenied('role_rank');
    }
    if (raw is Map && raw['error'] != null) {
      return AdminConflict(raw['error'].toString());
    }
    return const AdminTransient();
  }

  static AdminFailure _mapTransport(SyncTransportException e) =>
      switch (e.kind) {
        SyncTransportErrorKind.auth => const AdminPermissionDenied('denied'),
        SyncTransportErrorKind.transient => const AdminTransient(),
        SyncTransportErrorKind.server => const AdminTransient(),
        SyncTransportErrorKind.unknown => const AdminTransient(),
      };

  /// RFC-4122-shaped UUID (v5-style) with a per-call nonce — same pattern as
  /// the staff/printers repos. Every press is a distinct operation for the
  /// server's client_request_id idempotency ledger (no stale-replay no-op).
  String _requestId(String op, List<String> parts) {
    final seed = [_uid() ?? '', op, ...parts, _nonce().toString()].join('|');
    final bytes = sha256
        .convert(utf8.encode('mvp:tables:$seed'))
        .bytes
        .sublist(0, 16);
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hx(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hx(0, 4)}-${hx(4, 6)}-${hx(6, 8)}-${hx(8, 10)}-${hx(10, 16)}';
  }
}
