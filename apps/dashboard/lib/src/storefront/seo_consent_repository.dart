import 'dart:math';

import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// Restaurant-wide permission for a future release. Never enables indexing.
class SeoConsentState {
  const SeoConsentState({
    required this.consentEnabled,
    required this.revision,
    required this.canManage,
  });

  final bool consentEnabled;
  final String revision;
  final bool canManage;
}

/// One explicit Save. Preserve this exact request until its receipt is known.
class SeoConsentMutation {
  const SeoConsentMutation({
    required this.id,
    required this.expectedRevision,
    required this.consentEnabled,
  });

  final String id;
  final String expectedRevision;
  final bool consentEnabled;
}

enum SeoConsentOutcome {
  ok,
  denied,
  notFound,
  revisionConflict,
  requestConflict,
  invalidRequest,
  unavailable,
}

class SeoConsentResult {
  const SeoConsentResult(this.outcome, {this.state});
  final SeoConsentOutcome outcome;
  final SeoConsentState? state;
}

enum SeoConsentMutationState { committed, notRecorded, refused }

class SeoConsentReconciliation {
  const SeoConsentReconciliation(
    this.outcome, {
    this.mutationState,
    this.current,
  });
  final SeoConsentOutcome outcome;
  final SeoConsentMutationState? mutationState;
  final SeoConsentState? current;
}

abstract interface class SeoConsentRepository {
  Future<SeoConsentResult> read();
  Future<SeoConsentResult> save(SeoConsentMutation intent);

  /// Reads the request receipt and current state. It never writes consent.
  Future<SeoConsentReconciliation> reconcile(SeoConsentMutation intent);
}

class SupabaseSeoConsentRepository implements SeoConsentRepository {
  SupabaseSeoConsentRepository({
    required SyncRpcTransport transport,
    required this.organizationId,
    required this.restaurantId,
  }) : _transport = transport;

  final SyncRpcTransport _transport;
  final String organizationId;
  final String restaurantId;

  Map<String, dynamic> get _scope => {
    'p_organization_id': organizationId,
    'p_restaurant_id': restaurantId,
  };

  Map<String, dynamic> _params(SeoConsentMutation intent) => {
    ..._scope,
    'p_client_request_id': intent.id,
    'p_expected_revision': intent.expectedRevision,
    'p_consent_enabled': intent.consentEnabled,
  };

  @override
  Future<SeoConsentResult> read() async {
    try {
      return _result(
        await _transport.invoke('get_storefront_seo_consent_v1', _scope),
      );
    } catch (_) {
      return const SeoConsentResult(SeoConsentOutcome.unavailable);
    }
  }

  @override
  Future<SeoConsentResult> save(SeoConsentMutation intent) async {
    try {
      final raw = await _transport.invoke(
        'set_storefront_seo_consent_v1',
        _params(intent),
      );
      if (raw is Map && raw['ok'] == true && !_validReceipt(raw, intent)) {
        return const SeoConsentResult(SeoConsentOutcome.unavailable);
      }
      return _result(raw);
    } catch (_) {
      // The server may already have committed. A new request is unsafe.
      return const SeoConsentResult(SeoConsentOutcome.unavailable);
    }
  }

  @override
  Future<SeoConsentReconciliation> reconcile(SeoConsentMutation intent) async {
    try {
      final raw = await _transport.invoke(
        'reconcile_storefront_seo_consent_v1',
        _params(intent),
      );
      if (raw is! Map || raw['ok'] != true) {
        return SeoConsentReconciliation(_error(raw));
      }
      if (!_sameScope(raw))
        return const SeoConsentReconciliation(SeoConsentOutcome.unavailable);
      final current = _state(raw['current']);
      if (current == null)
        return const SeoConsentReconciliation(SeoConsentOutcome.unavailable);
      final receipt = raw['result'];
      if (raw['mutation_state'] == 'committed' &&
          receipt is Map &&
          _validReceipt(receipt, intent)) {
        return SeoConsentReconciliation(
          SeoConsentOutcome.ok,
          mutationState: SeoConsentMutationState.committed,
          current: current,
        );
      }
      if (raw['mutation_state'] == 'refused' &&
          receipt is Map &&
          receipt['ok'] == false &&
          receipt['client_request_id'] == intent.id) {
        final outcome = _error(receipt);
        if (outcome == SeoConsentOutcome.revisionConflict ||
            outcome == SeoConsentOutcome.requestConflict ||
            outcome == SeoConsentOutcome.invalidRequest) {
          return SeoConsentReconciliation(
            outcome,
            mutationState: SeoConsentMutationState.refused,
            current: current,
          );
        }
      }
      if (raw['mutation_state'] == 'not_recorded' && receipt == null) {
        return SeoConsentReconciliation(
          SeoConsentOutcome.ok,
          mutationState: SeoConsentMutationState.notRecorded,
          current: current,
        );
      }
      return const SeoConsentReconciliation(SeoConsentOutcome.unavailable);
    } catch (_) {
      return const SeoConsentReconciliation(SeoConsentOutcome.unavailable);
    }
  }

  bool _validReceipt(Map raw, SeoConsentMutation intent) =>
      raw['client_request_id'] == intent.id &&
      _state(raw)?.consentEnabled == intent.consentEnabled;

  bool _sameScope(Map raw) =>
      raw['entity'] == 'storefront_seo_consent' &&
      raw['organization_id'] == organizationId &&
      raw['restaurant_id'] == restaurantId;

  SeoConsentResult _result(Object? raw) {
    if (raw is Map && raw['ok'] == true) {
      final state = _state(raw);
      return state == null
          ? const SeoConsentResult(SeoConsentOutcome.unavailable)
          : SeoConsentResult(SeoConsentOutcome.ok, state: state);
    }
    return SeoConsentResult(_error(raw));
  }

  SeoConsentState? _state(Object? raw) {
    if (raw is! Map ||
        raw['ok'] != true ||
        !_sameScope(raw) ||
        raw['provisioned'] is! bool ||
        raw['consent_enabled'] is! bool ||
        raw['can_manage'] is! bool ||
        raw['indexing_active'] != false ||
        raw['effective_indexing_eligible'] != false)
      return null;
    final revision = raw['revision'];
    if (revision is! String || !isSeoConsentRevision(revision)) return null;
    return SeoConsentState(
      consentEnabled: raw['consent_enabled'] as bool,
      revision: revision,
      canManage: raw['can_manage'] as bool,
    );
  }

  static SeoConsentOutcome _error(Object? raw) {
    if (raw is! Map) return SeoConsentOutcome.unavailable;
    return switch (raw['error']) {
      'permission_denied' => SeoConsentOutcome.denied,
      'not_found' => SeoConsentOutcome.notFound,
      'revision_conflict' => SeoConsentOutcome.revisionConflict,
      'request_conflict' => SeoConsentOutcome.requestConflict,
      'invalid_request' => SeoConsentOutcome.invalidRequest,
      _ => SeoConsentOutcome.unavailable,
    };
  }
}

bool isSeoConsentRevision(String value) =>
    RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(value) &&
    (value.length < 19 || value.compareTo('9223372036854775807') <= 0);

String newSeoConsentMutationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
