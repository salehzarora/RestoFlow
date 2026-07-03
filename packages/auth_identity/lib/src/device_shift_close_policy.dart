/// Read-only seam (RF-113): whether THIS paired POS station's branch has the
/// owner-controlled "Close shift & count cash" reconciliation workflow enabled.
///
/// The value is a per-branch POLICY flag owned by the Dashboard
/// (`branches.pos_shift_close_enabled`) and read token-proven server-side via
/// `public.get_device_pos_shift_close_enabled`. It gates only the VISIBILITY of
/// the reconciliation UI on the POS — the server's internal shift requirement
/// for payments (RF-055) is independent and unchanged.
///
/// [load] returns `true`/`false` for a known policy, or `null` when it cannot
/// be determined (no credential, transport/session failure). Callers treat
/// `null` as "enabled" (the default-true policy) so a read glitch never hides a
/// legitimately-available workflow.
abstract class DeviceShiftClosePolicyReader {
  Future<bool?> load();
}
