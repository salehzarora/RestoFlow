import 'dart:math';

import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// Branch configuration, independent of global operators and device consent.
class OnlineOrderValues {
  const OnlineOrderValues({
    required this.ordering,
    required this.alerts,
    required this.printing,
  });

  final bool ordering;
  final bool alerts;
  final bool printing;

  OnlineOrderValues copyWith({bool? ordering, bool? alerts, bool? printing}) =>
      OnlineOrderValues(
        ordering: ordering ?? this.ordering,
        alerts: alerts ?? this.alerts,
        printing: printing ?? this.printing,
      );

  @override
  bool operator ==(Object other) =>
      other is OnlineOrderValues &&
      ordering == other.ordering &&
      alerts == other.alerts &&
      printing == other.printing;

  @override
  int get hashCode => Object.hash(ordering, alerts, printing);
}

class OnlineOrderSettings {
  const OnlineOrderSettings({required this.values, required this.revision});

  final OnlineOrderValues values;

  /// Canonical decimal text: never round a PostgreSQL bigint through JS number.
  final String revision;
}

/// Created once per explicit Save and retained unchanged until reconciled.
class OnlineOrderMutation {
  const OnlineOrderMutation({
    required this.id,
    required this.expectedRevision,
    required this.values,
  });

  final String id;
  final String expectedRevision;
  final OnlineOrderValues values;
}

enum OnlineOrderOutcome {
  ok,
  denied,
  notFound,
  revisionConflict,
  requestConflict,
  invalidRequest,
  unavailable,
}

class OnlineOrderResult {
  const OnlineOrderResult(this.outcome, {this.settings});
  final OnlineOrderOutcome outcome;
  final OnlineOrderSettings? settings;
}

enum OnlineOrderMutationState { committed, notRecorded, refused }

class OnlineOrderReconciliation {
  const OnlineOrderReconciliation(this.outcome, {this.state, this.current});

  final OnlineOrderOutcome outcome;
  final OnlineOrderMutationState? state;
  final OnlineOrderSettings? current;
}

abstract interface class OnlineOrderSettingsRepository {
  Future<OnlineOrderResult> read();
  Future<OnlineOrderResult> save(OnlineOrderMutation intent);

  /// Queries the receipt and current state; never performs a settings write.
  Future<OnlineOrderReconciliation> reconcile(OnlineOrderMutation intent);
}

