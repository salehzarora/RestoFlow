/// Read-only seam (RF-117): the owner-controlled per-branch TAX setting for THIS
/// paired POS station's branch, read token-proven server-side via
/// `public.get_device_branch_tax(p_device_id, p_session_token)`.
///
/// The value is a per-branch policy owned by the Dashboard (`branches.tax_enabled`
/// + `branches.tax_rate_bp`). The POS reads it to DISPLAY the tax line and to
/// include `tax_total_minor` in the order it submits; `app.submit_order` keeps its
/// existing money validation (grand = subtotal − discount + tax, non-negative).
///
/// This build wires the `exclusive` mode only (tax ADDED on top of the subtotal).
/// Money stays integer minor units and the rate is integer BASIS POINTS — there
/// is NO floating point (DECISION D-007).
///
/// [load] returns the branch tax setting, or `null` when it cannot be determined
/// (no credential, transport/session failure). Callers treat `null` as
/// [BranchTax.disabled] so a read glitch never invents a tax the owner did not
/// configure — tax is default-OFF (unlike the default-true shift-close policy).
abstract class DeviceBranchTaxReader {
  Future<BranchTax?> load();
}

/// The per-branch tax setting the POS reads to display tax (RF-117). Pure,
/// immutable value: whether the branch adds tax and, if so, the rate in integer
/// BASIS POINTS (1 bp = 0.01%; 1700 bp = 17.00%). No float, ever (D-007). The
/// rate is meaningful only when [enabled]; a disabled setting carries rate 0.
class BranchTax {
  const BranchTax({required this.enabled, required this.rateBp});

  /// Whether this branch adds tax (owner policy; default false).
  final bool enabled;

  /// The tax rate in integer basis points (0..10000). Meaningful only when
  /// [enabled]. Integer only — money and rates never use floating point.
  final int rateBp;

  /// The default: tax OFF (no jurisdiction frozen — the MVP supports the shape,
  /// ships no rate). Used whenever the setting is unread/unconfigured.
  static const BranchTax disabled = BranchTax(enabled: false, rateBp: 0);

  /// True only when the branch adds tax AND the rate is a positive number of
  /// basis points (a 0-bp "enabled" setting adds nothing, so it displays none).
  bool get addsTax => enabled && rateBp > 0;

  @override
  bool operator ==(Object other) =>
      other is BranchTax && other.enabled == enabled && other.rateBp == rateBp;

  @override
  int get hashCode => Object.hash(enabled, rateBp);

  @override
  String toString() => 'BranchTax(enabled: $enabled, rateBp: $rateBp)';
}
