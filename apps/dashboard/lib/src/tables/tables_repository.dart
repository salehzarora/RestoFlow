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
  /// tombstones excluded), label-ordered, PLUS the TABLE-FLOOR-LAYOUT-021
  /// section catalog (empty sections included, display-ordered).
  Future<AdminResult<TablesFloorSnapshot>> load();

  /// `public.upsert_table` — create ([id] null) or update label/seats/area/
  /// active. The operational status is owned by [setStatus], never by upsert;
  /// the section/placement are owned by [setTableSection]/[setTablePosition]
  /// (deliberately OUTSIDE this full-replace call so a stale client can never
  /// erase layout).
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

  /// TABLE-FLOOR-LAYOUT-021 — `public.upsert_table_section`: create ([id]
  /// null; appends after the live siblings) or rename/toggle a section.
  Future<AdminResult<void>> upsertSection({
    String? id,
    required String name,
    required bool isActive,
  });

  /// `public.soft_delete_table_section` — tombstones the section AND detaches
  /// its tables (section + placement cleared; tables are NEVER deleted).
  Future<AdminResult<void>> deleteSection(String id);

  /// `public.set_table_section` — assign ([sectionId] non-null) or clear.
  /// Any section change clears the placement (a position belongs to one
  /// canvas).
  Future<AdminResult<void>> setTableSection(String tableId, String? sectionId);

  /// `public.set_table_layout_position` — place the table at NORMALIZED
  /// integer coordinates (0..10000 each) inside its section canvas.
  Future<AdminResult<void>> setTablePosition(
    String tableId,
    int layoutX,
    int layoutY,
  );

  /// `public.reorder_table_sections` — the COMPLETE live section id list in
  /// the owner's new order.
  Future<AdminResult<void>> reorderSections(List<String> ids);

  /// TABLE-FLOOR-MAP-POLISH-027 — `public.upsert_floor_element`: create or
  /// edit a VISUAL-ONLY fixture. An EMPTY [DashboardFloorElement.id] creates
  /// (the store mints the id); a known id updates. kind + section are
  /// immutable server contract — an edit only moves/resizes/rotates/relabels.
  Future<AdminResult<void>> upsertFloorElement(DashboardFloorElement element);

  /// `public.delete_floor_element` — tombstones the fixture.
  Future<AdminResult<void>> deleteFloorElement(String id);
}

