/// Non-web targets: there is no launch URL to carry a handoff, so support mode
/// is never entered here. Returning null is the honest answer, not a fallback.
String? takeSupportHandoff() => null;
