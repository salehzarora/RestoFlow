/// The four client surfaces (one per app binary) that RF-108 routes principals
/// into. The role -> surface policy lives in `RoleEntryPolicy`.
enum AppSurface {
  /// Cashier point-of-sale (`apps/pos`).
  pos,

  /// Kitchen display (`apps/kds`).
  kds,

  /// Owner/manager dashboard (`apps/dashboard`).
  dashboard,

  /// Platform-admin console (`apps/admin`) - gated by `is_platform_admin`, never
  /// by a tenant role (D-026).
  admin,
}
