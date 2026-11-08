import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/online_order_inbox.dart';
import 'pos_session.dart';

/// Public negotiated protocol values. Secrets stay in method-local RPC inputs.
final _id = RegExp(r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$');
bool dutyId(Object? value) => value is String && _id.hasMatch(value);
bool dutyHash(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
bool dutyFields(Map? value, Set<String> keys) =>
    value != null &&
    value.length == keys.length &&
    value.keys.every(keys.contains);

DateTime? dutyTime(Object? value) {
  if (value is! String) return null;
  final m = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|[+-](?:0\d|1\d|2[0-3]):[0-5]\d)$',
  ).firstMatch(value);
  if (m == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(m[i]!)];
  if (parts[1] < 1 ||
      parts[1] > 12 ||
      parts[2] < 1 ||
      parts[2] > DateTime.utc(parts[0], parts[1] + 1, 0).day ||
      parts[3] > 23 ||
      parts[4] > 59 ||
      parts[5] > 59)
    return null;
  return DateTime.tryParse(value)?.toUtc();
}

class ShiftAlertPreview {
  const ShiftAlertPreview._(
    this.consentId,
    this.shiftId,
    this.revision,
    this.endWire,
    this.end,
    this.serverTime,
  );
  final String consentId;
  final String shiftId;
  final String revision;
  final String endWire;
  final DateTime end;
  final DateTime serverTime;

  static ShiftAlertPreview? parse(
    Map? raw, {
    required String consent,
    required bool issued,
  }) {
    if (!dutyFields(raw, {
      'ok',
      'mode',
      'consent_id',
      'shift_id',
      'policy_revision',
      'authority_expires_at',
      'server_time',
      if (issued) ...{'registration_id', 'generation'},
    }))
      return null;
    final r = raw!;
    final end = dutyTime(r['authority_expires_at']),
        time = dutyTime(r['server_time']);
    if (r['ok'] != true ||
        r['mode'] != 'shift' ||
        !dutyId(consent) ||
        r['consent_id'] != consent ||
        !dutyId(r['shift_id']) ||
        !dutyId(r['policy_revision']) ||
        end == null ||
        time == null ||
        !time.isBefore(end) ||
        issued && (!dutyId(r['registration_id']) || !dutyId(r['generation'])))
      return null;
    return ShiftAlertPreview._(
      consent,
      r['shift_id'] as String,
      r['policy_revision'] as String,
      r['authority_expires_at'] as String,
      end,
      time,
    );
  }

  bool matches(ShiftAlertPreview other) =>
      consentId == other.consentId &&
      shiftId == other.shiftId &&
      revision == other.revision &&
      end.isAtSameMomentAs(other.end) &&
      !other.serverTime.isBefore(serverTime);
}

enum ShiftAlertPhase { none, pending, active, revoking, expired }

class ShiftAlertStatus {
  const ShiftAlertStatus(
    this.phase,
    this.available,
    this.canStartConsent,
    this.end,
    this.remaining,
  );
  final ShiftAlertPhase phase;
  final bool available;
  final bool canStartConsent;
  final DateTime? end;
  final Duration? remaining;

  static ShiftAlertStatus? parse(Map? raw) {
    if (raw == null || raw['phase'] is! String) return null;
    final phase = ShiftAlertPhase.values
        .where((v) => v.name == raw['phase'])
        .firstOrNull;
    final active = phase == ShiftAlertPhase.active;
    if (phase == null ||
        !dutyFields(raw, {
          'phase',
          'available',
          'ready',
          'opt_in',
          'can_start_consent',
          if (active) ...{
            'consent_id',
            'registration_generation',
            'authority_expires_at',
            'remaining_ms',
          },
        }) ||
        raw['available'] is! bool ||
        raw['ready'] is! bool ||
        raw['opt_in'] is! bool ||
        raw['can_start_consent'] is! bool ||
        (raw['can_start_consent'] == true &&
            (raw['available'] != true ||
                active ||
                phase == ShiftAlertPhase.pending)) ||
        raw['ready'] != active ||
        (phase != ShiftAlertPhase.none && raw['available'] != true))
      return null;
    if (!active)
      return ShiftAlertStatus(
        phase,
        raw['available'] as bool,
        raw['can_start_consent'] as bool,
        null,
        null,
      );
    final end = dutyTime(raw['authority_expires_at']), ms = raw['remaining_ms'];
    if (raw['opt_in'] != true ||
        !dutyId(raw['consent_id']) ||
        !dutyId(raw['registration_generation']) ||
        end == null ||
        ms is! int ||
        ms <= 0 ||
        ms > 0x7fffffff)
      return null;
    return ShiftAlertStatus(
      phase,
      true,
      false,
      end,
      Duration(milliseconds: ms),
    );
  }
}

enum ShiftAlertCall { preview, enroll }

typedef ShiftAlertRpc =
    Future<Map?> Function(
      ShiftAlertCall call,
      Map<String, dynamic> input,
      bool Function() current,
    );

final shiftAlertRpcProvider = Provider<ShiftAlertRpc>((ref) {
  final transport = ref.watch(posAuthTransportProvider),
      session = ref.watch(posSyncSessionProvider);
  final secrets = ref.watch(onlineOrderInboxSecretStoreProvider);
  var live = true;
  ref.onDispose(() => live = false);
  return (call, input, current) async {
    if (!live ||
        !current() ||
        session == null ||
        transport == null ||
        secrets == null)
      return null;
    final device = await secrets.read();
    if (!live ||
        !current() ||
        device == null ||
        device.deviceId != session.deviceId ||
        device.sessionToken.isEmpty)
      return null;
    final response = await transport.invoke(
      call == ShiftAlertCall.preview
          ? 'pos_preview_shift_order_alert'
          : 'pos_register_shift_order_alert',
      {
        ...input,
        'p_device_id': session.deviceId,
        'p_pin_session_id': session.pinSessionId,
        'p_device_session_token': device.sessionToken,
      },
    );
    return live && current() && response is Map ? response : null;
  };
});
