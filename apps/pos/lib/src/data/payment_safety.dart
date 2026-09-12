/// PAYMENT-ATTEMPT-RECOVERY-001 / K3-B02 + K3-B03 — the SAME-DART-ISOLATE
/// money-safety registry: activity keys, owners, participants, reservations and
/// fail-closed incidents, with compare-and-set transitions.
///
/// LIFETIME, named accurately: this is isolate-scoped in-memory state. It
/// survives store, controller, provider-container, session, scope and sheet
/// recreation. It is NOT cross-isolate and NOT cross-OS-process. A genuine
/// process restart loses every owner, reservation, participant and
/// isolate-only incident; only what the ENVELOPE holds (an active
/// `replacement_block`) survives that boundary. Process-death durability is
/// therefore NOT certified by anything in this file.
///
/// Every transition returns a NEW registry. No field is ever assigned.
library;

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;

import 'payment_attempt.dart';
import 'payment_replacement_block.dart';
import 'sync_cursor_store.dart' show PosSyncScope;

// ---------------------------------------------------------------------------
// Canonical order identity
// ---------------------------------------------------------------------------

/// The authoritative server order id, narrowed by the SAME rule the shipped
/// strict decoder applies to `order_id` — a String that is not blank after
/// trimming (`payment_attempt.dart:789-798`).
///
/// NO further grammar is imposed. Source imposes none, and a stricter rule
/// would reject ids the shipped store accepts.
@immutable
final class CanonicalOrderId {
  const CanonicalOrderId._(this.value);

  final String value;

  static CanonicalOrderId? tryFrom(Object? v) {
    if (v is! String) return null;
    if (v.trim().isEmpty) return null;
    return CanonicalOrderId._(v);
  }

  /// The association key the strict decoder RE-DERIVES and checks
  /// (`payment_attempt.dart:837-845` -> `order_identity.dart:64-76`).
  String get identityKey => 'srv:$value';

  @override
  bool operator ==(Object other) =>
      other is CanonicalOrderId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

// ---------------------------------------------------------------------------
// PaymentActivityKey — the money-safety identity
// ---------------------------------------------------------------------------

/// K3-B02. Value equality over the FULL RAW scope plus the canonical order.
///
/// It deliberately does NOT use `PosSyncScope.key`, which is lossy: that getter
/// joins the four raw fields with `.` and `.` is inside its own allowed
/// character class (`sync_cursor_store.dart:37-40`), so
/// `{org: 'acme.north', restaurant: 'r1'}` and `{org: 'acme', restaurant:
/// 'north.r1'}` produce ONE storage key from two genuinely different tills.
/// Money safety keys on the raw fields; storage keys are derived from them and
/// are not identity.
@immutable
final class PaymentActivityKey {
  const PaymentActivityKey({required this.scope, required this.orderId});

  final PosSyncScope scope;
  final CanonicalOrderId orderId;

  String get organizationId => scope.organizationId;
  String get restaurantId => scope.restaurantId;
  String get branchId => scope.branchId;
  String get deviceId => scope.deviceId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentActivityKey &&
          scope == other.scope &&
          orderId == other.orderId;

  @override
  int get hashCode => Object.hash(scope, orderId);

  @override
  String toString() =>
      'PaymentActivityKey(${scope.organizationId}/${scope.restaurantId}/'
      '${scope.branchId}/${scope.deviceId}/${orderId.value})';
}

// ---------------------------------------------------------------------------
// ExactAttemptBinding — the 17-field frozen decision identity
// ---------------------------------------------------------------------------

/// Mirrors `PaymentAttempt.describesSameDecisionAs` (`payment_attempt.dart:686-703`)
/// field for field, in source order, with value equality over all seventeen.
///
/// `supersedes` is INSIDE the identity (`:703`), so a corrected attempt that
/// points at the record it replaces is a DIFFERENT decision and the two can
/// never reconcile with each other. That is why a linked correction is a new
/// record rather than an edit.
@immutable
final class ExactAttemptBinding {
  const ExactAttemptBinding({
    required this.localOperationId,
    required this.targetId,
    required this.clientCreatedAt,
    required this.identityKey,
    required this.orderId,
    required this.orderNumber,
    required this.expectedRevision,
    required this.tenderType,
    required this.amountMinor,
    required this.amountTenderedMinor,
    required this.currencyCode,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.deviceId,
    required this.employeeProfileId,
    required this.supersedes,
  });

