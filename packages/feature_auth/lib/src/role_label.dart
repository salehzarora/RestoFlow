import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// The localized display label for a membership [role] (the six D-004 keys).
///
/// Roles are per-membership (D-004) - there is no global role, and
/// `platform_admin` is NOT a membership role (D-026), so it never reaches here.
String membershipRoleLabel(AppLocalizations l10n, MembershipRole role) =>
    switch (role) {
      MembershipRole.orgOwner => l10n.authRoleOwner,
      MembershipRole.restaurantOwner => l10n.authRoleRestaurantOwner,
      MembershipRole.manager => l10n.authRoleManager,
      MembershipRole.cashier => l10n.authRoleCashier,
      MembershipRole.kitchenStaff => l10n.authRoleKitchenStaff,
      MembershipRole.accountant => l10n.authRoleAccountant,
    };
