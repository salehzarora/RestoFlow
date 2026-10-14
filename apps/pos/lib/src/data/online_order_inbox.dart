import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import '../state/pos_session.dart';
import '../state/pos_device_context.dart';
import '../state/pos_sync_scope_provider.dart';

/// Memory-only pickup intent. Never write these objects to an operational store.
enum OnlineOrderStatus { pending, accepted, rejected, expired }

enum OnlineOrderDecision { accept, reject }

enum OnlineInboxFailure {
  unavailable,
  transport,
  malformed,
  invalidSession,
  permissionDenied,
  notFound,
  requestExpired,
  decisionConflict,
  quoteChanged,
  itemUnavailable,
  modifierSelectionInvalid,
  orderingUnavailable,
  shiftRequired,
  orderRejected,
  invalidRequest,
}

class OnlineInboxException implements Exception {
  const OnlineInboxException(this.failure);
  final OnlineInboxFailure failure;
  // Deliberately excludes RPC diagnostics, customer data and credentials.
  @override
  String toString() => 'OnlineInboxException(${failure.name})';
}

Never _malformed() =>
    throw const OnlineInboxException(OnlineInboxFailure.malformed);

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
String _id(Object? value) =>
    value is String && _uuid.hasMatch(value) ? value : _malformed();
String _text(Object? value) => value is String ? value : _malformed();
String? _optionalText(Object? value) => value == null ? null : _text(value);
String? _itemNotes(Object? value) {
  final notes = _optionalText(value);
  if (notes != null &&
      (notes.runes.length > 140 ||
          notes.runes.any(
            (c) =>
                (c < 32 && c != 10) ||
                (c >= 127 && c <= 159) ||
                (c >= 0xd800 && c <= 0xdfff),
          ))) {
    _malformed();
  }
  return notes;
}

int _integer(Object? value, {int minimum = 0}) =>
    value is int && value >= minimum ? value : _malformed();
DateTime _time(Object? value) => value is String
    ? DateTime.tryParse(value)?.toUtc() ?? _malformed()
    : _malformed();
Map _object(Object? value) => value is Map ? value : _malformed();
List _array(Object? value) => value is List ? value : _malformed();

class OnlineOrderModifier {
  const OnlineOrderModifier({
    required this.name,
    required this.quantity,
    required this.priceMinor,
  });
  final String name;
  final int quantity;
  final int priceMinor;

  factory OnlineOrderModifier.fromJson(Object? raw) {
    final json = _object(raw);
    _id(json['modifier_option_id']);
    _id(json['modifier_id']);
    return OnlineOrderModifier(
      name: _text(json['option_name_snapshot']),
      quantity: _integer(json['quantity'], minimum: 1),
      priceMinor: _integer(json['price_minor_snapshot']),
    );
  }
}

class OnlineOrderItem {
  const OnlineOrderItem({
    required this.name,
    required this.quantity,
    required this.unitPriceMinor,
    required this.lineTotalMinor,
    required this.modifiers,
    this.notes,
  });
  final String name;
  final int quantity;
  final int unitPriceMinor;
  final int lineTotalMinor;
  final List<OnlineOrderModifier> modifiers;
  final String? notes;

  factory OnlineOrderItem.fromJson(Object? raw) {
    final json = _object(raw);
    _id(json['menu_item_id']);
    final item = OnlineOrderItem(
      name: _text(json['item_name_snapshot']),
      quantity: _integer(json['quantity'], minimum: 1),
      unitPriceMinor: _integer(json['unit_price_minor_snapshot']),
      lineTotalMinor: _integer(json['line_total_minor']),
      modifiers: List.unmodifiable(
        _array(json['modifiers']).map(OnlineOrderModifier.fromJson),
      ),
      notes: _itemNotes(json['notes']),
    );
    final options = item.modifiers.fold<int>(
      0,
      (sum, option) => sum + option.quantity * option.priceMinor,
    );
    if (item.lineTotalMinor !=
        item.quantity * (item.unitPriceMinor + options)) {
      _malformed();
    }
    return item;
  }
}

