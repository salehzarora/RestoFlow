import 'app_user_context.dart';
import 'membership_context.dart';

/// The full result of `public.get_my_context()` (RF-124, API_CONTRACT section
/// 4.22). On success `ok` is always true; the server raises SQLSTATE 42501 on
/// failure (there is NO `ok:false` envelope). No `server_ts`, no money fields,
/// no global role.
class MyContext {
  const MyContext({
    required this.appUser,
    required this.isPlatformAdmin,
    required this.memberships,
    this.hasMfaAal2 = false,
  });

  /// The caller's own identity.
  final AppUserContext appUser;

  /// Separate platform-plane boolean (D-026) - NEVER a membership; no
  /// organization/restaurant/branch is derivable from it.
  final bool isPlatformAdmin;

  /// RF-119: whether the caller's OWN Supabase Auth session is at assurance level
  /// aal2 (`get_my_context.is_mfa_aal2`). A UX signal only - the admin gate uses
  /// it to show an honest "MFA required" state for a platform admin WITHOUT MFA;
  /// it is NEVER an authorization decision (platform data reads are gated
  /// server-side by `app.platform_admin_guard`). Defaults false (fail-closed) when
  /// the field is absent (a pre-RF-119 server, or a caller that does not use it).
  final bool hasMfaAal2;

  /// The caller's own memberships as a LIST (D-004); may be empty. Never
  /// collapsed into a single global role.
  final List<MembershipContext> memberships;

  /// Parses the raw `get_my_context` result. Fail-closed: a non-object,
  /// `ok != true`, or any missing/malformed field throws [FormatException]; an
  /// unknown membership role throws [UnknownRoleException]. Both are caught by
  /// the repository and mapped to typed failures.
  factory MyContext.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('get_my_context did not return an object');
    }
    final json = raw.cast<String, dynamic>();
    if (json['ok'] != true) {
      throw const FormatException('get_my_context ok != true');
    }
    final appUserJson = json['app_user'];
    if (appUserJson is! Map) {
      throw const FormatException(
        'get_my_context.app_user missing or not an object',
      );
    }
    final isPlatformAdmin = json['is_platform_admin'];
    if (isPlatformAdmin is! bool) {
      throw const FormatException(
        'get_my_context.is_platform_admin missing or not a bool',
      );
    }
    final membershipsJson = json['memberships'];
    if (membershipsJson is! List) {
      throw const FormatException(
        'get_my_context.memberships missing or not a list',
      );
    }
    final memberships = <MembershipContext>[];
    for (final entry in membershipsJson) {
      if (entry is! Map) {
        throw const FormatException('membership entry is not an object');
      }
      memberships.add(
        MembershipContext.fromJson(entry.cast<String, dynamic>()),
      );
    }
    // RF-119: tolerant parse (additive, non-breaking) - a missing or non-bool
    // `is_mfa_aal2` fails closed to false (a pre-RF-119 server, or a non-admin
    // consumer). Never throws on this field.
    final mfaAal2 = json['is_mfa_aal2'];
    return MyContext(
      appUser: AppUserContext.fromJson(appUserJson.cast<String, dynamic>()),
      isPlatformAdmin: isPlatformAdmin,
      memberships: List.unmodifiable(memberships),
      hasMfaAal2: mfaAal2 is bool ? mfaAal2 : false,
    );
  }
}
