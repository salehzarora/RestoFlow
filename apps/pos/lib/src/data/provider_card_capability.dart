/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F — the till's card-terminal posture and the
/// fresh manager proof, both read from the server's PIN-session probe
/// `public.pin_session_capabilities` (execution packet §4.4, §8.4, §9).
///
/// `branch_features.card_terminal_mode` (`test` | `live`) and
/// `branch_features.card_terminal_enabled` (boolean) are present only while the
/// session's exact device has a `configured`, `enabled` or `draining` terminal
/// binding (API_CONTRACT §4.30b). They are ADVISORY: the server's claim and its
/// `card_terminal_required` guard stay the authority. The posture is never
/// derived from a local toggle.
library;

import 'package:flutter/foundation.dart' show immutable;
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'provider_card_attempt.dart' show ProviderCardMode;

/// What the probe says about this till's card terminal.
@immutable
sealed class ProviderCardPosture {
  const ProviderCardPosture();
}

/// Both keys absent: no binding (or an older server). The legacy hand-recorded
/// Card tender is unchanged and no integrated action is offered.
@immutable
final class ProviderCardPostureAbsent extends ProviderCardPosture {
  const ProviderCardPostureAbsent();
}

/// A binding in `configured`, `enabled` or `draining`. [enabled] is true only
/// while new integrated starts are permitted.
@immutable
final class ProviderCardPosturePresent extends ProviderCardPosture {
  const ProviderCardPosturePresent(this.mode, {required this.enabled});
  final ProviderCardMode mode;
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is ProviderCardPosturePresent &&
      other.mode == mode &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(mode, enabled);
}

/// The probe failed, has not answered, or answered a shape this build cannot
/// read. Fail closed: no integrated action, and the legacy Card tender waits
/// for a successful re-read (packet §9.1).
@immutable
final class ProviderCardPostureUnknown extends ProviderCardPosture {
  const ProviderCardPostureUnknown();
}

/// Parses the posture from the probe's top-level `branch_features` value.
///
/// Absent (`null`) or a map holding neither key is [ProviderCardPostureAbsent];
/// both keys well-typed is [ProviderCardPosturePresent]; anything else — one
/// key alone, a wrong type, an unknown mode, a non-map value — is
/// [ProviderCardPostureUnknown]. Never throws.
ProviderCardPosture providerCardPostureFrom(Object? branchFeatures) {
  if (branchFeatures == null) return const ProviderCardPostureAbsent();
  if (branchFeatures is! Map) return const ProviderCardPostureUnknown();
  final hasMode = branchFeatures.containsKey('card_terminal_mode');
  final hasEnabled = branchFeatures.containsKey('card_terminal_enabled');
  if (!hasMode && !hasEnabled) return const ProviderCardPostureAbsent();
  final mode = ProviderCardMode.fromWire(branchFeatures['card_terminal_mode']);
  final enabled = branchFeatures['card_terminal_enabled'];
  if (mode == null || enabled is! bool) {
    return const ProviderCardPostureUnknown();
  }
  return ProviderCardPosturePresent(mode, enabled: enabled);
}

/// The roles that may Resume a recording (**D-054** point 4).
const Set<String> kProviderCardManagerRoles = <String>{
  'manager',
  'restaurant_owner',
  'org_owner',
};

/// The answer of a fresh manager proof.
enum ProviderCardManagerProof {
  /// The probe answered `ok:true` with a manager-or-higher role: an active PIN
  /// session and an active membership of that role.
  proven,

  /// The probe answered `ok:true` with another role.
  notManager,

  /// No usable answer (no session, a transport failure, a refusal, a shape this
  /// build cannot read). Nothing is dispatched.
  unavailable,
}

/// A FRESH `pin_session_capabilities` read whose only use is the Resume's
/// manager proof (packet §8.4). Never cached; never throws.
Future<ProviderCardManagerProof> proveProviderCardManager({
  required SyncRpcTransport? transport,
  required SyncSession? session,
}) async {
  if (transport == null || session == null) {
    return ProviderCardManagerProof.unavailable;
  }
  final Object? raw;
  try {
    raw = await transport.invoke('pin_session_capabilities', <String, dynamic>{
      'p_pin_session_id': session.pinSessionId,
      'p_device_id': session.deviceId,
    });
  } catch (_) {
    return ProviderCardManagerProof.unavailable;
  }
  if (raw is! Map || raw['ok'] != true) {
    return ProviderCardManagerProof.unavailable;
  }
  final role = raw['role'];
  if (role is! String) return ProviderCardManagerProof.unavailable;
  return kProviderCardManagerRoles.contains(role)
      ? ProviderCardManagerProof.proven
      : ProviderCardManagerProof.notManager;
}