class OnlineOrderRequest {
  const OnlineOrderRequest({
    required this.id,
    required this.status,
    required this.customerName,
    required this.customerPhone,
    required this.notes,
    required this.createdAt,
    required this.expiresAt,
    required this.currencyCode,
    required this.subtotalMinor,
    required this.taxTotalMinor,
    required this.grandTotalMinor,
    required this.items,
    this.canonicalOrderId,
  });
  final String id;
  final OnlineOrderStatus status;
  final String customerName;
  final String customerPhone;
  final String? notes;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String currencyCode;
  final int subtotalMinor;
  final int taxTotalMinor;
  final int grandTotalMinor;
  final List<OnlineOrderItem> items;
  final String? canonicalOrderId;

  bool expiredAt(DateTime now) => !expiresAt.isAfter(now);

  factory OnlineOrderRequest.fromJson(Object? raw) {
    final json = _object(raw);
    final customer = _object(json['customer']);
    final totals = _object(json['totals']);
    final status = OnlineOrderStatus.values
        .where((s) => s.name == json['status'])
        .firstOrNull;
    if (status == null) _malformed();
    final currency = _text(totals['currency_code']);
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) _malformed();
    final request = OnlineOrderRequest(
      id: _id(json['request_id']),
      status: status,
      customerName: _text(customer['name']),
      customerPhone: _text(customer['phone']),
      notes: _optionalText(json['notes']),
      createdAt: _time(json['created_at']),
      expiresAt: _time(json['expires_at']),
      currencyCode: currency,
      subtotalMinor: _integer(totals['subtotal_minor']),
      taxTotalMinor: _integer(totals['tax_total_minor']),
      grandTotalMinor: _integer(totals['grand_total_minor']),
      items: List.unmodifiable(
        _array(json['items']).map(OnlineOrderItem.fromJson),
      ),
      canonicalOrderId: json['canonical_order_id'] == null
          ? null
          : _id(json['canonical_order_id']),
    );
    if (request.items.isEmpty ||
        request.subtotalMinor !=
            request.items.fold<int>(
              0,
              (sum, item) => sum + item.lineTotalMinor,
            ) ||
        request.grandTotalMinor !=
            request.subtotalMinor + request.taxTotalMinor ||
        !request.expiresAt.isAfter(request.createdAt) ||
        (status == OnlineOrderStatus.accepted) !=
            (request.canonicalOrderId != null)) {
      _malformed();
    }
    return request;
  }
}

class OnlineInboxCursor {
  const OnlineInboxCursor(this.createdAt, this.id);
  final DateTime createdAt;
  final String id;
  factory OnlineInboxCursor.fromJson(Object? raw) {
    final json = _object(raw);
    return OnlineInboxCursor(_time(json['created_at']), _id(json['id']));
  }
}

class OnlineInboxPage {
  const OnlineInboxPage({
    required this.serverTime,
    required this.requests,
    this.hasMore = false,
    this.nextCursor,
  });
  final DateTime serverTime;
  final List<OnlineOrderRequest> requests;
  final bool hasMore;
  final OnlineInboxCursor? nextCursor;

  factory OnlineInboxPage.fromJson(Object? raw) {
    final json = _success(raw);
    if (json['has_more'] is! bool) _malformed();
    final page = OnlineInboxPage(
      serverTime: _time(json['server_time']),
      requests: List.unmodifiable(
        _array(json['requests']).map(OnlineOrderRequest.fromJson),
      ),
      hasMore: json['has_more'] as bool,
      nextCursor: json['next_cursor'] == null
          ? null
          : OnlineInboxCursor.fromJson(json['next_cursor']),
    );
    if (page.hasMore && page.nextCursor == null) _malformed();
    if (page.requests.map((r) => r.id).toSet().length != page.requests.length) {
      _malformed();
    }
    return page;
  }
}