  factory ExactAttemptBinding.of(PaymentAttempt a) => ExactAttemptBinding(
    localOperationId: a.localOperationId,
    targetId: a.targetId,
    clientCreatedAt: a.clientCreatedAt,
    identityKey: a.identityKey,
    orderId: a.orderId,
    orderNumber: a.orderNumber,
    expectedRevision: a.expectedRevision,
    tenderType: a.tenderType,
    amountMinor: a.amountMinor,
    amountTenderedMinor: a.amountTenderedMinor,
    currencyCode: a.currencyCode,
    organizationId: a.organizationId,
    restaurantId: a.restaurantId,
    branchId: a.branchId,
    deviceId: a.deviceId,
    employeeProfileId: a.employeeProfileId,
    supersedes: a.supersedes,
  );

  final String localOperationId;
  final String targetId;
  final String clientCreatedAt;
  final String identityKey;
  final String orderId;
  final String orderNumber;
  final int? expectedRevision;
  final String tenderType;
  final int amountMinor;
  final int amountTenderedMinor;
  final String currencyCode;
  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String deviceId;
  final String? employeeProfileId;
  final String? supersedes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExactAttemptBinding &&
          localOperationId == other.localOperationId &&
          targetId == other.targetId &&
          clientCreatedAt == other.clientCreatedAt &&
          identityKey == other.identityKey &&
          orderId == other.orderId &&
          orderNumber == other.orderNumber &&
          expectedRevision == other.expectedRevision &&
          tenderType == other.tenderType &&
          amountMinor == other.amountMinor &&
          amountTenderedMinor == other.amountTenderedMinor &&
          currencyCode == other.currencyCode &&
          organizationId == other.organizationId &&
          restaurantId == other.restaurantId &&
          branchId == other.branchId &&
          deviceId == other.deviceId &&
          employeeProfileId == other.employeeProfileId &&
          supersedes == other.supersedes;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    localOperationId,
    targetId,
    clientCreatedAt,
    identityKey,
    orderId,
    orderNumber,
    expectedRevision,
    tenderType,
    amountMinor,
    amountTenderedMinor,
    currencyCode,
    organizationId,
    restaurantId,
    branchId,
    deviceId,
    employeeProfileId,
    supersedes,
  ]);
}

// ---------------------------------------------------------------------------
// Scoped tokens — never bare, never guessable across keys
// ---------------------------------------------------------------------------

int _tokenSeq = 0;

/// Every token carries the key it belongs to, so a release can never reach the
/// wrong owner. A bare opaque string could.
@immutable
final class ActivityOwnerToken {
  ActivityOwnerToken.issue(this.key) : serial = ++_tokenSeq;
  const ActivityOwnerToken.raw(this.key, this.serial);

  final PaymentActivityKey key;
  final int serial;

  @override
  bool operator ==(Object other) =>
      other is ActivityOwnerToken && key == other.key && serial == other.serial;

  @override
  int get hashCode => Object.hash(key, serial);

  @override
  String toString() => 'owner#$serial';
}

@immutable
final class ParticipantToken {
  ParticipantToken.issue(this.key) : serial = ++_tokenSeq;
  const ParticipantToken.raw(this.key, this.serial);

  final PaymentActivityKey key;
  final int serial;

  @override
  bool operator ==(Object other) =>
      other is ParticipantToken && key == other.key && serial == other.serial;

  @override
  int get hashCode => Object.hash(key, serial);

  @override
  String toString() => 'participant#$serial';
}

@immutable
final class ReservationToken {
  ReservationToken.issue(this.key) : serial = ++_tokenSeq;
  const ReservationToken.raw(this.key, this.serial);

  final PaymentActivityKey key;
  final int serial;

  @override
  bool operator ==(Object other) =>
      other is ReservationToken && key == other.key && serial == other.serial;

  @override
  int get hashCode => Object.hash(key, serial);

  @override
  String toString() => 'reservation#$serial';
}

/// A participant HANDLE carries both its own token and the owner token it was
/// admitted under, so releasing it can be validated rather than trusted. A bare
/// participant token could be replayed against a later owner.
@immutable
final class ParticipantHandle {
  const ParticipantHandle({
    required this.key,
    required this.ownerToken,
    required this.participantToken,
    required this.safetyEpoch,
  });

  final PaymentActivityKey key;
  final ActivityOwnerToken ownerToken;
  final ParticipantToken participantToken;
  final int safetyEpoch;
}

/// A reservation HANDLE additionally captures the safety epoch it was taken at,
/// which is what makes a stale promotion detectable.
@immutable
final class ReentryReservation {
  const ReentryReservation({
    required this.key,
    required this.ownerToken,
    required this.reservationToken,
    required this.capturedEpoch,
  });

  final PaymentActivityKey key;
  final ActivityOwnerToken ownerToken;
  final ReservationToken reservationToken;
  final int capturedEpoch;
}

