import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'kitchen_print_worker.dart' show isTargetedWebPrintJob;
import 'kitchen_print_permission.dart';

/// Disk policy is RESTRICTIVE EVIDENCE, never positive send authority. A new
/// controller/process must obtain fresh paired-device authorization before its
/// server-imported spool can run. Direct/local offline POS printing does not
/// call this guard. This authority-validity rule survives even total failure
/// to write/invalidate old permissive cache bytes; no deletion is assumed.
class KitchenPrintContainment {
  KitchenPrintContainment({
    required DeviceContext context,
    required DeviceSessionSecretStore secretStore,
    required SyncRpcTransport transport,
    required bool Function() isCurrent,
    required bool Function() isOffline,
    FlutterSecureStorage? storage,
    Future<String?> Function(String)? readCache,
    Future<void> Function(String, String)? writeCache,
    DateTime Function()? now,
    KitchenPrintContainmentDomain? domain,
  }) : _context = context,
       _secrets = secretStore,
       _transport = transport,
       _isCurrent = isCurrent,
       _isOffline = isOffline,
       _read =
           readCache ??
           ((key) => (storage ?? const FlutterSecureStorage()).read(key: key)),
       _write =
           writeCache ??
           ((key, value) => (storage ?? const FlutterSecureStorage()).write(
             key: key,
             value: value,
           )),
       _now = now ?? DateTime.now {
    _barrier = (domain ?? _nativeDomain)._barriers.putIfAbsent(
      _cacheKey,
      _ScopeBarrier.new,
    );
    _generation = ++_barrier.generation;
  }

  final DeviceContext _context;
  final DeviceSessionSecretStore _secrets;
  final SyncRpcTransport _transport;
  final bool Function() _isCurrent, _isOffline;
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  final DateTime Function() _now;
  _Policy? _policy;
  Future<void> _pending = Future<void>.value();
  String? _fingerprint;
  bool _cacheLoaded = false;
  int? _ordinaryAuthorityRevision;
  int _operationEpoch = 0;
  late final _ScopeBarrier _barrier;
  late final int _generation;

  // A provider replacement invalidates its predecessor before any old reply
  // can install permission. Cross-controller writes to one scoped cache key
  // are serialized, including a plugin write already pending at replacement.
  static final KitchenPrintContainmentDomain _nativeDomain =
      KitchenPrintContainmentDomain();
  bool get _active => _isCurrent() && _barrier.generation == _generation;
  bool get _ordinaryAuthority =>
      _active &&
      _ordinaryAuthorityRevision != null &&
      _policy?.raw['mode'] == 'ordinary' &&
      _policy!.revision == _ordinaryAuthorityRevision &&
      _barrier.observation?.revision == _ordinaryAuthorityRevision;

  String get _cacheKey =>
      'restoflow.pos.kitchen_spool.containment.v1.'
      '${_context.organizationId}.${_context.restaurantId}.${_context.branchId}.${_context.deviceId}';

  /// Serialize reads and cache writes. Every caller gets a new observation
  /// after earlier reads, rather than sharing a read started before gate wait.
  Future<bool> synchronize() {
    final operation = _pending.then((_) => _synchronize());
    _pending = operation.then((_) {});
    return operation;
  }

  Future<bool> _synchronize() async {
    var succeeded = false;
    try {
      final credential = await _secrets.read();
      if (!_active ||
          credential == null ||
          credential.deviceId != _context.deviceId ||
          credential.sessionToken.isEmpty)
        return false;
      final fingerprint = sha256
          .convert(utf8.encode(credential.sessionToken))
          .toString();
      if (_fingerprint != fingerprint) {
        _fingerprint = fingerprint;
        _policy = null;
        _cacheLoaded = false;
        _ordinaryAuthorityRevision = null;
      }
      if (!_cacheLoaded) {
        try {
          final cached = await _read(_cacheKey);
          if (!_active) return false;
          if (cached != null) {
            final envelope = jsonDecode(cached);
            if (envelope is Map &&
                envelope['v'] == 1 &&
                envelope['session_fingerprint'] == fingerprint) {
              _observe(_decode(envelope['policy']), fromNetwork: false);
            }
          }
        } catch (_) {
          // Corrupt/unreadable cache grants nothing. A real fresh server
          // observation may still recover; we never regenerate a spool key.
        }
        _cacheLoaded = true;
      }
      // A current controller's successful online ordinary observation permits
      // later unheld spool work offline without an RPC. A restart/cache read
      // alone never recreates that authorization. Other genuine local offline
      // POS printing keeps its existing independent provenance/authority path.
      if (_isOffline()) return succeeded = _ordinaryAuthority;
      final raw = await _transport
          .invoke('pos_kitchen_print_containment', {
            'p_device_id': credential.deviceId,
            'p_session_token': credential.sessionToken,
          })
          .timeout(const Duration(seconds: 8));
      if (!_active || _fingerprint != fingerprint) return false;
      final fresh = _decode(raw);
      _ordinaryAuthorityRevision = null;
      // Publish the restriction BEFORE the first persistence await. If the
      // write fails or never completes, held/blocked jobs are already denied.
      final merged = _observe(fresh, fromNetwork: true);
      if (!await _persist(merged, fingerprint)) return false;
      if (merged.raw['mode'] == 'ordinary') {
        _ordinaryAuthorityRevision = merged.revision;
      }
      return succeeded = true;
    } catch (_) {
      // Learned restrictions and revoked authority are NOT rolled back here.
      return false;
    } finally {
      // Failed/malformed/missing observations invalidate outstanding operation
      // decisions without changing R2's controller-level offline authority.
      if (!succeeded) _operationEpoch++;
    }
  }

