import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show PulledKitchenDispatch;

/// No customer data, destination, token, or raw server diagnostic is retained.
enum OnlineOrderPrintState {
  claimed,
  busy,
  available,
  sendReserved,
  reconciliationRequired,
  transportAccepted,
  unavailable,
}

class OnlineOrderPrintResult {
  const OnlineOrderPrintResult({
    required this.requestId,
    required this.orderId,
    required this.dispatchId,
    required this.decisionId,
    required this.printerAssignmentId,
    required this.state,
    this.dispatch,
    this.attemptId,
    this.sendAuthorized = false,
  });
  final String requestId, orderId, dispatchId, decisionId;
  // A status-only available ledger has not selected a printer yet. Claimed
  // and sendReserved replies still require a valid assignment in the decoder.
  final String? printerAssignmentId;
  final OnlineOrderPrintState state;
  final PulledKitchenDispatch? dispatch;
  final String? attemptId;
  final bool sendAuthorized;
}

abstract interface class OnlineOrderPrintRepository {
  Future<OnlineOrderPrintResult> claim(String requestId);
  Future<OnlineOrderPrintResult> begin(String requestId, String attemptId);
  Future<OnlineOrderPrintResult> finish(
    String requestId,
    String attemptId,
    String clientStatus, {
    String? errorCode,
  });
  Future<OnlineOrderPrintResult> status(String requestId);
}

class OnlineOrderPrintException implements Exception {
  const OnlineOrderPrintException();
  @override
  String toString() => 'OnlineOrderPrintException';
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
String _id(Object? value) => value is String && _uuid.hasMatch(value)
    ? value
    : throw const OnlineOrderPrintException();

/// Uses the REAL paired-device secret and current PIN. Request ID is a lookup,
/// never dispatch/scope authority. Only a fresh begin reply may authorize send.
class RealOnlineOrderPrintRepository implements OnlineOrderPrintRepository {
  const RealOnlineOrderPrintRepository({
    required SyncRpcTransport transport,
    required SyncSession session,
    required DeviceSessionSecretStore secretStore,
    required bool Function() isCurrent,
  }) : _transport = transport,
       _session = session,
       _secretStore = secretStore,
       _isCurrent = isCurrent;
  final SyncRpcTransport _transport;
  final SyncSession _session;
  final DeviceSessionSecretStore _secretStore;
  final bool Function() _isCurrent;

  Future<OnlineOrderPrintResult> _invoke(
    String rpc,
    String requestId, {
    String? attemptId,
    String? clientStatus,
    String? errorCode,
  }) async {
    _id(requestId);
    if (attemptId != null) _id(attemptId);
    try {
      final credential = await _secretStore.read();
      if (!_isCurrent() ||
          credential == null ||
          credential.deviceId != _session.deviceId ||
          credential.sessionToken.isEmpty) {
        throw const OnlineOrderPrintException();
      }
      final raw = await _transport.invoke(rpc, {
        'p_request_id': requestId,
        'p_device_id': _session.deviceId,
        'p_pin_session_id': _session.pinSessionId,
        'p_device_session_token': credential.sessionToken,
        if (attemptId != null) 'p_attempt_id': attemptId,
        if (clientStatus != null) 'p_client_status': clientStatus,
        if (errorCode != null) 'p_error_code': errorCode,
      });
      if (!_isCurrent() ||
          raw is! Map ||
          raw['ok'] != true ||
          _id(raw['request_id']) != requestId) {
        throw const OnlineOrderPrintException();
      }
      final state = switch (raw['state']) {
        'claimed' => OnlineOrderPrintState.claimed,
        'busy' => OnlineOrderPrintState.busy,
        'available' => OnlineOrderPrintState.available,
        'send_reserved' => OnlineOrderPrintState.sendReserved,
        'reconciliation_required' =>
          OnlineOrderPrintState.reconciliationRequired,
        'transport_accepted' => OnlineOrderPrintState.transportAccepted,
        _ => throw const OnlineOrderPrintException(),
      };
      final orderId = _id(raw['canonical_order_id']);
      final dispatchId = _id(raw['dispatch_id']);
      final assignmentId = raw['printer_assignment_id'] == null
          ? null
          : _id(raw['printer_assignment_id']);
      if ((state == OnlineOrderPrintState.claimed ||
              state == OnlineOrderPrintState.sendReserved) &&
          assignmentId == null) {
        throw const OnlineOrderPrintException();
      }
      final returnedAttempt = raw['attempt_id'] == null
          ? null
          : _id(raw['attempt_id']);
      final authorized = raw['send_authorized'] == true;
      if (authorized &&
          (rpc != 'pos_begin_web_order_print' ||
              state != OnlineOrderPrintState.sendReserved ||
              returnedAttempt != attemptId)) {
        throw const OnlineOrderPrintException();
      }
      PulledKitchenDispatch? dispatch;
      if (raw['dispatch'] != null) {
        final row = raw['dispatch'];
        if (rpc != 'pos_claim_web_order_print' ||
            state != OnlineOrderPrintState.claimed ||
            row is! Map ||
            _id(row['id']) != dispatchId ||
            _id(row['order_id']) != orderId ||
            row['dispatch_type'] != 'initial_order' ||
            row['service_round_id'] != null ||
            row['payload_version'] != 1 ||
            row['payload'] is! Map ||
            row['created_at'] is! String ||
            DateTime.tryParse(row['created_at'] as String) == null) {
          throw const OnlineOrderPrintException();
        }
        dispatch = PulledKitchenDispatch(
          dispatchId: dispatchId,
          dispatchType: 'initial_order',
          orderId: orderId,
          payloadVersion: 1,
          moneyFreePayload: Map<String, Object?>.from(row['payload'] as Map),
          createdAt: row['created_at'] as String,
          claimExpiresAt: row['claim_expires_at'] as String?,
        );
      }
      if (state == OnlineOrderPrintState.claimed && dispatch == null) {
        throw const OnlineOrderPrintException();
      }
      return OnlineOrderPrintResult(
        requestId: requestId,
        orderId: orderId,
        dispatchId: dispatchId,
        decisionId: _id(raw['decision_id']),
        printerAssignmentId: assignmentId,
        state: state,
        dispatch: dispatch,
        attemptId: returnedAttempt,
        sendAuthorized: authorized,
      );
    } catch (_) {
      throw const OnlineOrderPrintException();
    }
  }

  @override
  Future<OnlineOrderPrintResult> claim(String requestId) =>
      _invoke('pos_claim_web_order_print', requestId);
  @override
  Future<OnlineOrderPrintResult> begin(String requestId, String attemptId) =>
      _invoke('pos_begin_web_order_print', requestId, attemptId: attemptId);
  @override
  Future<OnlineOrderPrintResult> status(String requestId) =>
      _invoke('pos_web_order_print_status', requestId);
  @override
  Future<OnlineOrderPrintResult> finish(
    String requestId,
    String attemptId,
    String clientStatus, {
    String? errorCode,
  }) {
    if (!const {
          'transport_accepted',
          'possibly_printed',
          'failed_retryable',
          'blocked_configuration',
        }.contains(clientStatus) ||
        (errorCode != null &&
            !RegExp(r'^[a-z0-9_]{1,80}$').hasMatch(errorCode))) {
      throw const OnlineOrderPrintException();
    }
    return _invoke(
      'pos_finish_web_order_print',
      requestId,
      attemptId: attemptId,
      clientStatus: clientStatus,
      errorCode: errorCode,
    );
  }
}