// ---------------------------------------------------------------------------
// Owner handoff
// ---------------------------------------------------------------------------

@immutable
sealed class OwnerHandoff {
  const OwnerHandoff();

  bool get isReleasable => this is OwnerHandoffReleasable;
  bool get isFailClosed => this is OwnerHandoffFailClosed;
}

@immutable
final class OwnerHandoffReleasable extends OwnerHandoff {
  const OwnerHandoffReleasable();
}

@immutable
final class OwnerHandoffUntilHandoff extends OwnerHandoff {
  const OwnerHandoffUntilHandoff();
}

@immutable
final class OwnerHandoffFailClosed extends OwnerHandoff {
  const OwnerHandoffFailClosed(this.reason);
  final IncidentReason reason;

  @override
  bool operator ==(Object other) =>
      other is OwnerHandoffFailClosed && reason == other.reason;

  @override
  int get hashCode => Object.hash('failClosed', reason);
}

// ---------------------------------------------------------------------------
// OperationOwner
// ---------------------------------------------------------------------------

@immutable
final class OperationOwner {
  OperationOwner({
    required this.key,
    required this.ownerToken,
    required this.binding,
    required this.safetyEpoch,
    required this.handoff,
    required Set<ParticipantToken> participants,
    required Set<ReservationToken> reservations,
    required Map<ReservationToken, int> capturedEpochs,
  }) : participants = Set<ParticipantToken>.unmodifiable(participants),
       reservations = Set<ReservationToken>.unmodifiable(reservations),
       capturedEpochs = Map<ReservationToken, int>.unmodifiable(capturedEpochs);

  final PaymentActivityKey key;

  /// NON-nullable. An owner without a token cannot be compare-and-set against.
  final ActivityOwnerToken ownerToken;

  /// Null until the owner is bound to a frozen decision.
  final ExactAttemptBinding? binding;

  final int safetyEpoch;
  final OwnerHandoff handoff;
  final Set<ParticipantToken> participants;
  final Set<ReservationToken> reservations;
  final Map<ReservationToken, int> capturedEpochs;

  /// An owner disappears only when nobody is inside it AND the handoff permits.
  bool get removable =>
      participants.isEmpty && reservations.isEmpty && handoff.isReleasable;

  OperationOwner copyWith({
    ExactAttemptBinding? binding,
    int? safetyEpoch,
    OwnerHandoff? handoff,
    Set<ParticipantToken>? participants,
    Set<ReservationToken>? reservations,
    Map<ReservationToken, int>? capturedEpochs,
  }) => OperationOwner(
    key: key,
    // NEVER reassigned: the token IS the owner's identity.
    ownerToken: ownerToken,
    binding: binding ?? this.binding,
    safetyEpoch: safetyEpoch ?? this.safetyEpoch,
    handoff: handoff ?? this.handoff,
    participants: participants ?? this.participants,
    reservations: reservations ?? this.reservations,
    capturedEpochs: capturedEpochs ?? this.capturedEpochs,
  );
}

// ---------------------------------------------------------------------------
// Incidents
// ---------------------------------------------------------------------------

/// The carried three-value state. There is deliberately no `failClosed` member:
/// "fail closed" is a DISPOSITION (see [SafetyPosture]), not an incident state.
/// An incident that is blocking is `active`.
enum IncidentState { active, resolvedPendingClear, cleared }

@immutable
sealed class IncidentDurability {
  const IncidentDurability();
}

/// The block is on disk, at this occurrence.
@immutable
final class DurableRecordBlock extends IncidentDurability {
  const DurableRecordBlock(this.occurrence);
  final BlockOccurrence occurrence;
}

/// Isolate memory only — lost on process restart.
@immutable
final class IsolateLatchOnly extends IncidentDurability {
  const IsolateLatchOnly();
}

/// No record to block; only the owner holds the fail-closed fact.
@immutable
final class OwnerOnlyFailClosed extends IncidentDurability {
  const OwnerOnlyFailClosed();
}

@immutable
final class PaymentFailClosedIncident {
  PaymentFailClosedIncident({
    required this.key,
    required this.occurrence,
    required this.operationId,
    required this.binding,
    required this.serverTruth,
    required this.reason,
    required this.observedAt,
    required this.durability,
    required this.state,
    required List<ServerTruth> conflictingDiagnosticEvidence,
  }) : conflictingDiagnosticEvidence = List<ServerTruth>.unmodifiable(
         conflictingDiagnosticEvidence,
       );

  final PaymentActivityKey key;

  /// Null until a durable block exists for this incident.
  final BlockOccurrence? occurrence;

