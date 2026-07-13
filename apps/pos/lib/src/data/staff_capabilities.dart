import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// FULL-COMP-PERMISSION-001 — the EFFECTIVE rights of the human behind the current
/// PIN session, as the SERVER resolves them.
///
/// These are EFFECTIVE, not stored, values: a manager/owner holds both rights BY
/// ROLE, while a cashier holds [applyDiscount] by default and [applyFullComp] only
/// via an explicit grant. The POS therefore never has to know the role or reason
/// about role hierarchies — it asks the server what this person may do.
///
/// ADVISORY ONLY. The server re-decides on every mutation inside `app.apply_discount`
/// and remains the sole authority. These exist so the POS can state the rule up
/// front instead of letting a cashier type a discount, wait, and be refused.
class PosStaffCapabilities {
  const PosStaffCapabilities({
    required this.applyDiscount,
    required this.applyFullComp,
  });

  /// FAIL-CLOSED default: knowing nothing, we assume nothing is granted.
  static const PosStaffCapabilities none = PosStaffCapabilities(
    applyDiscount: false,
    applyFullComp: false,
  );

  /// May apply ordinary discounts.
  final bool applyDiscount;

  /// May apply a discount that brings the order total to exactly zero.
  final bool applyFullComp;

  /// Parses the `capabilities` object from `public.pin_session_capabilities`.
  ///
  /// Both use `== true`, so a missing field, an old server that does not send the
  /// key, a null, or any malformed value resolves to DENIED. The client never
  /// invents a permission it was not explicitly given.
  static PosStaffCapabilities fromJson(Map<Object?, Object?> json) =>
      PosStaffCapabilities(
        applyDiscount: json['apply_discount'] == true,
        applyFullComp: json['apply_full_comp'] == true,
      );
}

/// Reads the effective capabilities of the current PIN session.
abstract class StaffCapabilitiesRepository {
  /// Returns the effective capabilities, or null when they cannot be established
  /// (no session, transport failure, malformed envelope).
  ///
  /// NULL MEANS "UNKNOWN", NOT "DENIED" — and the two must not be conflated. The
  /// POS keeps the discount controls available when capabilities are unknown and
  /// lets the SERVER refuse, because silently hiding a manager's discount button
  /// after a transient network blip would be a worse failure than an honest
  /// server-side rejection. Nothing unsafe can follow: the server gate is
  /// authoritative and a zero-total discount is still refused there.
  Future<PosStaffCapabilities?> fetch();
}

/// DEMO capabilities: the demo cashier can discount but CANNOT comp, so the demo
/// exercises the same refusal path a real un-granted cashier hits.
class DemoStaffCapabilitiesRepository implements StaffCapabilitiesRepository {
  const DemoStaffCapabilitiesRepository();

  @override
  Future<PosStaffCapabilities?> fetch() async =>
      const PosStaffCapabilities(applyDiscount: true, applyFullComp: false);
}

/// REAL capabilities, read from `public.pin_session_capabilities` over the same
/// anon-key + PIN/device-session transport as the sync path (never the `app`
/// schema, never a service-role key).
class RealStaffCapabilitiesRepository implements StaffCapabilitiesRepository {
  const RealStaffCapabilitiesRepository(this._transport, this._session);

  final SyncRpcTransport? _transport;
  final SyncSession? _session;

  @override
  Future<PosStaffCapabilities?> fetch() async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) return null;

    final Object? raw;
    try {
      raw = await transport.invoke(
        'pin_session_capabilities',
        <String, dynamic>{
          'p_pin_session_id': session.pinSessionId,
          'p_device_id': session.deviceId,
        },
      );
    } on SyncTransportException {
      return null; // unknown, not denied — see the seam doc above.
    }
    if (raw is! Map || raw['ok'] != true) return null;
    final caps = raw['capabilities'];
    if (caps is! Map) return null;
    return PosStaffCapabilities.fromJson(caps);
  }
}