  _Policy _observe(_Policy incoming, {required bool fromNetwork}) {
    final previous = _barrier.observation;
    if (previous != null && incoming.revision < previous.revision) {
      _policy = previous;
      if (fromNetwork) throw const FormatException('stale_policy');
      return previous;
    }
    // Equal-revision mode changes may only tighten (expiry produces blocked).
    // A late permissive cache/response can never undo a learned restriction.
    var chosen = incoming;
    if (previous != null && incoming.revision == previous.revision) {
      const strength = {'ordinary': 0, 'target_only': 1, 'blocked': 2};
      if (strength[previous.raw['mode']]! > strength[incoming.raw['mode']]!) {
        chosen = previous;
      }
    }
    final merged = chosen.withHolds({...?previous?.held, ...incoming.held});
    _barrier.observation = merged;
    _policy = merged;
    return merged;
  }

  Future<bool> _persist(_Policy policy, String fingerprint) async {
    final done = Completer<void>();
    final prior = _barrier.writes;
    _barrier.writes = done.future;
    try {
      await prior;
      if (!_active || _fingerprint != fingerprint) return false;
      await _write(
        _cacheKey,
        jsonEncode({
          'v': 1,
          'session_fingerprint': fingerprint,
          'policy': policy.raw,
        }),
      );
      if (!_active || _fingerprint != fingerprint) return false;
      final currentCredential = await _secrets.read();
      return _active &&
          currentCredential != null &&
          currentCredential.deviceId == _context.deviceId &&
          sha256
                  .convert(utf8.encode(currentCredential.sessionToken))
                  .toString() ==
              fingerprint &&
          _barrier.observation?.revision == policy.revision;
    } finally {
      // A failed plugin write cannot poison the scoped queue. A newer current
      // controller writes AFTER any pending old write, never before it.
      done.complete();
    }
  }

  _Policy _decode(Object? raw) {
    if (raw is! Map ||
        raw['ok'] != true ||
        raw['organization_id'] != _context.organizationId ||
        raw['restaurant_id'] != _context.restaurantId ||
        raw['branch_id'] != _context.branchId ||
        raw['device_id'] != _context.deviceId ||
        raw['revision'] is! int ||
        (raw['revision'] as int) < 0 ||
        !const {'ordinary', 'blocked', 'target_only'}.contains(raw['mode']) ||
        raw['held_dispatch_ids'] is! List)
      throw const FormatException();
    final ids = <String>{};
    for (final id in raw['held_dispatch_ids'] as List) {
      if (id is! String || !_uuid.hasMatch(id)) throw const FormatException();
      ids.add(id.toLowerCase());
    }
    final target = raw['target_request_id'];
    final expires = raw['expires_at'];
    final expiry = expires is String ? DateTime.tryParse(expires) : null;
    if (raw['mode'] == 'target_only' &&
        (target is! String || !_uuid.hasMatch(target) || expiry == null))
      throw const FormatException();
    return _Policy(Map<String, Object?>.from(raw), ids, expiry);
  }

  Future<bool> allowsOrdinary() async =>
      await synchronize() && _ordinaryAuthority;

  Future<bool> allowsTarget(String requestId) async {
    if (!await synchronize() || !_active || _isOffline()) return false;
    final policy = _policy!;
    return policy.raw['mode'] == 'ordinary' ||
        (policy.raw['mode'] == 'target_only' &&
            policy.raw['target_request_id'] == requestId &&
            policy.expiry!.isAfter(_now().toUtc()));
  }

  /// Legacy ordinary-import adapter. Absence of an exact hold is not enough.
  /// Exact targets must supply their validated claim through authorizeOperation.
  Future<bool> allowsDispatch(String dispatchId) async {
    final permission = await authorizeOperation(
      KitchenPrintOperation.ordinaryImport,
      dispatchId: dispatchId,
    );
    return permission?.isCurrent ?? false;
  }