  final String operationId;
  final ExactAttemptBinding binding;
  final ServerTruth serverTruth;
  final IncidentReason reason;
  final String observedAt;
  final IncidentDurability durability;
  final IncidentState state;

  /// OD-1. Contradictory evidence is RETAINED beside the incident. It never
  /// resolves it, never clears it, and never replaces [serverTruth].
  final List<ServerTruth> conflictingDiagnosticEvidence;

  /// The accepted-class truth this incident stands on, or null.
  AcceptedTruth? get acceptedTruth {
    final t = serverTruth;
    return t is AcceptedTruth ? t : null;
  }

  PaymentFailClosedIncident copyWith({
    BlockOccurrence? occurrence,
    IncidentDurability? durability,
    IncidentState? state,
    List<ServerTruth>? conflictingDiagnosticEvidence,
  }) => PaymentFailClosedIncident(
    key: key,
    occurrence: occurrence ?? this.occurrence,
    operationId: operationId,
    binding: binding,
    serverTruth: serverTruth,
    reason: reason,
    observedAt: observedAt,
    durability: durability ?? this.durability,
    state: state ?? this.state,
    conflictingDiagnosticEvidence:
        conflictingDiagnosticEvidence ?? this.conflictingDiagnosticEvidence,
  );

  /// OD-1: an exact memoized refusal offered against an accepted/APPLIED
  /// incident is RETAINED as conflicting evidence. It does not resolve, does
  /// not clear, and does not change the recorded truth.
  PaymentFailClosedIncident withConflictingEvidence(ServerTruth t) => copyWith(
    conflictingDiagnosticEvidence: <ServerTruth>[
      ...conflictingDiagnosticEvidence,
      t,
    ],
  );
}

// ---------------------------------------------------------------------------
// Durability knowledge — tri-state
// ---------------------------------------------------------------------------

/// `_verifyDurable` answers FALSE on any doubt — no reader, a read failure,
/// absent, stale or different bytes (`payment_attempt_store.dart:713-726`). A
/// false answer is therefore NOT evidence that the previous bytes survived.
/// [verifiedOld] requires an actual proving read.
enum DurabilityKnowledge { verifiedNew, verifiedOld, unknown }

// ---------------------------------------------------------------------------
// Safety posture and identity eligibility
// ---------------------------------------------------------------------------

@immutable
sealed class SafetyPosture {
  const SafetyPosture();
}

@immutable
final class PostureClear extends SafetyPosture {
  const PostureClear();
}

@immutable
final class PostureDegraded extends SafetyPosture {
  const PostureDegraded(this.reason);
  final String reason;
}

@immutable
final class PostureFailClosed extends SafetyPosture {
  const PostureFailClosed(this.reason);
  final IncidentReason reason;

  @override
  bool operator ==(Object other) =>
      other is PostureFailClosed && reason == other.reason;

  @override
  int get hashCode => Object.hash('posture.failClosed', reason);
}

/// What a caller may allocate. Owner Option B is expressed here: a contradicted
/// acceptance yields [forbidden], and that is consulted BEFORE any
/// `local_operation_id` or provisional target is minted.
enum NewIdentityEligibility {
  /// No new identity at all.
  forbidden,

  /// Resume/re-send the SAME operation/target/idempotency identity only.
  sameAttemptOnly,

  /// A NEW decision, linked by `supersedes`.
  linkedCorrectionOnly,

  /// Nothing was allocated or sent; a clean mint is safe.
  freshMintAllowed,
}

// ---------------------------------------------------------------------------
// The registry
// ---------------------------------------------------------------------------

@immutable
final class PaymentSafetyRegistry {
  PaymentSafetyRegistry(
    Map<PaymentActivityKey, OperationOwner> owners,
    Map<PaymentActivityKey, PaymentFailClosedIncident> incidents,
  ) : owners = Map<PaymentActivityKey, OperationOwner>.unmodifiable(owners),
      incidents =
          Map<PaymentActivityKey, PaymentFailClosedIncident>.unmodifiable(
            incidents,
          );

  factory PaymentSafetyRegistry.empty() => PaymentSafetyRegistry(
    const <PaymentActivityKey, OperationOwner>{},
    const <PaymentActivityKey, PaymentFailClosedIncident>{},
  );

  final Map<PaymentActivityKey, OperationOwner> owners;
  final Map<PaymentActivityKey, PaymentFailClosedIncident> incidents;

  OperationOwner? ownerOf(PaymentActivityKey k) => owners[k];
  PaymentFailClosedIncident? incidentOf(PaymentActivityKey k) => incidents[k];