/// A clearly-labelled in-memory demo store (demo mode only; the demo banner is
/// shown by the shell). Mirrors the backend semantics without a backend —
/// TABLE-FLOOR-LAYOUT-021 seeds two REAL sections with placed tables so the
/// demo floor editor renders a meaningful map out of the box.
class InMemoryTablesStore implements TablesAdminRepository {
  InMemoryTablesStore()
    : _sections = [
        const DashboardTableSection(
          id: 'demo-section-1',
          name: 'Main hall',
          displayOrder: 0,
          isActive: true,
          branchId: 'demo-branch',
        ),
        const DashboardTableSection(
          id: 'demo-section-2',
          name: 'Terrace',
          displayOrder: 1,
          isActive: true,
          branchId: 'demo-branch',
        ),
      ],
      _tables = [
        const DashboardTable(
          id: 'demo-table-1',
          label: 'T1',
          seats: 4,
          area: 'Main hall',
          status: DiningTableStatus.available,
          isActive: true,
          branchId: 'demo-branch',
          sectionId: 'demo-section-1',
          sectionName: 'Main hall',
          sectionDisplayOrder: 0,
          layoutX: 1500,
          layoutY: 2500,
        ),
        const DashboardTable(
          id: 'demo-table-2',
          label: 'T2',
          seats: 2,
          area: 'Main hall',
          status: DiningTableStatus.occupied,
          isActive: true,
          branchId: 'demo-branch',
          sectionId: 'demo-section-1',
          sectionName: 'Main hall',
          sectionDisplayOrder: 0,
          layoutX: 5000,
          layoutY: 2500,
        ),
        const DashboardTable(
          id: 'demo-table-3',
          label: 'T3',
          seats: 6,
          area: 'Main hall',
          status: DiningTableStatus.available,
          isActive: true,
          branchId: 'demo-branch',
          sectionId: 'demo-section-1',
          sectionName: 'Main hall',
          sectionDisplayOrder: 0,
          layoutX: 8200,
          layoutY: 6500,
        ),
        const DashboardTable(
          id: 'demo-table-4',
          label: 'P1',
          seats: 4,
          area: 'Terrace',
          status: DiningTableStatus.available,
          isActive: true,
          branchId: 'demo-branch',
          sectionId: 'demo-section-2',
          sectionName: 'Terrace',
          sectionDisplayOrder: 1,
          layoutX: 2200,
          layoutY: 3200,
        ),
        const DashboardTable(
          id: 'demo-table-5',
          label: 'P2',
          seats: 4,
          area: 'Terrace',
          status: DiningTableStatus.outOfService,
          isActive: true,
          branchId: 'demo-branch',
          sectionId: 'demo-section-2',
          sectionName: 'Terrace',
          sectionDisplayOrder: 1,
          layoutX: 6800,
          layoutY: 6200,
        ),
        // P3 is deliberately UNASSIGNED: the legacy/unassigned fallback zone
        // must always be demonstrable.
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

  final List<DashboardTableSection> _sections;
  final List<DashboardTable> _tables;
  // TABLE-FLOOR-MAP-POLISH-027: demo fixtures so the element layer renders a
  // meaningful floor out of the box (a wall + a labelled cashier stand).
  final List<DashboardFloorElement> _elements = [
    const DashboardFloorElement(
      id: 'demo-element-1',
      sectionId: 'demo-section-1',
      kind: 'wall',
      layoutX: 0,
      layoutY: 0,
      widthNorm: 3000,
      heightNorm: 150,
    ),
    const DashboardFloorElement(
      id: 'demo-element-2',
      sectionId: 'demo-section-1',
      kind: 'cashier',
      layoutX: 9500,
      layoutY: 9500,
      widthNorm: 900,
      heightNorm: 900,
      label: 'POS',
    ),
  ];
  int _seq = 0;

  @override
  Future<AdminResult<TablesFloorSnapshot>> load() async => Success(
    TablesFloorSnapshot(
      tables: List.unmodifiable(_tables),
      sections: List.unmodifiable(
        [..._sections]
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder)),
      ),
      floorElements: List.unmodifiable(_elements),
    ),
  );

  @override
  Future<AdminResult<void>> upsertFloorElement(
    DashboardFloorElement element,
  ) async {
    if (element.layoutX < 0 ||
        element.layoutX > 10000 ||
        element.layoutY < 0 ||
        element.layoutY > 10000) {
      return const Failure(AdminValidation('position'));
    }
    final trimmed = element.label?.trim();
    final normalized = DashboardFloorElement(
      id: element.id.isEmpty ? 'demo-element-new-${++_seq}' : element.id,
      sectionId: element.sectionId,
      kind: element.kind,
      layoutX: element.layoutX,
      layoutY: element.layoutY,
      widthNorm: element.widthNorm,
      heightNorm: element.heightNorm,
      orientationQuarterTurns: element.orientationQuarterTurns,
      label: (trimmed?.isEmpty ?? true) ? null : trimmed,
    );
    final index = element.id.isEmpty
        ? -1
        : _elements.indexWhere((e) => e.id == element.id);
    if (index >= 0) {
      _elements[index] = normalized;
    } else {
      _elements.add(normalized);
    }
    return const Success(null);
  }

  @override
  Future<AdminResult<void>> deleteFloorElement(String id) async {
    _elements.removeWhere((e) => e.id == id);
    return const Success(null);
  }

  @override
  Future<AdminResult<void>> upsertSection({
    String? id,
    required String name,
    required bool isActive,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const Failure(AdminValidation('name'));
    final duplicate = _sections.any(
      (s) => s.id != id && s.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (duplicate) return const Failure(AdminConflict('duplicate_name'));
    final index = _sections.indexWhere((s) => s.id == id);
    if (index >= 0) {
      _sections[index] = DashboardTableSection(
        id: _sections[index].id,
        name: trimmed,
        displayOrder: _sections[index].displayOrder,
        isActive: isActive,
        branchId: _sections[index].branchId,
      );
      // Keep the denormalized section name on assigned tables honest.
      for (var i = 0; i < _tables.length; i++) {
        if (_tables[i].sectionId == id) {
          _tables[i] = _tables[i].copyWithPlacement(
            sectionId: id,
            sectionName: trimmed,
            sectionDisplayOrder: _tables[i].sectionDisplayOrder,
            layoutX: _tables[i].layoutX,
            layoutY: _tables[i].layoutY,
          );
        }
      }
    } else {
      final next = _sections.isEmpty
          ? 0
          : _sections
                    .map((s) => s.displayOrder)
                    .reduce((a, b) => a > b ? a : b) +
                1;
      _sections.add(
        DashboardTableSection(
          id: id ?? 'demo-section-new-${++_seq}',
          name: trimmed,
          displayOrder: next,
          isActive: isActive,
          branchId: 'demo-branch',
        ),
      );
    }
    return const Success(null);
  }

  @override
  Future<AdminResult<void>> deleteSection(String id) async {
    _sections.removeWhere((s) => s.id == id);
    // 027: fixtures are section-owned — they go with the section (the backend
    // tombstones them the same way).
    _elements.removeWhere((e) => e.sectionId == id);
    // DETACH, never delete: the backend clears section + placement.
    for (var i = 0; i < _tables.length; i++) {
      if (_tables[i].sectionId == id) {
        _tables[i] = _tables[i].copyWithPlacement();
      }
    }
    return const Success(null);
  }

  @override
  Future<AdminResult<void>> setTableSection(
    String tableId,
    String? sectionId,
  ) async {
    final index = _tables.indexWhere((t) => t.id == tableId);
    if (index < 0) return const Failure(AdminTransient());
    if (sectionId == null) {
      _tables[index] = _tables[index].copyWithPlacement();
      return const Success(null);
    }
    DashboardTableSection? section;
    for (final s in _sections) {
      if (s.id == sectionId) {
        section = s;
        break;
      }
    }
    if (section == null) return const Failure(AdminTransient());
    // A section change clears the placement (one canvas, one position).
    _tables[index] = _tables[index].copyWithPlacement(
      sectionId: section.id,
      sectionName: section.name,
      sectionDisplayOrder: section.displayOrder,
    );
    return const Success(null);
  }

  @override
  Future<AdminResult<void>> setTablePosition(
    String tableId,
    int layoutX,
    int layoutY,
  ) async {
    final index = _tables.indexWhere((t) => t.id == tableId);
    if (index < 0) return const Failure(AdminTransient());
    final t = _tables[index];
    if (t.sectionId == null) return const Failure(AdminValidation('section'));
    if (layoutX < 0 || layoutX > 10000 || layoutY < 0 || layoutY > 10000) {
      return const Failure(AdminValidation('position'));
    }
    _tables[index] = t.copyWithPlacement(
      sectionId: t.sectionId,
      sectionName: t.sectionName,
      sectionDisplayOrder: t.sectionDisplayOrder,
      layoutX: layoutX,
      layoutY: layoutY,
    );
    return const Success(null);
  }

  @override
  Future<AdminResult<void>> reorderSections(List<String> ids) async {
    for (var i = 0; i < ids.length; i++) {
      final index = _sections.indexWhere((s) => s.id == ids[i]);
      if (index < 0) return const Failure(AdminTransient());
      _sections[index] = DashboardTableSection(
        id: _sections[index].id,
        name: _sections[index].name,
        displayOrder: i,
        isActive: _sections[index].isActive,
        branchId: _sections[index].branchId,
      );
    }
    return const Success(null);
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
  Future<AdminResult<TablesFloorSnapshot>> load() async {
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
    return Success(
      TablesFloorSnapshot(
        tables: [
          for (final row in (raw['tables'] as List?) ?? const [])
            if (row is Map)
              if (_tableFrom(row) case final t?) t,
        ],
        // TABLE-FLOOR-LAYOUT-021: the section catalog envelope (absent on an
        // older backend -> empty list; the floor editor simply shows no
        // canvases and everything stays in the classic grid).
        sections: [
          for (final row in (raw['sections'] as List?) ?? const [])
            if (row is Map)
              if (_sectionFrom(row) case final s?) s,
        ],
        // TABLE-FLOOR-MAP-POLISH-027: the fixture catalog envelope (absent on
        // an older backend -> empty; the element layer simply draws nothing).
        floorElements: [
          for (final row in (raw['floor_elements'] as List?) ?? const [])
            if (row is Map)
              if (_elementFrom(row) case final e?) e,
        ],
      ),
    );
  }

  static DashboardFloorElement? _elementFrom(Map<dynamic, dynamic> row) {
    final id = row['id'];
    final sectionId = row['section_id'];
    final kind = row['kind'];
    final x = row['layout_x'];
    final y = row['layout_y'];
    final w = row['width_norm'];
    final h = row['height_norm'];
    if (id is! String ||
        id.isEmpty ||
        sectionId is! String ||
        sectionId.isEmpty ||
        kind is! String ||
        kind.isEmpty ||
        x is! int ||
        y is! int ||
        w is! int ||
        h is! int) {
      return null; // malformed -> skip (decoration, never worth failing a load)
    }
    final orient = row['orientation_quarter_turns'];
    final label = row['label'];
    return DashboardFloorElement(
      id: id,
      sectionId: sectionId,
      kind: kind,
      layoutX: x,
      layoutY: y,
      widthNorm: w,
      heightNorm: h,
      orientationQuarterTurns: orient is int && orient >= 0 && orient <= 3
          ? orient
          : 0,
      label: label is String && label.isNotEmpty ? label : null,
    );
  }

  static DashboardTableSection? _sectionFrom(Map<dynamic, dynamic> row) {
    final id = row['id'];
    final name = row['name'];
    if (id is! String || name is! String || name.isEmpty) return null;
    final order = row['display_order'];
    return DashboardTableSection(
      id: id,
      name: name,
      displayOrder: order is int ? order : 0,
      isActive: row['is_active'] == true,
      branchId: (row['branch_id'] ?? '').toString(),
    );
  }

  static DashboardTable? _tableFrom(Map<dynamic, dynamic> row) {
    final status = DiningTableStatus.fromWire(row['status']?.toString());
    if (status == null) return null; // unknown -> skip
    final seats = row['seats'];
    final area = row['area']?.toString();
    // RESTAURANT-OPERATIONS-V1-001: server-derived occupancy; missing/malformed
    // degrades to 0 (display truth, never a gate).
    final activeOrders = row['active_order_count'];
    // PILOT-OPERATIONS-CORRECTIONS-001: the server-computed effective state +
    // active link group (display-only on the Dashboard; the POS owns link/unlink).
    final effective = row['effective_state'];
    final groupId = row['group_id'];
    // TABLE-FLOOR-LAYOUT-021: the section + normalized placement (all nullable;
    // a legacy row simply carries none). Defensive both-or-neither on the
    // coordinates — the DB forbids halves, and we never trust one axis.
    final sectionId = row['section_id'];
    final sectionName = row['section_name'];
    final sectionOrder = row['section_display_order'];
    final rawX = row['layout_x'];
    final rawY = row['layout_y'];
    final hasXY = rawX is int && rawY is int;
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
      effectiveState: effective is String && effective.isNotEmpty
          ? effective
          : null,
      groupId: groupId is String && groupId.isNotEmpty ? groupId : null,
      sectionId: sectionId is String && sectionId.isNotEmpty ? sectionId : null,
      sectionName: sectionName is String && sectionName.isNotEmpty
          ? sectionName
          : null,
      sectionDisplayOrder: sectionOrder is int ? sectionOrder : null,
      layoutX: hasXY ? rawX : null,
      layoutY: hasXY ? rawY : null,
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

  // ---- TABLE-FLOOR-LAYOUT-021: sections + freeform placement ---------------

  @override
  Future<AdminResult<void>> upsertSection({
    String? id,
    required String name,
    required bool isActive,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const Failure(AdminValidation('name'));
    final restaurantId = _scope.restaurantId;
    final branchId = _scope.branchId;
    if (restaurantId == null || branchId == null) {
      return const Failure(AdminValidation('scope'));
    }
    return _invokeVoid('upsert_table_section', <String, dynamic>{
      'p_client_request_id': _requestId('upsert-section', [id ?? '', trimmed]),
      'p_organization_id': _scope.organizationId,
      'p_restaurant_id': restaurantId,
      'p_branch_id': branchId,
      'p_id': id,
      'p_name': trimmed,
      'p_is_active': isActive,
    });
  }

  @override
  Future<AdminResult<void>> deleteSection(String id) async =>
      _invokeVoid('soft_delete_table_section', <String, dynamic>{
        'p_client_request_id': _requestId('delete-section', [id]),
        'p_organization_id': _scope.organizationId,
        'p_section_id': id,
      });

  @override
  Future<AdminResult<void>> setTableSection(
    String tableId,
    String? sectionId,
  ) async => _invokeVoid('set_table_section', <String, dynamic>{
    'p_client_request_id': _requestId('set-section', [
      tableId,
      sectionId ?? '',
    ]),
    'p_organization_id': _scope.organizationId,
    'p_table_id': tableId,
    'p_section_id': sectionId,
  });

  @override
  Future<AdminResult<void>> setTablePosition(
    String tableId,
    int layoutX,
    int layoutY,
  ) async {
    if (layoutX < 0 || layoutX > 10000 || layoutY < 0 || layoutY > 10000) {
      return const Failure(AdminValidation('position'));
    }
    return _invokeVoid('set_table_layout_position', <String, dynamic>{
      'p_client_request_id': _requestId('set-position', [
        tableId,
        '$layoutX',
        '$layoutY',
      ]),
      'p_organization_id': _scope.organizationId,
      'p_table_id': tableId,
      'p_layout_x': layoutX,
      'p_layout_y': layoutY,
    });
  }

  @override
  Future<AdminResult<void>> reorderSections(List<String> ids) async {
    if (ids.isEmpty) return const Failure(AdminValidation('sections'));
    final restaurantId = _scope.restaurantId;
    final branchId = _scope.branchId;
    if (restaurantId == null || branchId == null) {
      return const Failure(AdminValidation('scope'));
    }
    return _invokeVoid('reorder_table_sections', <String, dynamic>{
      'p_organization_id': _scope.organizationId,
      'p_restaurant_id': restaurantId,
      'p_branch_id': branchId,
      'p_ids': ids,
    });
  }

  // ---- TABLE-FLOOR-MAP-POLISH-027: visual fixtures -------------------------

  @override
  Future<AdminResult<void>> upsertFloorElement(
    DashboardFloorElement element,
  ) async {
    final restaurantId = _scope.restaurantId;
    final branchId = _scope.branchId;
    if (restaurantId == null || branchId == null) {
      return const Failure(AdminValidation('scope'));
    }
    final trimmed = element.label?.trim();
    return _invokeVoid('upsert_floor_element', <String, dynamic>{
      'p_client_request_id': _requestId('upsert-element', [
        element.id,
        element.kind,
        '${element.layoutX}',
        '${element.layoutY}',
      ]),
      'p_organization_id': _scope.organizationId,
      'p_restaurant_id': restaurantId,
      'p_branch_id': branchId,
      'p_section_id': element.sectionId,
      'p_kind': element.kind,
      // Empty id = create: the SERVER mints (p_id null); a known id updates.
      'p_id': element.id.isEmpty ? null : element.id,
      'p_layout_x': element.layoutX,
      'p_layout_y': element.layoutY,
      'p_width_norm': element.widthNorm,
      'p_height_norm': element.heightNorm,
      'p_orientation_quarter_turns': element.orientationQuarterTurns,
      'p_label': (trimmed?.isEmpty ?? true) ? null : trimmed,
    });
  }

  @override
  Future<AdminResult<void>> deleteFloorElement(String id) async =>
      _invokeVoid('delete_floor_element', <String, dynamic>{
        'p_client_request_id': _requestId('delete-element', [id]),
        'p_organization_id': _scope.organizationId,
        'p_element_id': id,
      });

  /// The shared invoke-and-map body every void write above uses.
  Future<AdminResult<void>> _invokeVoid(
    String function,
    Map<String, dynamic> params,
  ) async {
    final Object? raw;
    try {
      raw = await _t.invoke(function, params);
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
