/// The caller's own identity from `public.get_my_context().app_user`
/// (API_CONTRACT section 4.22). Exactly four fields - no money, no extra keys,
/// only the CALLER's own data (the resolver is self-scoped, RF-124).
class AppUserContext {
  const AppUserContext({
    required this.id,
    required this.email,
    required this.displayName,
    required this.isActive,
  });

  /// The caller's `app_users.id`.
  final String id;

  /// The caller's email (always non-null per `app_users.email NOT NULL`).
  final String email;

  /// The caller's display name; nullable per `app_users.display_name`.
  final String? displayName;

  /// Whether the caller's `app_users.is_active` is true.
  final bool isActive;

  /// Parses the `app_user` object. Fail-closed: a missing or wrong-typed
  /// required field throws [FormatException] (the repository maps it to an
  /// invalid-response failure). No key beyond {id,email,display_name,is_active}
  /// is read.
  factory AppUserContext.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final email = json['email'];
    final isActive = json['is_active'];
    final displayName = json['display_name'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('app_user.id missing or not a string');
    }
    if (email is! String || email.isEmpty) {
      throw const FormatException('app_user.email missing or not a string');
    }
    if (isActive is! bool) {
      throw const FormatException('app_user.is_active missing or not a bool');
    }
    if (displayName != null && displayName is! String) {
      throw const FormatException('app_user.display_name not a string or null');
    }
    return AppUserContext(
      id: id,
      email: email,
      displayName: displayName as String?,
      isActive: isActive,
    );
  }
}