  PaymentSafetyRegistry _with({
    required PaymentActivityKey key,
    required OperationOwner? owner,
    required bool touchOwner,
    required PaymentFailClosedIncident? incident,
    required bool touchIncident,
  }) {
    final o = Map<PaymentActivityKey, OperationOwner>.of(owners);
    if (touchOwner) {
      if (owner == null) {
        o.remove(key);
      } else {
        o[key] = owner;
      }
    }
    final i = Map<PaymentActivityKey, PaymentFailClosedIncident>.of(incidents);
    if (touchIncident) {
      if (incident == null) {
        i.remove(key);
      } else {
        i[key] = incident;
      }
    }
    return PaymentSafetyRegistry(o, i);
  }
}

enum RegistryRefusalReason {
  noOwner,
  ownerTokenMismatch,
  ownerEpochMismatch,
  ownerNotFailClosed,
  ownerAlreadyPresent,
  participantUnknown,
  reservationUnknown,
  reservationStale,
  noIncident,
  incidentOccurrenceMismatch,
  incidentStateMismatch,
  incidentAlreadyPresent,
}

@immutable
sealed class SafetyRegistryTransitionResult {
  const SafetyRegistryTransitionResult();

  /// ALWAYS present: the NEXT registry, or the unchanged one on a refusal.
  PaymentSafetyRegistry get registry;
}

@immutable
final class RegistryTransitionApplied extends SafetyRegistryTransitionResult {
  const RegistryTransitionApplied(this.registry, this.owner, this.incident);

  @override
  final PaymentSafetyRegistry registry;

  final OperationOwner? owner;
  final PaymentFailClosedIncident? incident;
}

@immutable
final class RegistryTransitionRefused extends SafetyRegistryTransitionResult {
  const RegistryTransitionRefused(this.registry, this.reason);

  @override
  final PaymentSafetyRegistry registry;

  final RegistryRefusalReason reason;
}

/// Installs a fresh owner. Refuses if one already stands for [key].
SafetyRegistryTransitionResult beginOwner({
  required PaymentSafetyRegistry registry,
  required PaymentActivityKey key,
  required ActivityOwnerToken ownerToken,
  ExactAttemptBinding? binding,
}) {
  if (registry.ownerOf(key) != null) {
    return RegistryTransitionRefused(
      registry,
      RegistryRefusalReason.ownerAlreadyPresent,
    );
  }
  final owner = OperationOwner(
    key: key,
    ownerToken: ownerToken,
    binding: binding,
    safetyEpoch: 0,
    handoff: const OwnerHandoffUntilHandoff(),
    participants: const <ParticipantToken>{},
    reservations: const <ReservationToken>{},
    capturedEpochs: const <ReservationToken, int>{},
  );
  return RegistryTransitionApplied(
    registry._with(
      key: key,
      owner: owner,
      touchOwner: true,
      incident: null,
      touchIncident: false,
    ),
    owner,
    registry.incidentOf(key),
  );
}

SafetyRegistryTransitionResult replaceOwnerIfExact({
  required PaymentSafetyRegistry registry,
  required PaymentActivityKey key,
  required ActivityOwnerToken expectedOwnerToken,
  required OperationOwner nextOwner,
}) {
  final cur = registry.ownerOf(key);
  if (cur == null) {
    return RegistryTransitionRefused(registry, RegistryRefusalReason.noOwner);
  }
  if (cur.ownerToken != expectedOwnerToken ||
      nextOwner.key != key ||
      nextOwner.ownerToken != expectedOwnerToken) {
    return RegistryTransitionRefused(
      registry,
      RegistryRefusalReason.ownerTokenMismatch,
    );
  }
  return RegistryTransitionApplied(
    registry._with(
      key: key,
      owner: nextOwner,
      touchOwner: true,
      incident: null,
      touchIncident: false,
    ),
    nextOwner,
    registry.incidentOf(key),
  );
}

/// A2 admitted under the SAME owner gets its own handle. Releasing it can never
/// remove A's participation, because removal is by exact token.
({SafetyRegistryTransitionResult result, ParticipantHandle? handle})
admitParticipant({
  required PaymentSafetyRegistry registry,
  required PaymentActivityKey key,
  required ActivityOwnerToken expectedOwnerToken,
}) {
  final cur = registry.ownerOf(key);
  if (cur == null) {
    return (
      result: RegistryTransitionRefused(
        registry,
        RegistryRefusalReason.noOwner,
      ),
      handle: null,
    );
  }
  if (cur.ownerToken != expectedOwnerToken) {
    return (
      result: RegistryTransitionRefused(
        registry,
        RegistryRefusalReason.ownerTokenMismatch,
      ),
      handle: null,
    );
  }
  final token = ParticipantToken.issue(key);
  final next = cur.copyWith(
    participants: <ParticipantToken>{...cur.participants, token},
  );
  return (
    result: RegistryTransitionApplied(
      registry._with(
        key: key,
        owner: next,
        touchOwner: true,
        incident: null,
        touchIncident: false,
      ),
      next,
      registry.incidentOf(key),
    ),
    handle: ParticipantHandle(
      key: key,
      ownerToken: expectedOwnerToken,
      participantToken: token,
      safetyEpoch: cur.safetyEpoch,
    ),
  );
}