  /// One fresh, correctly scoped observation decides mode, identity and holds
  /// together. Returned authority is invalidated by any later observation,
  /// failed read, learned restriction, credential/generation or scope change.
  Future<KitchenPrintAuthorization?> authorizeOperation(
    KitchenPrintOperation operation, {
    required String dispatchId,
    KitchenPrintTarget? target,
  }) async {
    if (!_uuid.hasMatch(dispatchId) ||
        _policy?.held.contains(dispatchId.toLowerCase()) == true ||
        !await synchronize()) {
      return null;
    }
    final policy = _policy;
    final fingerprint = _fingerprint;
    final epoch = _operationEpoch;
    if (policy == null || fingerprint == null) return null;
    bool current() =>
        _active &&
        _fingerprint == fingerprint &&
        _operationEpoch == epoch &&
        identical(_policy, policy) &&
        identical(_barrier.observation, policy) &&
        _operationAllowed(operation, dispatchId, target, policy);
    if (!current()) return null;
    return KitchenPrintAuthorization(
      operation: operation,
      dispatchId: dispatchId,
      target: target,
      isCurrent: current,
      matchesCredential: (deviceId, sessionToken) =>
          deviceId == _context.deviceId &&
          sha256.convert(utf8.encode(sessionToken)).toString() == fingerprint,
    );
  }

  bool _operationAllowed(
    KitchenPrintOperation operation,
    String dispatchId,
    KitchenPrintTarget? target,
    _Policy policy,
  ) {
    if (policy.held.contains(dispatchId.toLowerCase())) return false;
    if (!operation.isTarget) {
      return target == null && _ordinaryAuthority;
    }
    if (target == null ||
        !target.isCurrent ||
        _isOffline() ||
        target.dispatchId != dispatchId ||
        ![
          target.requestId,
          target.orderId,
          target.dispatchId,
          target.decisionId,
          target.printerAssignmentId,
        ].every(_uuid.hasMatch)) {
      return false;
    }
    return (policy.raw['mode'] == 'ordinary' && _ordinaryAuthority) ||
        (policy.raw['mode'] == 'target_only' &&
            policy.raw['target_request_id'] == target.requestId &&
            policy.expiry!.isAfter(_now().toUtc()));
  }

  Future<bool> allowsJob(KitchenSpoolJobRow row) async =>
      (await permissionForJob(row)).mayTransmit;

  KitchenPrintPermission? _restriction(KitchenSpoolJobRow row) {
    final policy = _policy;
    if (policy == null) return null;
    if (policy.held.contains(row.dispatchId.toLowerCase())) {
      return KitchenPrintPermission.held;
    }
    if (policy.raw['mode'] == 'blocked' ||
        (policy.raw['mode'] == 'target_only' &&
            (!isTargetedWebPrintJob(row) ||
                row.localJobId !=
                    'web-initial:${policy.raw['target_request_id']}' ||
                !policy.expiry!.isAfter(_now().toUtc()) ||
                _isOffline()))) {
      return KitchenPrintPermission.blocked;
    }
    return null;
  }

  Future<KitchenPrintPermission> permissionForJob(
    KitchenSpoolJobRow row,
  ) async {
    if (row.organizationId != _context.organizationId ||
        row.restaurantId != _context.restaurantId ||
        row.branchId != _context.branchId ||
        row.deviceId != _context.deviceId ||
        !_active)
      return KitchenPrintPermission.unknown;
    // Immutable exact holds are positive ownership evidence. Branch blocks
    // stop sending but cannot exclude an owner; unknown reads cannot either.
    final restriction = _restriction(row);
    if (restriction != null) return restriction;
    final observed = await synchronize();
    if (!_active) return KitchenPrintPermission.unknown;
    final learnedRestriction = _restriction(row);
    if (learnedRestriction != null) return learnedRestriction;
    if (!observed) return KitchenPrintPermission.unknown;
    if (_policy!.raw['mode'] == 'ordinary') {
      return _ordinaryAuthority
          ? KitchenPrintPermission.permitted
          : KitchenPrintPermission.unknown;
    }
    // Exact active target passed _restriction; its real begin RPC still
    // validates request/order/dispatch/attempt/printer under the server lock.
    return KitchenPrintPermission.permitted;
  }
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class _Policy {
  _Policy(this.raw, this.held, this.expiry);
  final Map<String, Object?> raw;
  final Set<String> held;
  final DateTime? expiry;
  int get revision => raw['revision'] as int;
  _Policy withHolds(Set<String> ids) =>
      _Policy({...raw, 'held_dispatch_ids': ids.toList()..sort()}, ids, expiry);
}

class _ScopeBarrier {
  int generation = 0;
  Future<void> writes = Future<void>.value();
  _Policy? observation;
}

/// A process-local synchronization domain, shared by native production
/// controllers. Tests may inject one per isolated synthetic backing store.
/// It persists no positive authority and cannot authorize an offline restart.
class KitchenPrintContainmentDomain {
  final Map<String, _ScopeBarrier> _barriers = {};
}