class OnlineInboxDecisionResult {
  const OnlineInboxDecisionResult({
    required this.requestId,
    required this.status,
    required this.canonicalOrderId,
    required this.decisionId,
    required this.replayed,
  });
  final String requestId;
  final OnlineOrderStatus status;
  final String? canonicalOrderId;
  final String decisionId;
  final bool replayed;

  factory OnlineInboxDecisionResult.fromJson(Object? raw) {
    final json = _success(raw);
    final status = switch (json['status']) {
      'accepted' => OnlineOrderStatus.accepted,
      'rejected' => OnlineOrderStatus.rejected,
      _ => _malformed(),
    };
    final canonicalId = json['canonical_order_id'] == null
        ? null
        : _id(json['canonical_order_id']);
    if ((status == OnlineOrderStatus.accepted) != (canonicalId != null) ||
        json['replayed'] is! bool) {
      _malformed();
    }
    return OnlineInboxDecisionResult(
      requestId: _id(json['request_id']),
      status: status,
      canonicalOrderId: canonicalId,
      decisionId: _id(json['decision_id']),
      replayed: json['replayed'] as bool,
    );
  }
}

Map _success(Object? raw) {
  final json = _object(raw);
  if (json['ok'] == true) return json;
  if (json['ok'] != false) _malformed();
  throw OnlineInboxException(switch (json['error']) {
    'invalid_session' => OnlineInboxFailure.invalidSession,
    'permission_denied' => OnlineInboxFailure.permissionDenied,
    'not_found' => OnlineInboxFailure.notFound,
    'request_expired' => OnlineInboxFailure.requestExpired,
    'decision_conflict' => OnlineInboxFailure.decisionConflict,
    'quote_changed' => OnlineInboxFailure.quoteChanged,
    'item_unavailable' => OnlineInboxFailure.itemUnavailable,
    'modifier_selection_invalid' => OnlineInboxFailure.modifierSelectionInvalid,
    'ordering_unavailable' => OnlineInboxFailure.orderingUnavailable,
    'shift_required' => OnlineInboxFailure.shiftRequired,
    'order_rejected' => OnlineInboxFailure.orderRejected,
    'invalid_request' => OnlineInboxFailure.invalidRequest,
    _ => OnlineInboxFailure.malformed,
  });
}

abstract class OnlineOrderInboxRepository {
  Future<OnlineInboxPage> fetch({String? requestId, OnlineInboxCursor? cursor});
  Future<OnlineInboxDecisionResult> decide({
    required String requestId,
    required String decisionId,
    required OnlineOrderDecision decision,
    String? reason,
  });
}

class RealOnlineOrderInboxRepository implements OnlineOrderInboxRepository {
  const RealOnlineOrderInboxRepository({
    required SyncRpcTransport transport,
    required SyncSession session,
    required DeviceSessionSecretStore secretStore,
    this.isCurrent,
  }) : _transport = transport,
       _session = session,
       _secretStore = secretStore;
  final SyncRpcTransport _transport;
  final SyncSession _session;
  final DeviceSessionSecretStore _secretStore;
  final bool Function()? isCurrent;

  Future<Object?> _invoke(String rpc, Map<String, dynamic> params) async {
    final credential = await _secretStore.read();
    if (credential == null ||
        credential.deviceId != _session.deviceId ||
        credential.sessionToken.isEmpty ||
        isCurrent?.call() == false) {
      throw const OnlineInboxException(OnlineInboxFailure.invalidSession);
    }
    try {
      return await _transport.invoke(rpc, {
        ...params,
        'p_device_id': _session.deviceId,
        'p_pin_session_id': _session.pinSessionId,
        'p_device_session_token': credential.sessionToken,
      });
    } on SyncTransportException catch (error) {
      // Hosted RPCs remain deliberately undeployed in this ticket.
      throw OnlineInboxException(
        error.code == 'PGRST202' || error.code == '42883'
            ? OnlineInboxFailure.unavailable
            : error.kind == SyncTransportErrorKind.auth
            ? OnlineInboxFailure.invalidSession
            : OnlineInboxFailure.transport,
      );
    } catch (_) {
      throw const OnlineInboxException(OnlineInboxFailure.transport);
    }
  }