/// Removes ONLY the named participant, and only under the owner it was admitted
/// to. The owner is retained while anyone else remains inside it.
SafetyRegistryTransitionResult releaseParticipant({
  required PaymentSafetyRegistry registry,
  required ParticipantHandle handle,
}) {
  final key = handle.key;
  final cur = registry.ownerOf(key);
  if (cur == null) {
    return RegistryTransitionRefused(registry, RegistryRefusalReason.noOwner);
  }
  if (cur.ownerToken != handle.ownerToken) {
    return RegistryTransitionRefused(
      registry,
      RegistryRefusalReason.ownerTokenMismatch,
    );
  }
  if (!cur.participants.contains(handle.participantToken)) {
    return RegistryTransitionRefused(
      registry,
      RegistryRefusalReason.participantUnknown,
    );
  }
  final remaining = <ParticipantToken>{...cur.participants}
    ..remove(handle.participantToken);
  final next = cur.copyWith(participants: remaining);
  // The owner disappears only when nobody is inside it AND the handoff permits.
  final keep = !next.removable;
  return RegistryTransitionApplied(
    registry._with(
      key: key,
      owner: keep ? next : null,
      touchOwner: true,
      incident: null,
      touchIncident: false,
    ),
    keep ? next : null,
    registry.incidentOf(key),
  );
}

/// Takes a re-entry reservation, capturing the CURRENT safety epoch.
({SafetyRegistryTransitionResult result, ReentryReservation? reservation})
reserveSameAttempt({
  required PaymentSafetyRegistry registry,
  required PaymentActivityKey key,
  required ActivityOwnerToken expectedOwnerToken,
}) {
  final cur = registry.ownerOf(key);
  if (cur == null) {
    return (
      result: RegistryTransitionRefused(
        registry,
        RegistryRefusalReason.noOwner,
      ),
      reservation: null,
    );
  }
  if (cur.ownerToken != expectedOwnerToken) {
    return (
      result: RegistryTransitionRefused(
        registry,
        RegistryRefusalReason.ownerTokenMismatch,
      ),
      reservation: null,
    );
  }
  final token = ReservationToken.issue(key);
  final next = cur.copyWith(
    reservations: <ReservationToken>{...cur.reservations, token},
    capturedEpochs: <ReservationToken, int>{
      ...cur.capturedEpochs,
      token: cur.safetyEpoch,
    },
  );
  return (
    result: RegistryTransitionApplied(
      registry._with(
        key: key,
        owner: next,
        touchOwner: true,
        incident: null,
        touchIncident: false,
      ),
      next,
      registry.incidentOf(key),
    ),
    reservation: ReentryReservation(
      key: key,
      ownerToken: expectedOwnerToken,
      reservationToken: token,
      capturedEpoch: cur.safetyEpoch,
    ),
  );
}

/// A reservation may promote ONLY while the safety epoch it captured still
/// stands. Entering a fail-closed state bumps the epoch, so a reservation taken
/// before it can never promote afterwards.
({SafetyRegistryTransitionResult result, ParticipantHandle? handle})
promoteReservation({
  required PaymentSafetyRegistry registry,
  required ReentryReservation reservation,
}) {
  final key = reservation.key;
  final cur = registry.ownerOf(key);
  if (cur == null) {
    return (
      result: RegistryTransitionRefused(
        registry,
        RegistryRefusalReason.noOwner,
      ),
      handle: null,
    );
  }
  if (cur.ownerToken != reservation.ownerToken) {
    return (
      result: RegistryTransitionRefused(
        registry,
        RegistryRefusalReason.ownerTokenMismatch,
      ),
      handle: null,
    );
  }
  if (!cur.reservations.contains(reservation.reservationToken)) {
    return (
      result: RegistryTransitionRefused(
        registry,
        RegistryRefusalReason.reservationUnknown,
      ),
      handle: null,
    );
  }
  if (cur.safetyEpoch != reservation.capturedEpoch ||
      cur.handoff.isFailClosed) {
    return (
      result: RegistryTransitionRefused(
        registry,
        RegistryRefusalReason.reservationStale,
      ),
      handle: null,
    );
  }
  final token = ParticipantToken.issue(key);
  final remaining = <ReservationToken>{...cur.reservations}
    ..remove(reservation.reservationToken);
  final epochs = <ReservationToken, int>{...cur.capturedEpochs}
    ..remove(reservation.reservationToken);
  final next = cur.copyWith(
    reservations: remaining,
    capturedEpochs: epochs,
    participants: <ParticipantToken>{...cur.participants, token},
  );
  return (
    result: RegistryTransitionApplied(
      registry._with(
        key: key,
        owner: next,
        touchOwner: true,
        incident: null,
        touchIncident: false,
      ),
      next,
      registry.incidentOf(key),
    ),
    handle: ParticipantHandle(
      key: key,
      ownerToken: reservation.ownerToken,
      participantToken: token,
      safetyEpoch: next.safetyEpoch,
    ),
  );
}

