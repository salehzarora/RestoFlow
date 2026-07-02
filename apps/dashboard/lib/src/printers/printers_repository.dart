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

import 'printer_models.dart';

/// The dashboard Printers repository seam (RF-150 backend). Reuses the admin
/// failure vocabulary ([AdminFailure]/[AdminResult]) so the shared state views
/// and snackbar mapping work unchanged.
abstract class PrintersRepository {
  /// `public.list_printers` — printers + routes + the branch's stations.
  Future<AdminResult<PrintersSnapshot>> load();

  /// `public.upsert_printer_device` — create ([id] null) or update.
  Future<AdminResult<void>> upsertPrinter({
    String? id,
    required String displayName,
    required PrinterConnectionType connectionType,
    required PrinterRole role,
    required String paperWidth,
    required Map<String, Object?> connectionConfig,
    required bool isEnabled,
  });

  /// `public.set_printer_route` — idempotent on the live (station, printer) edge.
  Future<AdminResult<void>> setRoute({
    required String stationId,
    required String printerDeviceId,
    required bool isEnabled,
  });

  /// `public.soft_delete_printer_device` — tombstones the printer + its routes.
  Future<AdminResult<void>> deletePrinter(String id);
}

/// A clearly-labelled in-memory demo store (demo mode only; the demo banner is
/// shown by the shell). Mirrors the backend semantics without a backend.
class InMemoryPrintersStore implements PrintersRepository {
  InMemoryPrintersStore()
    : _stations = const [
        StationInfo(id: 'demo-station-grill', name: 'Grill'),
        StationInfo(id: 'demo-station-cold', name: 'Cold'),
      ],
      _printers = [
        const PrinterDevice(
          id: 'demo-printer-receipt',
          displayName: 'Front counter',
          connectionType: PrinterConnectionType.network,
          role: PrinterRole.receipt,
          paperWidth: '80mm',
          connectionConfig: {'host': '10.0.0.50', 'port': 9100},
          isEnabled: true,
        ),
        const PrinterDevice(
          id: 'demo-printer-kitchen',
          displayName: 'Kitchen pass',
          connectionType: PrinterConnectionType.network,
          role: PrinterRole.kitchen,
          paperWidth: '80mm',
          connectionConfig: {'host': '10.0.0.51', 'port': 9100},
          isEnabled: true,
        ),
      ],
      _routes = [
        const PrinterRoute(
          id: 'demo-route-1',
          stationId: 'demo-station-grill',
          printerDeviceId: 'demo-printer-kitchen',
          isEnabled: true,
        ),
      ];

  final List<StationInfo> _stations;
  final List<PrinterDevice> _printers;
  final List<PrinterRoute> _routes;
  int _seq = 0;

  @override
  Future<AdminResult<PrintersSnapshot>> load() async => Success(
    PrintersSnapshot(
      printers: List.unmodifiable(_printers),
      routes: List.unmodifiable(_routes),
      stations: List.unmodifiable(_stations),
    ),
  );

  @override
  Future<AdminResult<void>> upsertPrinter({
    String? id,
    required String displayName,
    required PrinterConnectionType connectionType,
    required PrinterRole role,
    required String paperWidth,
    required Map<String, Object?> connectionConfig,
    required bool isEnabled,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty) return const Failure(AdminValidation('name'));
    final device = PrinterDevice(
      id: id ?? 'demo-printer-${++_seq}',
      displayName: name,
      connectionType: connectionType,
      role: role,
      paperWidth: paperWidth,
      connectionConfig: Map.unmodifiable(connectionConfig),
      isEnabled: isEnabled,
    );
    final index = _printers.indexWhere((p) => p.id == device.id);
    if (index >= 0) {
      _printers[index] = device;
    } else {
      _printers.add(device);
    }
    return const Success(null);
  }

  @override
  Future<AdminResult<void>> setRoute({
    required String stationId,
    required String printerDeviceId,
    required bool isEnabled,
  }) async {
    final index = _routes.indexWhere(
      (r) => r.stationId == stationId && r.printerDeviceId == printerDeviceId,
    );
    final route = PrinterRoute(
      id: index >= 0 ? _routes[index].id : 'demo-route-${++_seq}',
      stationId: stationId,
      printerDeviceId: printerDeviceId,
      isEnabled: isEnabled,
    );
    if (index >= 0) {
      _routes[index] = route;
    } else {
      _routes.add(route);
    }
    return const Success(null);
  }

  @override
  Future<AdminResult<void>> deletePrinter(String id) async {
    _printers.removeWhere((p) => p.id == id);
    _routes.removeWhere((r) => r.printerDeviceId == id);
    return const Success(null);
  }
}

