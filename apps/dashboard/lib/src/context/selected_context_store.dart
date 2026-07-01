import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's SELECTED membership (organization/restaurant/branch scope)
/// across restarts (RF-152). The stored value is the membership id — a NON-SECRET
/// UUID, never a token/password — so it does not require secure storage. Startup
/// ALWAYS re-validates the restored id against the live memberships and clears it
/// if it is no longer allowed (fail-closed; see [DashboardAuthFlow]).
abstract interface class SelectedContextStore {
  /// The persisted selected membership id, or null if none/absent.
  Future<String?> readSelectedMembershipId();

  /// Persists [membershipId] as the selected membership.
  Future<void> writeSelectedMembershipId(String membershipId);

  /// Clears any persisted selection (called on sign-out or on an invalid saved id).
  Future<void> clear();
}

/// An in-memory [SelectedContextStore] (the default + the test seam). Survives
/// only for the app session — no cross-restart persistence.
class InMemorySelectedContextStore implements SelectedContextStore {
  String? _id;

  @override
  Future<String?> readSelectedMembershipId() async => _id;

  @override
  Future<void> writeSelectedMembershipId(String membershipId) async =>
      _id = membershipId;

  @override
  Future<void> clear() async => _id = null;
}

/// A `SharedPreferences`-backed [SelectedContextStore] used in production (web:
/// localStorage). Stores only the non-secret selected membership id.
class SharedPreferencesSelectedContextStore implements SelectedContextStore {
  static const String _key = 'rf152.selected_membership_id';

  @override
  Future<String?> readSelectedMembershipId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  @override
  Future<void> writeSelectedMembershipId(String membershipId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, membershipId);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