/// Enters the fail-closed state: the epoch is BUMPED, so every reservation
/// taken before this instant is now stale and can never promote.
SafetyRegistryTransitionResult enterOwnerFailClosed({
  required PaymentSafetyRegistry registry,
  required PaymentActivityKey key,
  required ActivityOwnerToken expectedOwnerToken,
  required IncidentReason reason,
}) {
  final cur = registry.ownerOf(key);
  if (cur == null) {
    return RegistryTransitionRefused(registry, RegistryRefusalReason.noOwner);
  }
  if (cur.ownerToken != expectedOwnerToken) {
    return RegistryTransitionRefused(
      registry,
      RegistryRefusalReason.ownerTokenMismatch,
    );
  }
  final next = cur.copyWith(
    safetyEpoch: cur.safetyEpoch + 1,
    handoff: OwnerHandoffFailClosed(reason),
  );
  return RegistryTransitionApplied(
    registry._with(
      key: key,
      owner: next,
      touchOwner: true,
      incident: null,
      touchIncident: false,
    ),
    next,
    registry.incidentOf(key),
  );
}

SafetyRegistryTransitionResult installIncidentIfAbsent({
  required PaymentSafetyRegistry registry,
  required PaymentActivityKey key,
  required PaymentFailClosedIncident incident,
}) {
  if (registry.incidentOf(key) != null) {
    return RegistryTransitionRefused(
      registry,
      RegistryRefusalReason.incidentAlreadyPresent,
    );
  }
  return RegistryTransitionApplied(
    registry._with(
      key: key,
      owner: null,
      touchOwner: false,
      incident: incident,
      touchIncident: true,
    ),
    registry.ownerOf(key),
    incident,
  );
}

/// Compare-and-set on the incident's CURRENT occurrence.
///
/// [expectedOccurrence] is NULLABLE, and must be: a first promotion runs while
/// the incident has no durable block yet, so a non-nullable expectation could
/// never match there.
SafetyRegistryTransitionResult replaceIncidentIfExact({
  required PaymentSafetyRegistry registry,
  required PaymentActivityKey key,
  required BlockOccurrence? expectedOccurrence,
  required PaymentFailClosedIncident nextIncident,
}) {
  final cur = registry.incidentOf(key);
  if (cur == null) {
    return RegistryTransitionRefused(
      registry,
      RegistryRefusalReason.noIncident,
    );
  }
  if (cur.occurrence != expectedOccurrence || nextIncident.key != key) {
    return RegistryTransitionRefused(
      registry,
      RegistryRefusalReason.incidentOccurrenceMismatch,
    );
  }
  return RegistryTransitionApplied(
    registry._with(
      key: key,
      owner: null,
      touchOwner: false,
      incident: nextIncident,
      touchIncident: true,
    ),
    registry.ownerOf(key),
    nextIncident,
  );
}