/// The real, Supabase-backed [PrintersRepository] over the hardened RF-150 RPCs
/// (`upsert_printer_device` / `set_printer_route` / `soft_delete_printer_device`)
/// plus the sprint's `list_printers` read RPC. Authenticated anon-key transport
/// only (DECISION D-011); identity server-derived from `auth.uid()`; scope from
/// the ACTIVE membership. Failures are safe, typed [AdminFailure]s.
class SupabasePrintersRepository implements PrintersRepository {
  SupabasePrintersRepository({
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
  Future<AdminResult<PrintersSnapshot>> load() async {
    final Object? raw;
    try {
      raw = await _t.invoke('list_printers', <String, dynamic>{
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
      PrintersSnapshot(
        printers: [
          for (final row in (raw['printers'] as List?) ?? const [])
            if (row is Map)
              if (_printerFrom(row) case final p?) p,
        ],
        routes: [
          for (final row in (raw['routes'] as List?) ?? const [])
            if (row is Map)
              PrinterRoute(
                id: (row['id'] ?? '').toString(),
                stationId: (row['station_id'] ?? '').toString(),
                printerDeviceId: (row['printer_device_id'] ?? '').toString(),
                isEnabled: row['is_enabled'] == true,
              ),
        ],
        stations: [
          for (final row in (raw['stations'] as List?) ?? const [])
            if (row is Map)
              StationInfo(
                id: (row['id'] ?? '').toString(),
                name: (row['name'] ?? '').toString(),
              ),
        ],
      ),
    );
  }

  static PrinterDevice? _printerFrom(Map<dynamic, dynamic> row) {
    final connection = PrinterConnectionType.fromWire(
      row['connection_type']?.toString(),
    );
    final role = PrinterRole.fromWire(row['role']?.toString());
    if (connection == null || role == null) return null; // unknown -> skip
    final config = row['connection_config'];
    return PrinterDevice(
      id: (row['id'] ?? '').toString(),
      displayName: (row['display_name'] ?? '').toString(),
      connectionType: connection,
      role: role,
      paperWidth: (row['paper_width'] ?? '80mm').toString(),
      connectionConfig: config is Map
          ? config.map((k, v) => MapEntry(k.toString(), v as Object?))
          : const {},
      isEnabled: row['is_enabled'] == true,
    );
  }

  @override
  Future<AdminResult<void>> upsertPrinter({
    String? id,
    required String displayName,
    required PrinterConnectionType connectionType,
    required PrinterRole role,
    required String paperWidth,
    required Map<String, Object?> connectionConfig,
    required bool isEnabled,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty) return const Failure(AdminValidation('name'));
    final restaurantId = _scope.restaurantId;
    final branchId = _scope.branchId;
    // printer_devices is branch-scoped (org/restaurant/branch NOT NULL): an
    // org-wide membership must pick a branch scope first (honest validation).
    if (restaurantId == null || branchId == null) {
      return const Failure(AdminValidation('scope'));
    }
    final Object? raw;
    try {
      raw = await _t.invoke('upsert_printer_device', <String, dynamic>{
        'p_organization_id': _scope.organizationId,
        'p_restaurant_id': restaurantId,
        'p_branch_id': branchId,
        'p_id': id,
        'p_display_name': name,
        'p_connection_type': connectionType.wire,
        'p_role': role.wire,
        'p_paper_width': paperWidth,
        'p_connection_config': connectionConfig,
        'p_is_enabled': isEnabled,
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
  Future<AdminResult<void>> setRoute({
    required String stationId,
    required String printerDeviceId,
    required bool isEnabled,
  }) async {
    final restaurantId = _scope.restaurantId;
    final branchId = _scope.branchId;
    if (restaurantId == null || branchId == null) {
      return const Failure(AdminValidation('scope'));
    }
    final Object? raw;
    try {
      raw = await _t.invoke('set_printer_route', <String, dynamic>{
        'p_organization_id': _scope.organizationId,
        'p_restaurant_id': restaurantId,
        'p_branch_id': branchId,
        'p_station_id': stationId,
        'p_printer_device_id': printerDeviceId,
        'p_is_enabled': isEnabled,
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
  Future<AdminResult<void>> deletePrinter(String id) async {
    final restaurantId = _scope.restaurantId;
    final branchId = _scope.branchId;
    if (restaurantId == null || branchId == null) {
      return const Failure(AdminValidation('scope'));
    }
    final Object? raw;
    try {
      raw = await _t.invoke('soft_delete_printer_device', <String, dynamic>{
        'p_organization_id': _scope.organizationId,
        'p_restaurant_id': restaurantId,
        'p_branch_id': branchId,
        'p_id': id,
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

  // Reserved for future idempotent writes (upsert/set_route are naturally
  // idempotent server-side; soft-delete is state-guarded). Kept so the seam
  // matches the device repo if a ledger-keyed RPC is added later.
  // ignore: unused_element
  String _requestId(String op, List<String> parts) {
    final seed = [_uid() ?? '', op, ...parts, _nonce().toString()].join('|');
    final bytes = sha256
        .convert(utf8.encode('mvp:printers:$seed'))
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
