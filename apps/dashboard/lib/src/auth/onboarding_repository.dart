/// The dashboard's restaurant-onboarding seam (RF-151).
///
/// A pure-Dart interface so the onboarding UI is widget-testable with a fake; the
/// real implementation (`supabase_dashboard_auth.dart`) calls the RF-150
/// `public.create_organization` wrapper through the authenticated anon-key
/// transport. SECURITY: identity is server-derived from `auth.uid()` (the call
/// sends NO user id); outcomes carry only a safe [OnboardingErrorKind].
library;

/// A user-safe classification of an onboarding failure (the UI localizes each).
enum OnboardingErrorKind {
  /// The backend denied the request (e.g. unauthenticated/42501).
  denied,

  /// The backend could not be reached.
  network,

  /// The backend returned an unexpected/malformed response.
  invalid,

  /// Anything else (unclassified).
  unknown,
}

/// The result of a create-organization attempt.
sealed class OnboardingOutcome {
  const OnboardingOutcome();
}

/// The organization (+ first restaurant + branch + owner membership) is in place.
/// [idempotentReplay] is true when the backend returned the EXISTING tenant for a
/// retried request (RF-150 idempotency) rather than creating a new one.
class OnboardingSucceeded extends OnboardingOutcome {
  const OnboardingSucceeded({this.idempotentReplay = false});

  final bool idempotentReplay;
}

/// The attempt failed; [kind] is a safe, localizable classification.
class OnboardingFailed extends OnboardingOutcome {
  const OnboardingFailed(this.kind);

  final OnboardingErrorKind kind;
}

/// Creates the owner's first organization via `public.create_organization`.
abstract interface class OnboardingRepository {
  /// Creates the caller's organization + first restaurant + branch (+ org_owner
  /// membership) for the authenticated principal. [restaurantName] names both the
  /// organization and the restaurant; an empty [branchName] defaults to the
  /// restaurant name. The currency/timezone/slug/idempotency-key are derived by
  /// the implementation (the UI never supplies them).
  Future<OnboardingOutcome> createOrganization({
    required String restaurantName,
    String? branchName,
  });
}