  @override
  Future<OnlineInboxPage> fetch({
    String? requestId,
    OnlineInboxCursor? cursor,
  }) async => OnlineInboxPage.fromJson(
    await _invoke('pos_web_order_inbox', {
      'p_request_id': requestId,
      'p_before_created_at': cursor?.createdAt.toIso8601String(),
      'p_before_id': cursor?.id,
      'p_limit': 50,
    }),
  );

  @override
  Future<OnlineInboxDecisionResult> decide({
    required String requestId,
    required String decisionId,
    required OnlineOrderDecision decision,
    String? reason,
  }) async {
    if (decision == OnlineOrderDecision.reject &&
        (reason == null ||
            reason.trim().isEmpty ||
            reason.trim().runes.length > 240 ||
            RegExp(r'[\x00-\x1F\x7F]').hasMatch(reason))) {
      throw const OnlineInboxException(OnlineInboxFailure.invalidRequest);
    }
    return OnlineInboxDecisionResult.fromJson(
      await _invoke(
        decision == OnlineOrderDecision.accept
            ? 'pos_accept_web_order'
            : 'pos_reject_web_order',
        {
          'p_request_id': requestId,
          'p_decision_id': decisionId,
          if (decision == OnlineOrderDecision.reject)
            'p_reason': reason!.trim(),
        },
      ),
    );
  }
}

class UnavailableOnlineOrderInboxRepository
    implements OnlineOrderInboxRepository {
  const UnavailableOnlineOrderInboxRepository();
  @override
  Future<OnlineInboxPage> fetch({
    String? requestId,
    OnlineInboxCursor? cursor,
  }) => throw const OnlineInboxException(OnlineInboxFailure.unavailable);
  @override
  Future<OnlineInboxDecisionResult> decide({
    required String requestId,
    required String decisionId,
    required OnlineOrderDecision decision,
    String? reason,
  }) => throw const OnlineInboxException(OnlineInboxFailure.unavailable);
}

/// Uses the boot coordinator's EXISTING platform-backed credential store.
final onlineOrderInboxSecretStoreProvider = Provider<DeviceSessionSecretStore?>(
  (ref) => null,
);

final onlineOrderInboxRepositoryProvider = Provider<OnlineOrderInboxRepository>(
  (ref) {
    final transport = ref.watch(posAuthTransportProvider);
    final session = ref.watch(posSyncSessionProvider);
    final store = ref.watch(onlineOrderInboxSecretStoreProvider);
    final context = ref.watch(posDeviceContextProvider);
    final scope = ref.watch(posSyncScopeProvider);
    if (transport == null ||
        session == null ||
        store == null ||
        scope == null ||
        context == null ||
        context.deviceType != 'pos' ||
        context.deviceId != session.deviceId ||
        context.deviceSessionId == null ||
        context.deviceSessionId!.isEmpty) {
      return const UnavailableOnlineOrderInboxRepository();
    }
    // Eager cancellation flags avoid reading an outdated Riverpod ref after
    // the asynchronous credential read. Dependency changes invalidate this
    // repository before its replacement necessarily gets built.
    var current = true;
    ref.listen(posSyncSessionProvider, (_, next) {
      if (next != session) current = false;
    });
    ref.listen(posSyncScopeProvider, (_, next) {
      if (next != scope) current = false;
    });
    ref.listen(posDeviceContextProvider, (_, next) {
      if (next?.deviceSessionId != context.deviceSessionId ||
          next?.deviceId != context.deviceId ||
          next?.organizationId != context.organizationId ||
          next?.restaurantId != context.restaurantId ||
          next?.branchId != context.branchId ||
          next?.deviceType != 'pos') {
        current = false;
      }
    });
    ref.onDispose(() => current = false);
    return RealOnlineOrderInboxRepository(
      transport: transport,
      session: session,
      secretStore: store,
      isCurrent: () => current,
    );
  },
);