/// The ATOMIC post-proof release. Verifies key, owner token, incident
/// occurrence, safety epoch and handoff state TOGETHER, then returns ONE next
/// registry in which only this incident is cleared and only this owner's
/// fail-closed handoff is released.
///
/// `resolvedPendingClear` is entered and left inside this function, so no
/// caller can observe an incident that is resolved but not yet cleared.
SafetyRegistryTransitionResult clearIncidentAndReleaseOwnerIfExact({
  required PaymentSafetyRegistry registry,
  required PaymentActivityKey key,
  required ActivityOwnerToken expectedOwnerToken,
  required BlockOccurrence expectedOccurrence,
  required int expectedSafetyEpoch,
}) {
  final incident = registry.incidentOf(key);
  if (incident == null) {
    return RegistryTransitionRefused(
      registry,
      RegistryRefusalReason.noIncident,
    );
  }
  if (incident.state != IncidentState.active) {
    return RegistryTransitionRefused(
      registry,
      RegistryRefusalReason.incidentStateMismatch,
    );
  }
  if (incident.occurrence != expectedOccurrence) {
    return RegistryTransitionRefused(
      registry,
      RegistryRefusalReason.incidentOccurrenceMismatch,
    );
  }

  final owner = registry.ownerOf(key);
  if (owner == null) {
    return RegistryTransitionRefused(registry, RegistryRefusalReason.noOwner);
  }
  if (owner.ownerToken != expectedOwnerToken) {
    return RegistryTransitionRefused(
      registry,
      RegistryRefusalReason.ownerTokenMismatch,
    );
  }
  if (owner.safetyEpoch != expectedSafetyEpoch) {
    return RegistryTransitionRefused(
      registry,
      RegistryRefusalReason.ownerEpochMismatch,
    );
  }
  if (!owner.handoff.isFailClosed) {
    return RegistryTransitionRefused(
      registry,
      RegistryRefusalReason.ownerNotFailClosed,
    );
  }

  final released = owner.copyWith(handoff: const OwnerHandoffReleasable());
  // An owner still holding participants or reservations is NOT removed: the
  // handoff is released, and the owner disappears when the last one leaves.
  final nextOwner = released.removable ? null : released;
  return RegistryTransitionApplied(
    registry._with(
      key: key,
      owner: nextOwner,
      touchOwner: true,
      incident: null,
      touchIncident: true,
    ),
    nextOwner,
    null,
  );
}

// ---------------------------------------------------------------------------
// The isolate-scoped registry instance
// ---------------------------------------------------------------------------

/// ONE registry per Dart isolate, for the same reason the payment key guard is
/// isolate-scoped: the untrustworthy thing is the KEY, not one Dart object. It
/// survives store, controller, provider-container, session and sheet
/// recreation, and it does NOT survive a process restart.
PaymentSafetyRegistry _isolateRegistry = PaymentSafetyRegistry.empty();

PaymentSafetyRegistry paymentSafetyRegistry() => _isolateRegistry;

/// The outcome of a KEY-SCOPED commit against the live isolate registry.
@immutable
sealed class SafetyCommitResult {
  const SafetyCommitResult();
}

@immutable
final class SafetyCommitApplied extends SafetyCommitResult {
  const SafetyCommitApplied(this.registry, this.owner, this.incident);

  /// The registry now installed.
  final PaymentSafetyRegistry registry;
  final OperationOwner? owner;
  final PaymentFailClosedIncident? incident;
}

@immutable
final class SafetyCommitRefused extends SafetyCommitResult {
  const SafetyCommitRefused(this.reason);
  final RegistryRefusalReason reason;
}

/// Applies ONE activity key's transition to the registry that is LIVE at this
/// instant, and installs the result.
///
/// THIS IS THE ONLY WAY PRODUCTION MAY MUTATE THE ISOLATE REGISTRY, and the
/// shape is the point.
///
/// The API it replaces took a whole `PaymentSafetyRegistry` and assigned it:
///
///     commitPaymentSafetyRegistry(promotion.registry);
///
/// Every caller of that had, of necessity, obtained its value BEFORE a long
/// await — a durable write, a bounded read retry — because that is what the
/// transition needed. Installing it afterwards published a map of the whole
/// isolate as it had looked before the await, so any owner or incident that
/// ANOTHER PaymentActivityKey committed during that window was silently
/// deleted. On this device that is not a bookkeeping slip: an order whose only
/// containment was an isolate latch lost it, hydrated `SafetyClear`, and minted
/// a second payment identity for money that had already moved.
///
/// Here the registry is re-read at the moment of the swap, and the window
/// between that read and the assignment is synchronous BY CONSTRUCTION:
/// [transition] returns a value, not a future, so no continuation can
/// interleave and no await can hide inside it. Because every transition derives
/// its next registry from the one it is handed (see `_with`, which copies the
/// maps it is given and touches a single key), passing the live registry means
/// every unrelated key is carried across untouched.
///
/// The transition itself still decides whether the target key is in the state
/// the caller expected — that is the compare — so a key another writer has
/// moved is REFUSED here rather than overwritten.
SafetyCommitResult commitSafetyTransition(
  SafetyRegistryTransitionResult Function(PaymentSafetyRegistry live)
  transition,
) {
  final live = _isolateRegistry;
  final t = transition(live);
  if (t is RegistryTransitionRefused) return SafetyCommitRefused(t.reason);
  final applied = t as RegistryTransitionApplied;
  _isolateRegistry = applied.registry;
  return SafetyCommitApplied(applied.registry, applied.owner, applied.incident);
}

@visibleForTesting
void resetPaymentSafetyRegistryForTest() {
  _isolateRegistry = PaymentSafetyRegistry.empty();
}
