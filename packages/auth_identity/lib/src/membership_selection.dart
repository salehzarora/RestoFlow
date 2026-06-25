import 'membership_context.dart';
import 'my_context.dart';

/// The selection status given the membership list + the platform-admin flag.
enum MembershipSelectionStatus {
  /// No memberships and not a platform admin -> show a "no access" screen.
  noMemberships,

  /// No memberships but IS a platform admin -> admin-only entry (D-026); NO
  /// tenant scope is derived.
  platformAdminNoMemberships,

  /// Exactly one membership -> auto-selected (no picker needed).
  autoSelected,

  /// More than one membership and none validly selected -> show the picker.
  pickerNeeded,

  /// More than one membership and one is validly selected.
  selected,
}

/// In-memory (Stage 1) multi-membership selection model (D-004).
///
/// Holds the membership list, the platform-admin flag, and an optional selected
/// membership id, and derives the active membership FAIL-CLOSED. Stage 1 keeps
/// this in memory only (re-pick on restart) - no secure storage is added yet.
class MembershipSelection {
  const MembershipSelection({
    required this.memberships,
    required this.isPlatformAdmin,
    this.selectedMembershipId,
  });

  /// Builds the selection from a parsed [MyContext].
  factory MembershipSelection.fromContext(
    MyContext context, {
    String? selectedMembershipId,
  }) {
    return MembershipSelection(
      memberships: context.memberships,
      isPlatformAdmin: context.isPlatformAdmin,
      selectedMembershipId: selectedMembershipId,
    );
  }

  final List<MembershipContext> memberships;
  final bool isPlatformAdmin;
  final String? selectedMembershipId;

  /// The active membership, or `null`.
  ///
  /// - Zero memberships -> null.
  /// - Exactly one -> that membership (auto-active; a stale selected id is
  ///   ignored).
  /// - More than one -> the membership whose id equals [selectedMembershipId];
  ///   if none is selected, or the selected id is not in the list, returns null
  ///   (FAIL-CLOSED - never guesses).
  MembershipContext? get activeMembership {
    if (memberships.isEmpty) return null;
    if (memberships.length == 1) return memberships.first;
    final id = selectedMembershipId;
    if (id == null) return null;
    for (final membership in memberships) {
      if (membership.id == id) return membership;
    }
    return null;
  }

  /// The current selection status (drives the entry/landing UI).
  MembershipSelectionStatus get status {
    if (memberships.isEmpty) {
      return isPlatformAdmin
          ? MembershipSelectionStatus.platformAdminNoMemberships
          : MembershipSelectionStatus.noMemberships;
    }
    if (memberships.length == 1) {
      return MembershipSelectionStatus.autoSelected;
    }
    return activeMembership != null
        ? MembershipSelectionStatus.selected
        : MembershipSelectionStatus.pickerNeeded;
  }

  /// Returns a copy with [membershipId] selected. Fail-closed reads still apply
  /// (an unknown id yields no active membership).
  MembershipSelection select(String? membershipId) {
    return MembershipSelection(
      memberships: memberships,
      isPlatformAdmin: isPlatformAdmin,
      selectedMembershipId: membershipId,
    );
  }

  /// Clears the selection. Modeled for sign-out; no persistence in Stage 1.
  MembershipSelection cleared() => select(null);
}