/// The normal authenticated Dashboard transport. No identity/credentials are
/// supplied by this seam; scope is pinned and every successful response checked.
class SupabaseOnlineOrderSettingsRepository
    implements OnlineOrderSettingsRepository {
  SupabaseOnlineOrderSettingsRepository({
    required SyncRpcTransport transport,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
  }) : _transport = transport;

  final SyncRpcTransport _transport;
  final String organizationId;
  final String restaurantId;
  final String branchId;

  Map<String, dynamic> get _scope => {
    'p_organization_id': organizationId,
    'p_restaurant_id': restaurantId,
    'p_branch_id': branchId,
  };

  Map<String, dynamic> _params(OnlineOrderMutation intent) => {
    ..._scope,
    'p_client_request_id': intent.id,
    'p_expected_revision': intent.expectedRevision,
    'p_ordering_enabled': intent.values.ordering,
    'p_alerts_enabled': intent.values.alerts,
    'p_printing_enabled': intent.values.printing,
  };

  @override
  Future<OnlineOrderResult> read() async {
    try {
      return _result(
        await _transport.invoke('get_online_order_settings_v2', _scope),
      );
    } catch (_) {
      return const OnlineOrderResult(OnlineOrderOutcome.unavailable);
    }
  }

  @override
  Future<OnlineOrderResult> save(OnlineOrderMutation intent) async {
    try {
      final raw = await _transport.invoke(
        'set_online_order_settings_v2',
        _params(intent),
      );
      if (raw is Map &&
          raw['ok'] == true &&
          raw['client_request_id'] != intent.id) {
        return const OnlineOrderResult(OnlineOrderOutcome.unavailable);
      }
      return _result(raw);
    } catch (_) {
      // A transport/unknown response may follow a COMMIT. The UI must freeze
      // this exact intent and use the read-only reconciliation contract.
      return const OnlineOrderResult(OnlineOrderOutcome.unavailable);
    }
  }

  @override
  Future<OnlineOrderReconciliation> reconcile(
    OnlineOrderMutation intent,
  ) async {
    try {
      final raw = await _transport.invoke(
        'reconcile_online_order_settings_v2',
        _params(intent),
      );
      if (raw is! Map || raw['ok'] != true) {
        return OnlineOrderReconciliation(_error(raw));
      }
      final current = _settings(raw['current']);
      if (current == null) {
        return const OnlineOrderReconciliation(OnlineOrderOutcome.unavailable);
      }
      if (raw['mutation_state'] == 'committed') {
        final receipt = raw['result'];
        if (receipt is! Map ||
            receipt['ok'] != true ||
            receipt['client_request_id'] != intent.id ||
            _settings(receipt) == null) {
          return const OnlineOrderReconciliation(
            OnlineOrderOutcome.unavailable,
          );
        }
        return OnlineOrderReconciliation(
          OnlineOrderOutcome.ok,
          state: OnlineOrderMutationState.committed,
          current: current,
        );
      }
      if (raw['mutation_state'] == 'refused') {
        final receipt = raw['result'];
        if (receipt is! Map ||
            receipt['ok'] != false ||
            receipt['client_request_id'] != intent.id) {
          return const OnlineOrderReconciliation(
            OnlineOrderOutcome.unavailable,
          );
        }
        final outcome = _error(receipt);
        if (outcome != OnlineOrderOutcome.revisionConflict &&
            outcome != OnlineOrderOutcome.requestConflict &&
            outcome != OnlineOrderOutcome.invalidRequest) {
          return const OnlineOrderReconciliation(
            OnlineOrderOutcome.unavailable,
          );
        }
        return OnlineOrderReconciliation(
          outcome,
          state: OnlineOrderMutationState.refused,
          current: current,
        );
      }
      if (raw['mutation_state'] == 'not_recorded' && raw['result'] == null) {
        return OnlineOrderReconciliation(
          OnlineOrderOutcome.ok,
          state: OnlineOrderMutationState.notRecorded,
          current: current,
        );
      }
      return const OnlineOrderReconciliation(OnlineOrderOutcome.unavailable);
    } catch (_) {
      return const OnlineOrderReconciliation(OnlineOrderOutcome.unavailable);
    }
  }

  OnlineOrderResult _result(Object? raw) {
    if (raw is Map && raw['ok'] == true) {
      final state = _settings(raw);
      return state == null
          ? const OnlineOrderResult(OnlineOrderOutcome.unavailable)
          : OnlineOrderResult(OnlineOrderOutcome.ok, settings: state);
    }
    return OnlineOrderResult(
      _error(raw),
      settings: raw is Map ? _settings(raw['current']) : null,
    );
  }

  OnlineOrderSettings? _settings(Object? raw) {
    if (raw is! Map ||
        raw['ok'] != true ||
        raw['entity'] != 'online_order_settings' ||
        raw['organization_id'] != organizationId ||
        raw['restaurant_id'] != restaurantId ||
        raw['branch_id'] != branchId ||
        raw['provisioned'] is! bool ||
        raw['ordering_enabled'] is! bool ||
        raw['alerts_enabled'] is! bool ||
        raw['printing_enabled'] is! bool) {
      return null;
    }
    final revision = raw['revision'];
    if (revision is! String || !isOnlineOrderRevision(revision)) return null;
    return OnlineOrderSettings(
      revision: revision,
      values: OnlineOrderValues(
        ordering: raw['ordering_enabled'] as bool,
        alerts: raw['alerts_enabled'] as bool,
        printing: raw['printing_enabled'] as bool,
      ),
    );
  }

  static OnlineOrderOutcome _error(Object? raw) {
    if (raw is! Map) return OnlineOrderOutcome.unavailable;
    return switch (raw['error']) {
      'permission_denied' => OnlineOrderOutcome.denied,
      'not_found' => OnlineOrderOutcome.notFound,
      'revision_conflict' => OnlineOrderOutcome.revisionConflict,
      'request_conflict' => OnlineOrderOutcome.requestConflict,
      'invalid_request' => OnlineOrderOutcome.invalidRequest,
      _ => OnlineOrderOutcome.unavailable,
    };
  }
}

bool isOnlineOrderRevision(String value) =>
    RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(value) &&
    (value.length < 19 || value.compareTo('9223372036854775807') <= 0);

String newOnlineOrderMutationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
