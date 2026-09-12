import 'dart:async';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/ids.dart';
import '../data/order_identity.dart';
import '../data/payment.dart';
import '../data/payment_attempt.dart';
import '../data/payment_attempt_store.dart';
import '../data/payment_replacement_block.dart';
import '../data/payment_safety.dart';
import '../data/payment_repository.dart';
import '../data/sync_cursor_store.dart'
    show PosPersistenceException, PosSyncScope;
import 'order_sync_controller.dart' show posSyncClockProvider;
import 'pos_session.dart';
import 'pos_sync_scope_provider.dart';

/// TEST-ONLY. Awaited inside `_reconcileAcceptedSafetyEvidence` after exact
/// evidence has been classified and BEFORE any safety state is committed.
///
/// It exists because the race OD-2 is about — a provider rebuild landing while
/// containment is being established — is otherwise not deterministically
/// reachable from a test, and a race test that cannot be made to fail proves
/// nothing. Null in production, where the barrier costs one null check.
@visibleForTesting
Future<void> Function()? debugPaymentSafetyCommitBarrier;

/// S1-R4 / F004e — the two truths a cashier must keep being told about one
/// attempt, when the device could not write them down.
///
/// The server's refusal is EXACT and is preserved as itself; the failed local
/// save is a SEPARATE fact beside it. R3 kept only a widget field, so closing
/// and reopening the sheet — or rebuilding the provider — silently dropped
/// both, and the cashier was shown a clean tender form for an order the server
/// had already refused.
class PaymentAttemptDisclosure {
  const PaymentAttemptDisclosure({
    required this.refusalCode,
    required this.localSaveFailed,
    this.localOperationId,
  });

  /// The exact refusal the server gave for THIS attempt, or null when the
  /// disclosure is only about storage.
  final PaymentRefusalCode? refusalCode;

  /// Whether the write that would have recorded that answer did not stick.
  final bool localSaveFailed;

  /// S1-R5 / F004 — the OPERATION this disclosure is about.
  ///
  /// Bound so that a rebuilt controller can drop a disclosure left by an
  /// operation the current record has already superseded, instead of showing
  /// an old refusal over a newer accepted payment for the same order.
  final String? localOperationId;

  bool get isEmpty => refusalCode == null && !localSaveFailed;
}

/// S1-R4 / F004e — the isolate-scoped, scope-bound observation register.
///
/// Deliberately NOT durable: the very thing being disclosed is that durable
/// storage refused the write, so writing the warning into that store and
/// claiming it survived would be circular. It lives for the process, keyed by
/// sync scope and attempt identity, so a rebuilt controller, a replaced
/// provider and a recreated sheet all see the same two truths — while a
/// different scope sees nothing. A real process restart loses it, which is
/// stated rather than papered over: after that only verified backing or an
/// authorized passive check can speak.
final Map<String, PaymentAttemptDisclosure> _paymentDisclosures =
    <String, PaymentAttemptDisclosure>{};

/// S1-R5 / F004 — the register key is bound to PHYSICAL NAMESPACE + ACTOR +
/// ORDER, and the stored value additionally names its OPERATION.
///
/// R4 keyed on sync scope plus order identity only. Two consequences were
/// proved: a second cashier signing in on the SAME authorized till inherited
/// the first cashier's exact refusal and failed-save banners, and an obsolete
/// operation could write into the context of a newer accepted one. The scope
/// key alone also named a logical scope rather than the physical key the
/// evidence actually lives under, so this now reuses the store's own boundary
/// name — the single place that decides which bytes are which.
String _disclosureActorPrefix(PosSyncScope scope, String? actor) =>
    '${paymentAttemptGuardKey(paymentAttemptsPhysicalKey(scope.key))}'
    '|${actor?.trim() ?? ''}|';

String _disclosureKey(PosSyncScope scope, String? actor, String identityKey) =>
    '${_disclosureActorPrefix(scope, actor)}$identityKey';

/// TEST ONLY: clears the in-process disclosure register.
@visibleForTesting
void resetPaymentDisclosuresForTest() => _paymentDisclosures.clear();

/// Immutable POS payment state (RF-116): the live shift / cash-drawer context plus
/// the recorded cash payments, keyed by ORDER IDENTITY.
///
/// POS-OPERATIONS-SYNC-001 (second review correction): this map was keyed by the
/// DISPLAY code. Two orders sharing a `#XXXXXX` therefore shared one entry, so paying
/// one of them marked BOTH paid — the second order's payment button disappeared, its
/// receipt showed the other order's money, and the till's takings were wrong by a whole
/// order. The key is now [PosOrderIdentity]: the server's order id where it exists,
/// this device's own operation id before that, and never the code.
///
/// PAYMENT-ATTEMPT-RECOVERY-001 adds the durable ATTEMPTS: the latest
/// [PaymentAttempt] per order identity (any phase) hydrated from the per-scope
/// store, plus the records this build could not read.
class PaymentState {
  const PaymentState({
    required this.shift,
    required this.payments,
    this.attempts = const {},
    this.quarantined = const [],
    this.hydrated = true,
    this.effectsArmed = const {},
    this.disclosures = const {},
  });

  final ShiftContext shift;

  /// Keyed by [PosOrderIdentity.key] — NEVER by `orderNumber`.
  final Map<String, CashPayment> payments;

  /// The LATEST durable attempt per [PosOrderIdentity.key] (pending or
  /// resolved), from this scope's store.
  final Map<String, PaymentAttempt> attempts;

  /// Stored attempt records this build cannot read (kept on disk, reported).
  final List<PaymentAttemptQuarantine> quarantined;

  /// False until the durable store has been read for the current scope. No
  /// NEW attempt may start before that: an unread store could hold an
  /// unresolved one for the same order.
  final bool hydrated;

  /// PAYMENT-ATTEMPT-RECOVERY-001: the order identity keys whose AUTOMATIC
  /// receipt/drawer triggers were armed by THIS process — i.e. the durable
  /// one-time reservation was written here, on a real acceptance edge.
  ///
  /// An observer of [payments] alone cannot tell a real payment edge from a
  /// payment that merely APPEARED because the durable store was hydrated
  /// after a restart or a session change. Firing paper on the second is how a
  /// recovered payment prints twice, so every automatic effect asks this set.
  final Set<String> effectsArmed;

  /// S1-R4 / F004e — the two truths still owed to the cashier for an attempt
  /// whose answer could not be written down, keyed by [PosOrderIdentity.key].
  final Map<String, PaymentAttemptDisclosure> disclosures;

  /// Whether THIS process armed [identity]'s one-time automatic effects.
  bool effectsArmedFor(PosOrderIdentity identity) =>
      effectsArmed.contains(identity.key);

  /// The outstanding disclosure for [identity], or null.
  PaymentAttemptDisclosure? disclosureFor(PosOrderIdentity identity) =>
      disclosures[identity.key];

  /// The payment recorded for [identity] this session, or null.
  CashPayment? paymentFor(PosOrderIdentity identity) => payments[identity.key];

  /// The UNRESOLVED attempt for [identity], or null.
  PaymentAttempt? pendingAttemptFor(PosOrderIdentity identity) {
    final a = attempts[identity.key];
    return a != null && a.isPending ? a : null;
  }

  /// Whether a stored record this build cannot read may concern [orderId].
  bool quarantineBlocks(String orderId) =>
      quarantined.any((q) => q.blocks(orderId));

  PaymentState copyWith({
    ShiftContext? shift,
    Map<String, CashPayment>? payments,
    Map<String, PaymentAttempt>? attempts,
    List<PaymentAttemptQuarantine>? quarantined,
    bool? hydrated,
    Set<String>? effectsArmed,
    Map<String, PaymentAttemptDisclosure>? disclosures,
  }) => PaymentState(
    shift: shift ?? this.shift,
    payments: payments ?? this.payments,
    attempts: attempts ?? this.attempts,
    quarantined: quarantined ?? this.quarantined,
    hydrated: hydrated ?? this.hydrated,
    effectsArmed: effectsArmed ?? this.effectsArmed,
    disclosures: disclosures ?? this.disclosures,
  );
}

/// PAYMENT-ATTEMPT-RECOVERY-001 — the typed outcome of ONE [PaymentController]
/// submit/resume. Exactly one shape; the cashier-facing sheet keys its
/// wording and its next actions on it and never on an exception message.
sealed class PaymentAttemptOutcome {
  const PaymentAttemptOutcome();
}

/// The server applied THIS attempt (or replayed its applied result).
class PaymentAttemptAccepted extends PaymentAttemptOutcome {
  const PaymentAttemptAccepted({
    required this.attempt,
    required this.payment,
    required this.replay,
    required this.automaticEffectsArmed,
    required this.localSaveFailed,
  });

  final PaymentAttempt attempt;
  final CashPayment payment;

  /// The acceptance came back as an idempotency replay (a resume).
  final bool replay;

  /// TRUE exactly once per attempt: the durable effect reservation was written
  /// in THIS call, so the caller may fire the automatic receipt/drawer
  /// triggers. False on every later replay, and when the reservation could
  /// not be persisted (then the physical outcome is honestly unknown and the
  /// manual reprint path stands).
  final bool automaticEffectsArmed;

  /// The server accepted but the local resolution could not be saved. The
  /// payment is REAL; the order is paid; the record stays `pending` on disk
  /// and resolves again (as a replay) on the next resume.
  final bool localSaveFailed;
}

/// A definitive refusal of THIS attempt. The order may still owe money; a
/// corrected attempt is a NEW cashier decision (new identity, linked).
class PaymentAttemptRefused extends PaymentAttemptOutcome {
  const PaymentAttemptRefused({
    required this.attempt,
    required this.code,
    this.localSaveFailed = false,
  });
  final PaymentAttempt attempt;
  final PaymentRefusalCode code;

  /// S1-R3 / F004 — TWO INDEPENDENT TRUTHS, both told.
  ///
  /// The server's refusal is exact and stays exact: it is memoized in the
  /// operation ledger and replays for this key. But when the local write that
  /// records it does not stick, this device's own record is NOT the refusal it
  /// is showing. The R2 build swallowed that failure and returned a plain
  /// refusal, so the cashier saw a settled-looking outcome backed by nothing
  /// on disk. Relabelling the refusal as unconfirmed would be the opposite
  /// error — it would deny a refusal the server really made. Both facts are
  /// carried here and both are shown.
  final bool localSaveFailed;
}

/// THIS attempt was refused AND the order is settled — by another attempt or
/// another till. Not our payment: no receipt, no drawer, no second tender.
class PaymentAttemptSettledElsewhere extends PaymentAttemptOutcome {
  const PaymentAttemptSettledElsewhere(this.attempt);
  final PaymentAttempt attempt;
}

/// Sent; outcome unknown. The attempt stays durable; check or resume it.
class PaymentAttemptUnconfirmed extends PaymentAttemptOutcome {
  const PaymentAttemptUnconfirmed({
    required this.attempt,
    required this.reason,
  });
  final PaymentAttempt attempt;
  final PaymentUnconfirmedReason reason;
}

/// The transport proved the request did not commit; resume the same attempt.
class PaymentAttemptNotApplied extends PaymentAttemptOutcome {
  const PaymentAttemptNotApplied(this.attempt);
  final PaymentAttempt attempt;
}

/// The session was refused; sign in again, then resume the SAME attempt.
class PaymentAttemptAuthRequired extends PaymentAttemptOutcome {
  const PaymentAttemptAuthRequired(this.attempt);
  final PaymentAttempt attempt;
}

/// The attempt could not be durably saved. NOTHING was sent.
class PaymentAttemptSaveBlocked extends PaymentAttemptOutcome {
  const PaymentAttemptSaveBlocked();
}

/// A send for this order is already in flight; nothing new was sent.
class PaymentAttemptBusy extends PaymentAttemptOutcome {
  const PaymentAttemptBusy(this.attempt);
  final PaymentAttempt? attempt;
}

/// An earlier UNRESOLVED attempt with DIFFERENT inputs exists for this order.
/// Nothing was sent; it must be resolved first.
class PaymentAttemptUnresolved extends PaymentAttemptOutcome {
  const PaymentAttemptUnresolved(this.attempt);
  final PaymentAttempt attempt;
}

/// The unresolved attempt was started by another cashier. Only they may
/// resume it; anyone permitted may check its status. Nothing was sent.
class PaymentAttemptOtherActor extends PaymentAttemptOutcome {
  const PaymentAttemptOtherActor(this.attempt);
  final PaymentAttempt attempt;
}

/// A stored attempt that may concern this order cannot be read. Nothing sent.
class PaymentAttemptQuarantined extends PaymentAttemptOutcome {
  const PaymentAttemptQuarantined();
}

/// PDR-003 — no authoritative order revision, so no recoverable real attempt
/// may be created or re-sent. Nothing was minted, stored or sent.
///
/// `record_payment` checks the revision only when one is supplied, so an
/// attempt built without one carries no optimistic-concurrency binding at all:
/// the cashier could be looking at a total the order no longer has. The order
/// must be refreshed before money is taken.
class PaymentAttemptRevisionRequired extends PaymentAttemptOutcome {
  const PaymentAttemptRevisionRequired();
}

/// PDR-007 — no identifiable cashier, so no recoverable real attempt may be
/// created. Nothing was minted, stored or sent.
///
/// An attempt minted without a non-empty actor could never be resumed by
/// anyone afterwards, because a resume requires two non-empty identities that
/// match. Refusing at the start is honest; minting a record nobody can ever
/// recover is a trap.
class PaymentAttemptActorRequired extends PaymentAttemptOutcome {
  const PaymentAttemptActorRequired();
}

/// K3-B06 — WHAT HAPPENED TO THE MONEY, as a first-class axis.
///
/// Kept SEPARATE from the safety disposition ([SafetyPosture]): a storage
/// failure degrades safety, it does not erase a server truth this device
/// already knows. The two are reported side by side, never collapsed.
enum MoneyTruthView {
  /// The money moved and this device can prove it.
  moved,

  /// The money moved; this device's durable record is NOT the proof.
  movedUnproven,

  /// Genuinely unknown. Never collect again without checking.
  mayHaveMoved,

  /// Proven not taken.
  didNotMove,

  /// No request left this device.
  nothingSent,
}

/// TOTAL over every [PaymentAttemptOutcome]. The analyzer proves exhaustiveness
/// because the class is sealed.
MoneyTruthView moneyTruthOf(PaymentAttemptOutcome o) => switch (o) {
  PaymentAttemptAccepted(:final localSaveFailed) =>
    localSaveFailed ? MoneyTruthView.movedUnproven : MoneyTruthView.moved,

  // The server's refusal is exact and memoized for this key. A failed local
  // write is a SEPARATE fact the variant already carries separately;
  // downgrading here would deny a refusal the server really made.
  PaymentAttemptRefused() => MoneyTruthView.didNotMove,
  PaymentAttemptSettledElsewhere() => MoneyTruthView.didNotMove,
  PaymentAttemptNotApplied() => MoneyTruthView.didNotMove,

  PaymentAttemptUnconfirmed() => MoneyTruthView.mayHaveMoved,
  PaymentAttemptAuthRequired() => MoneyTruthView.mayHaveMoved,
  PaymentAttemptUnresolved() => MoneyTruthView.mayHaveMoved,
  PaymentAttemptOtherActor() => MoneyTruthView.mayHaveMoved,

  // An unreadable stored attempt may be a SENT one.
  PaymentAttemptQuarantined() => MoneyTruthView.mayHaveMoved,

  // Nothing NEW was sent, but the in-flight send may already have moved money.
  PaymentAttemptBusy() => MoneyTruthView.mayHaveMoved,

  PaymentAttemptSaveBlocked() => MoneyTruthView.nothingSent,
  PaymentAttemptRevisionRequired() => MoneyTruthView.nothingSent,
  PaymentAttemptActorRequired() => MoneyTruthView.nothingSent,
};

/// K3-B06 — what a caller may allocate after [o]. TOTAL over the thirteen.
NewIdentityEligibility eligibilityOf(PaymentAttemptOutcome o) => switch (o) {
  // Already settled by THIS device's attempt: nothing to send, no new identity.
  PaymentAttemptAccepted() => NewIdentityEligibility.forbidden,

  // "Not our payment: no receipt, no drawer, NO SECOND TENDER."
  PaymentAttemptSettledElsewhere() => NewIdentityEligibility.forbidden,

  // A corrected attempt is a NEW cashier decision, LINKED to the old one.
  PaymentAttemptRefused() => NewIdentityEligibility.linkedCorrectionOnly,

  // "The transport proved the request did not commit; RESUME THE SAME
  // ATTEMPT." Minting a second identity would abandon a key the server can
  // still replay.
  PaymentAttemptNotApplied() => NewIdentityEligibility.sameAttemptOnly,

  // "Sign in again, then resume the SAME attempt."
  PaymentAttemptAuthRequired() => NewIdentityEligibility.sameAttemptOnly,

  // Owner Option B: no new identity while the outcome is unresolved.
  PaymentAttemptUnconfirmed() => NewIdentityEligibility.forbidden,

  // A send for this order is ALREADY IN FLIGHT.
  PaymentAttemptBusy() => NewIdentityEligibility.forbidden,

  PaymentAttemptUnresolved() => NewIdentityEligibility.forbidden,
  PaymentAttemptOtherActor() => NewIdentityEligibility.forbidden,
  PaymentAttemptQuarantined() => NewIdentityEligibility.forbidden,

  // Nothing was minted, stored or sent.
  PaymentAttemptSaveBlocked() => NewIdentityEligibility.freshMintAllowed,
  PaymentAttemptRevisionRequired() => NewIdentityEligibility.freshMintAllowed,
  PaymentAttemptActorRequired() => NewIdentityEligibility.freshMintAllowed,
};

/// A status check is READ-ONLY, so it may carry no outcome at all. Money is
/// ALWAYS derived from the outcome through [moneyTruthOf], so this can never
/// contradict it, and the standing safety posture is passed IN rather than
/// assumed clear.
@immutable
class StatusCheckReading {
  const StatusCheckReading({
    required this.outcome,
    required this.money,
    required this.safety,
    required this.eligibility,
  });

  final PaymentAttemptOutcome? outcome;
  final MoneyTruthView money;
  final SafetyPosture safety;
  final NewIdentityEligibility eligibility;
}

/// TOTAL over the four [PaymentAttemptStatusCheck] variants.
///
/// `StatusNothingPending` is a statement about the LEDGER, not a mint
/// authorisation: it publishes no outcome and defers eligibility to the
/// authoritative attempt/safety state.
StatusCheckReading readStatusCheck(
  PaymentAttemptStatusCheck c,
  SafetyPosture standingPosture,
  NewIdentityEligibility fromAuthoritativeState,
) => switch (c) {
  PaymentAttemptStatusResolved(:final outcome) => StatusCheckReading(
    outcome: outcome,
    money: moneyTruthOf(outcome),
    safety: standingPosture,
    eligibility: eligibilityOf(outcome),
  ),
  PaymentAttemptStatusStillPending(:final attempt) => StatusCheckReading(
    outcome: PaymentAttemptUnconfirmed(
      attempt: attempt,
      reason: PaymentUnconfirmedReason.transport,
    ),
    money: MoneyTruthView.mayHaveMoved,
    safety: standingPosture,
    eligibility: NewIdentityEligibility.forbidden,
  ),
  PaymentAttemptStatusCheckUnavailable() => StatusCheckReading(
    outcome: null,
    money: MoneyTruthView.mayHaveMoved,
    safety: standingPosture,
    eligibility: NewIdentityEligibility.forbidden,
  ),
  PaymentAttemptStatusNothingPending() => StatusCheckReading(
    outcome: null,
    money: MoneyTruthView.nothingSent,
    safety: standingPosture,
    eligibility: fromAuthoritativeState,
  ),
};

/// The READ-ONLY status check's answer for the cashier.
sealed class PaymentAttemptStatusCheck {
  const PaymentAttemptStatusCheck();
}

/// The ledger answered; the attempt is now resolved (see [outcome]).
class PaymentAttemptStatusResolved extends PaymentAttemptStatusCheck {
  const PaymentAttemptStatusResolved(this.outcome);
  final PaymentAttemptOutcome outcome;
}

/// The ledger has no row for the attempt and the order still owes money:
/// the original request may still be pending. Do not collect again.
class PaymentAttemptStatusStillPending extends PaymentAttemptStatusCheck {
  const PaymentAttemptStatusStillPending(this.attempt);
  final PaymentAttempt attempt;
}

/// The status could not be read right now.
class PaymentAttemptStatusCheckUnavailable extends PaymentAttemptStatusCheck {
  const PaymentAttemptStatusCheckUnavailable(this.reason);
  final String reason;
}

/// Nothing to check: there is no pending attempt for the order.
class PaymentAttemptStatusNothingPending extends PaymentAttemptStatusCheck {
  const PaymentAttemptStatusNothingPending();
}

/// Records cash payments and exposes the demo shift/cash-drawer context
/// (RF-116). Recording a payment rolls the order amount into the drawer and
/// refreshes the context. In-memory demo only — no backend, no printer.
///
/// PAYMENT-ATTEMPT-RECOVERY-001 (real mode): ONE durable business attempt per
/// cashier decision. [submitAttempt] freezes the inputs synchronously, holds a
/// per-order single-flight guard, adopts an existing pending attempt for the
/// order (same decision => RESUME under the same identity; different decision
/// => refuse to send), persists a new attempt BEFORE the first send, and
/// resolves it only from the server's answer. Nothing here retries in the
/// background, mints a second identity while one is unresolved, or issues a
/// payment on boot.
class PaymentController extends Notifier<PaymentState> {
  late PaymentRepository _repo;
  final Set<String> _inFlight = <String>{};
  int _generation = 0;
  Future<void>? _hydration;

  /// The clock and id source, CAPTURED IN `build`, for the OD-2 safety path.
  ///
  /// `ref` is only legal while a provider is building or settled. Riverpod has a
  /// third state — a watched dependency has CHANGED but the provider has not
  /// rebuilt yet — in which every `ref` function throws
  /// `'!_didChangeDependency': Cannot use ref functions after the dependency of
  /// a provider changed but before the provider rebuilt`, and `_generation` has
  /// NOT moved, so `_stillAuthoritative` still answers true. That window
  /// survives microtask AND macrotask boundaries until something flushes the
  /// element, so an awaited send can easily land inside it — which is exactly
  /// the "the provider is being rebuilt mid-payment" case OD-2 exists for.
  ///
  /// Reading `ref` there would have thrown straight out of the containment
  /// path, losing the incident, the durable block AND the caller's money
  /// outcome. These are read once in `build`, where `ref` is always legal.
  late DateTime Function() _safetyClock;
  late ClientIdGenerator _safetyIds;

  @override
  PaymentState build() {
    _repo = ref.watch(paymentRepositoryProvider);
    final store = ref.watch(paymentAttemptStoreProvider);
    final scope = ref.watch(posSyncScopeProvider);
    // A rebuild is a NEW WORLD (session / scope / repository changed): every
    // late callback from the previous one must leave this state alone.
    final gen = ++_generation;
    _inFlight.clear();
    // See `_safetyClock` — frozen here so the OD-2 safety path never touches
    // `ref` after an await.
    _safetyClock = ref.read(posSyncClockProvider);
    _safetyIds = ref.read(clientIdGeneratorProvider);
    // S1-R5 / F004: the actor this world belongs to is frozen HERE. Reading
    // it inside `_hydrate` would happen after an await, when the container may
    // already be disposed — and it would also be the wrong question: the
    // disclosures a hydration may import are the ones belonging to the cashier
    // this controller was built for.
    final actor = ref.read(posSignedInEmployeeProfileIdProvider);
    final durable = _repo is PaymentAttemptSender && scope != null;
    _hydration = durable
        ? _hydrate(gen, store, scope, actor)
        : Future<void>.value();
    return PaymentState(
      shift: _repo.shiftContext(),
      payments: const {},
      hydrated: !durable,
    );
  }

  Future<void> _hydrate(
    int gen,
    PaymentAttemptStore store,
    PosSyncScope scope,
    String? actor,
  ) async {
    final load = await store.load(scope);
    if (gen != _generation) return;
    final attempts = <String, PaymentAttempt>{};
    final payments = <String, CashPayment>{...state.payments};
    for (final a in load.attempts) {
      // Oldest first, so the LATEST record per identity wins.
      attempts[a.identityKey] = a;
    }
    for (final a in attempts.values) {
      final p = a.payment;
      if (a.phase == PaymentAttemptPhase.accepted && p != null) {
        payments.putIfAbsent(a.identityKey, () => p);
      }
    }
    // S1-R4 / F004e: a rebuilt controller re-reads the in-process disclosure
    // register for THIS scope, so a truth whose write failed is not silently
    // dropped by the very provider replacement that lost it in R3. Nothing is
    // read across scopes.
    //
    // S1-R5 / F004: and only what belongs to THIS actor on THIS physical key,
    // for an operation the current record has not already superseded. R4
    // imported every disclosure for the sync scope, so a different cashier
    // signing in on the same till inherited the previous cashier's refusal.
    final disclosures = <String, PaymentAttemptDisclosure>{};
    final prefix = _disclosureActorPrefix(scope, actor);
    for (final entry in _paymentDisclosures.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final identityKey = entry.key.substring(prefix.length);
      final operationId = entry.value.localOperationId;
      final current = attempts[identityKey];
      if (operationId != null &&
          current != null &&
          current.localOperationId != operationId) {
        // A newer operation already owns this order's context.
        continue;
      }
      disclosures[identityKey] = entry.value;
    }
    state = state.copyWith(
      attempts: attempts,
      payments: payments,
      quarantined: load.quarantined,
      hydrated: true,
      disclosures: disclosures,
    );
  }

  /// Completes once the durable store has been read for the current scope.
  Future<void> ensureHydrated() => _hydration ?? Future<void>.value();

  String _nowIso() =>
      ref.read(posSyncClockProvider)().toUtc().toIso8601String();

  /// [_nowIso] without `ref`. Used by everything on the OD-2 safety path.
  String _safetyNowIso() => _safetyClock().toUtc().toIso8601String();

  /// S1-R4 / F004e — records the two truths for [identity] so they survive
  /// this sheet, this controller and this provider.
  void _discloseForAttempt(
    PosSyncScope scope,
    PosOrderIdentity identity,
    PaymentAttempt attempt,
    PaymentAttemptDisclosure disclosure,
  ) {
    if (disclosure.isEmpty) return;
    if (!_ownsCurrentContext(identity, attempt)) return;
    final bound = PaymentAttemptDisclosure(
      refusalCode: disclosure.refusalCode,
      localSaveFailed: disclosure.localSaveFailed,
      localOperationId: attempt.localOperationId,
    );
    _paymentDisclosures[_disclosureKey(
          scope,
          attempt.employeeProfileId,
          identity.key,
        )] =
        bound;
    state = state.copyWith(
      disclosures: <String, PaymentAttemptDisclosure>{
        ...state.disclosures,
        identity.key: bound,
      },
    );
  }

  /// S1-R5 / F004 — whether [attempt] still owns the disclosure context for
  /// [identity].
  ///
  /// An operation that has been SUPERSEDED on this order may not write or
  /// erase what the cashier is told about the operation that replaced it. R4
  /// bound the durable record to the live truth but left the disclosure
  /// register open, so a delayed refusal for operation A could describe
  /// operation B's accepted payment.
  bool _ownsCurrentContext(PosOrderIdentity identity, PaymentAttempt attempt) {
    final current = state.attempts[identity.key];
    return current == null ||
        current.localOperationId == attempt.localOperationId;
  }

  /// Cleared ONLY by a current transition that actually recorded the evidence
  /// it describes — never by a disposer, a health flag or a cache read.
  void _clearDisclosure(
    PosSyncScope scope,
    PosOrderIdentity identity,
    PaymentAttempt attempt,
  ) {
    if (!_ownsCurrentContext(identity, attempt)) return;
    _paymentDisclosures.remove(
      _disclosureKey(scope, attempt.employeeProfileId, identity.key),
    );
    if (!state.disclosures.containsKey(identity.key)) return;
    final next = Map<String, PaymentAttemptDisclosure>.from(state.disclosures)
      ..remove(identity.key);
    state = state.copyWith(disclosures: next);
  }

  /// S1-R4 / F001 — whether the world this operation was started in is still
  /// the current one.
  ///
  /// The R3 build checked this only when merging into memory, so a stale
  /// controller still reached the STORE first and persisted its late
  /// diagnostic over a newer accepted record. Authority is now required at the
  /// mutation boundary too, re-checked after every await, and the store
  /// applies its own guarded transition as the real fence.
  bool _stillAuthoritative(int gen) => gen == _generation;

  /// The current world's generation.
  ///
  /// Test-only, and load-bearing for the OD-2 stale-controller race tests:
  /// without it they cannot PROVE the generation actually moved under the
  /// call in flight, and would pass vacuously against a controller that was
  /// never stale. Read-only — nothing can bump a generation through this.
  @visibleForTesting
  int get generationForTest => _generation;

  void _setAttempt(int gen, PaymentAttempt attempt) {
    if (gen != _generation) return;
    state = state.copyWith(
      attempts: {...state.attempts, attempt.identityKey: attempt},
    );
  }

  /// Records a payment against [identity] — THE order's identity, not its display
  /// code (settling the order [orderId] in real mode; ignored by the demo store).
  /// [amountMinor] is the order total and, for a CASH [method], [tenderedMinor] is the
  /// cash received; a NON-CASH tender (card/bit/external) is externally recorded for
  /// the exact total with no change (RF-117). Throws [PaymentException] if a cash
  /// tender does not cover the total or (real mode) the push fails / is unauthorized.
  /// Returns the recorded [CashPayment].
  ///
  /// A thin wrapper over [submitAttempt]: every non-accepted outcome becomes a
  /// TYPED [PaymentException] (never a bare message the caller has to parse).
  Future<CashPayment> payCash({
    required PosOrderIdentity identity,
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
  }) async {
    final outcome = await submitAttempt(
      identity: identity,
      orderId: orderId,
      orderNumber: orderNumber,
      amountMinor: amountMinor,
      tenderedMinor: tenderedMinor,
      currencyCode: currencyCode,
      method: method,
      expectedRevision: expectedRevision,
    );
    return switch (outcome) {
      PaymentAttemptAccepted(:final payment) => payment,
      _ => throw exceptionFor(outcome),
    };
  }

  /// The typed [PaymentException] for a non-accepted [outcome].
  static PaymentException exceptionFor(PaymentAttemptOutcome outcome) {
    PaymentAttemptSummary? sum(PaymentAttempt? a) =>
        a == null ? null : PaymentAttemptSummary.of(a);
    return switch (outcome) {
      PaymentAttemptAccepted() => const PaymentException('accepted'),
      PaymentAttemptRefused(:final code) =>
        RealPaymentRepository.exceptionForRefusal(code),
      PaymentAttemptSettledElsewhere(:final attempt) => PaymentException(
        'payment refused: order settled by another attempt',
        settledElsewhere: true,
        attempt: sum(attempt),
      ),
      PaymentAttemptUnconfirmed(:final attempt, :final reason) =>
        PaymentException(
          'payment unconfirmed: ${reason.name}',
          unconfirmed: true,
          attempt: sum(attempt),
        ),
      PaymentAttemptNotApplied(:final attempt) => PaymentException(
        'payment failed: not applied',
        notApplied: true,
        attempt: sum(attempt),
      ),
      PaymentAttemptAuthRequired(:final attempt) => PaymentException(
        'payment failed: auth',
        authRequired: true,
        attempt: sum(attempt),
      ),
      PaymentAttemptSaveBlocked() => const PaymentException(
        'payment attempt could not be saved; nothing was sent',
        saveBlocked: true,
      ),
      PaymentAttemptBusy(:final attempt) => PaymentException(
        'payment attempt in flight',
        inFlight: true,
        attempt: sum(attempt),
      ),
      PaymentAttemptUnresolved(:final attempt) => PaymentException(
        'an unresolved payment attempt exists for this order',
        unresolvedAttempt: true,
        attempt: sum(attempt),
      ),
      PaymentAttemptOtherActor(:final attempt) => PaymentException(
        'the unresolved payment attempt belongs to another cashier',
        otherActor: true,
        attempt: sum(attempt),
      ),
      PaymentAttemptQuarantined() => const PaymentException(
        'a stored payment attempt cannot be read; nothing was sent',
        quarantined: true,
      ),
      PaymentAttemptRevisionRequired() => const PaymentException(
        'the order revision is unknown; refresh the order before taking payment',
        revisionRequired: true,
      ),
      PaymentAttemptActorRequired() => const PaymentException(
        'no signed-in cashier; nothing was sent',
        actorRequired: true,
      ),
    };
  }

  /// ONE durable business attempt (see the class doc). Returns a typed
  /// [PaymentAttemptOutcome]; never throws for a server/transport/storage
  /// outcome.
  Future<PaymentAttemptOutcome> submitAttempt({
    required PosOrderIdentity identity,
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
  }) async {
    final repo = _repo;
    if (repo is! PaymentAttemptSender) {
      return _submitLegacy(
        identity: identity,
        orderId: orderId,
        orderNumber: orderNumber,
        amountMinor: amountMinor,
        tenderedMinor: tenderedMinor,
        currencyCode: currencyCode,
        method: method,
        expectedRevision: expectedRevision,
      );
    }
    final sender = repo as PaymentAttemptSender;
    final key = identity.key;
    // SINGLE-FLIGHT, acquired SYNCHRONOUSLY at confirmation: a second confirm
    // for the same order while one send is in flight sends nothing.
    if (_inFlight.contains(key)) {
      return PaymentAttemptBusy(state.attempts[key]);
    }
    // FROZEN BEFORE THE FIRST AWAIT: the scope, session and actor this
    // decision is being taken IN. Nothing below re-reads them.
    final scope = ref.read(posSyncScopeProvider);
    final session = ref.read(posSyncSessionProvider);
    final employee = ref.read(posSignedInEmployeeProfileIdProvider);
    final gen = _generation;
    final store = ref.read(paymentAttemptStoreProvider);
    if (scope == null || session == null || orderId.trim().isEmpty) {
      // No scope / no session: the repository would fail closed anyway; say so
      // without minting or persisting anything.
      return const PaymentAttemptSaveBlocked();
    }
    final tenderType = method.wire;
    final effectiveTendered = method.isCash ? tenderedMinor : amountMinor;

    _inFlight.add(key);
    try {
      await ensureHydrated();
      // A REBUILD (new session / scope / repository) does NOT abandon a
      // decision already in progress: the frozen scope, session and store
      // above are the world this payment belongs to, the record is written
      // there, and the caller is told the TRUE outcome. Only the merge into
      // the CURRENT session's state is refused (see `_setAttempt` /
      // `_mergePayment`) — dropping the outcome instead would leave the
      // cashier staring at a sheet that did nothing while the server may
      // already hold their money.
      if (state.quarantineBlocks(orderId)) {
        return const PaymentAttemptQuarantined();
      }
      // PDR-003: a recoverable real attempt without an authoritative revision
      // carries no concurrency binding, so it is refused BEFORE any identity
      // is allocated, anything is persisted and anything is sent.
      if (expectedRevision == null) {
        return const PaymentAttemptRevisionRequired();
      }
      // PDR-007: and no attempt is created for a cashier we cannot name.
      if ((employee ?? '').trim().isEmpty) {
        return const PaymentAttemptActorRequired();
      }

      PaymentAttempt? attempt = state.attempts[key];
      String? supersedes;
      if (attempt != null) {
        switch (attempt.phase) {
          case PaymentAttemptPhase.pending:
            // A stored attempt from before this rule keeps its bytes and may
            // still be checked, but it is never re-sent and never patched
            // from a fresh order read.
            if (attempt.expectedRevision == null) {
              return const PaymentAttemptRevisionRequired();
            }
            final guard = _resumeGuard(
              attempt,
              employee: employee,
              orderId: orderId,
              tenderType: tenderType,
              amountMinor: amountMinor,
              amountTenderedMinor: effectiveTendered,
              currencyCode: currencyCode,
            );
            if (guard != null) return guard;
          case PaymentAttemptPhase.accepted:
            // Already settled by THIS device's attempt: nothing to send, no
            // new identity, and NO automatic effects again.
            final payment = attempt.payment;
            if (payment == null) break;
            return PaymentAttemptAccepted(
              attempt: attempt,
              payment: payment,
              replay: true,
              automaticEffectsArmed: false,
              localSaveFailed: false,
            );
          case PaymentAttemptPhase.settledElsewhere:
            // NO SECOND TENDER, EVER.
            //
            // "THIS attempt was refused AND the order is settled — by another
            // attempt or another till. Not our payment: no receipt, no drawer,
            // no second tender." An earlier draft shared this arm with
            // `refused` and fell through to the mint, so `eligibilityOf` could
            // declare `forbidden` while the controller allocated an identity
            // anyway. The arm now returns before any id, target or send.
            _setAttempt(gen, attempt);
            return PaymentAttemptSettledElsewhere(attempt);
          case PaymentAttemptPhase.refused:
            // Resolved. A corrected attempt is a NEW decision, linked to the
            // old one (history is never erased). Whether one may be created at
            // all is decided by the single pre-mint gate below, not here.
            supersedes = attempt.localOperationId;
            attempt = null;
        }
      }

      // =====================================================================
      // OWNER OPTION B — THE ONE PRE-MINT SAFETY GATE.
      //
      // Every route to `PaymentAttempt.mint` passes through here, BEFORE any
      // `local_operation_id` or provisional target is allocated and before
      // anything is sent.
      //
      // It has to be here rather than inside the `refused` arm. `attempt` is
      // null on several routes that reach the mint: a genuine first payment, a
      // REBUILT controller whose in-memory map is empty, a controller that lost
      // its state while a durable block or an incident still stands, and any
      // path where the record simply is not in memory. An earlier draft gated
      // only the refused arm, so Owner Option B was enforced on one of the two
      // routes and a rebuilt controller could mint beside an ACTIVE durable
      // replacement block.
      //
      // `eligibilityOfSafety` — not the narrower accepted-truth projection —
      // is the gate. It forbids a fresh identity for an unreadable, untrusted,
      // present-empty, wrongly-typed or non-canonical envelope; a quarantine
      // blocking this order; an active durable block; an active isolate
      // incident; and a fail-closed owner. The accepted-truth projection is
      // consulted only to choose WHICH answer to give (§`_blockedMintOutcome`).
      //
      // Routes that returned above — accepted, settledElsewhere, and every
      // resume-guard refusal — never reach it, and a same-attempt resend never
      // reaches it either, because a pending record is adopted under its own
      // identity.
      if (attempt == null) {
        // THE ONLY AWAIT ON THIS PATH, and it is taken before anything is
        // decided. It returns BYTES AND NOTHING ELSE: no registry state is
        // allowed to cross this suspension, because anything that did would be
        // stale by the time it was acted on.
        final snapshot = await _readSafetySnapshot(store, scope, orderId);

        // ===================================================================
        // FROM HERE TO `PaymentAttempt.mint` THERE IS NO AWAIT, NO YIELD AND
        // NO ASYNC CALLBACK. That is load-bearing, not tidiness.
        //
        // The safety registry is an isolate global that other payment paths
        // commit to. An earlier draft sampled it BEFORE the snapshot read
        // above and hydrated with that value afterwards, so an incident
        // latched by another path DURING the read was invisible: rungs 4 and 5
        // consulted a map that no longer existed, the gate answered
        // `SafetyClear`, and a second `local_operation_id` and provisional
        // target were allocated for money this device already knew had moved.
        //
        // Reading the registry live is only half the fix. The read and the
        // decision it feeds have to happen in the SAME synchronous run, or the
        // very same window reopens between them — including across the
        // microtask boundary that returning from an `async` helper introduces,
        // which is why the hydrate is a plain function called HERE rather than
        // behind another await.
        //
        // `_hydrateSafetyNow`, `eligibilityOfSafety`, `_knownAcceptedIncident`,
        // `_blockedMintOutcome` and `PaymentAttempt.mint` are all synchronous.
        // DO NOT introduce an await into this block.
        // ===================================================================
        final safety = _hydrateSafetyNow(scope, orderId, snapshot);
        if (eligibilityOfSafety(safety) !=
            NewIdentityEligibility.freshMintAllowed) {
          // OD-1 — TWO SEPARATE QUESTIONS, ASKED SEPARATELY.
          //
          // "May a new identity be minted?" is decided ABOVE, by
          // `eligibilityOfSafety` alone. "What is the strongest thing this
          // device knows about the money?" is a different question, and the
          // answer to it may NOT be limited to what the envelope happens to be
          // readable enough to say.
          //
          // `hydratePaymentSafety` is a precedence ladder, and rung 1 — the
          // envelope is not usable — outranks rung 4, the isolate incident. So
          // a momentarily untrusted key hid an ACTIVE incident carrying exact
          // accepted/APPLIED truth, and the public answer came back
          // `PaymentAttemptSaveBlocked`, which `moneyTruthOf` publishes as
          // `nothingSent`: money that provably moved, reported as never sent.
          // That is precisely what OD-1 forbids.
          //
          // The known evidence is therefore read DIRECTLY from the registry,
          // never through the gate's ladder, and it is used ONLY to choose how
          // to say no — never to decide whether to say it.
          return _blockedMintOutcome(
            safety,
            _knownAcceptedIncident(scope, orderId),
          );
        }

        // MINT ONCE per cashier decision — the only place a new identity is
        // ever allocated on the durable path, and STILL THE SAME SYNCHRONOUS
        // RUN as the safety check immediately above.
        final minted = PaymentAttempt.mint(
          ids: ref.read(clientIdGeneratorProvider),
          now: ref.read(posSyncClockProvider)(),
          orderId: orderId,
          orderNumber: orderNumber,
          amountMinor: amountMinor,
          tenderedMinor: tenderedMinor,
          currencyCode: currencyCode,
          method: method,
          expectedRevision: expectedRevision,
          organizationId: scope.organizationId,
          restaurantId: scope.restaurantId,
          branchId: scope.branchId,
          deviceId: session.deviceId,
          employeeProfileId: employee,
          supersedes: supersedes,
        );
        // PERSIST BEFORE SEND. The record is stamped "sent" now, because the
        // moment the write is confirmed the bytes leave; a crash in between
        // reads as "may have been sent" — the only safe reading.
        final PaymentAttemptClaim claim;
        try {
          claim = await store.createIfAbsent(scope, minted.markSent(_nowIso()));
        } on PosPersistenceException {
          return const PaymentAttemptSaveBlocked();
        } catch (_) {
          return const PaymentAttemptSaveBlocked();
        }
        attempt = claim.attempt;
        if (!claim.created) {
          // Another controller/tab persisted an attempt for this order first:
          // adopt it if it is the same decision, otherwise refuse to send.
          final guard = _resumeGuard(
            attempt,
            employee: employee,
            orderId: orderId,
            tenderType: tenderType,
            amountMinor: amountMinor,
            amountTenderedMinor: effectiveTendered,
            currencyCode: currencyCode,
          );
          if (guard != null) {
            _setAttempt(gen, attempt);
            return guard;
          }
        }
        _setAttempt(gen, attempt);
      }

      final result = await sender.sendAttempt(attempt);
      return _resolve(
        gen: gen,
        scope: scope,
        session: session,
        store: store,
        attempt: attempt,
        result: result,
      );
    } finally {
      _inFlight.remove(key);
    }
  }

  /// The envelope snapshot the pre-mint gate reasons about, or null when this
  /// store has no snapshot seam (demo / a hand-written fake) or [orderId] is
  /// not canonical.
  ///
  /// THE AWAITING HALF OF THE GATE, and deliberately the whole of it. It
  /// returns bytes and nothing else: no safety-registry state crosses this
  /// suspension, because the registry is an isolate global other payment paths
  /// commit to, and a value read before this await would already be stale by
  /// the time the caller decided anything on it.
  Future<SnapshotResult?> _readSafetySnapshot(
    PaymentAttemptStore store,
    PosSyncScope scope,
    String orderId,
  ) async {
    final canonical = CanonicalOrderId.tryFrom(orderId);
    if (canonical == null) return null;
    if (store is! SharedPrefsPaymentAttemptStore) return null;
    return store.readEnvelopeSnapshot(scope, canonical);
  }

  /// The hydrated money-safety state, combining [snapshot] with the registry as
  /// it is RIGHT NOW.
  ///
  /// SYNCHRONOUS ON PURPOSE — this is the other half of the rule above. The
  /// caller must be able to read the registry, hydrate, decide eligibility and
  /// mint without ever yielding, and an `async` helper cannot offer that: even
  /// with a live read inside it, returning re-enters the caller a microtask
  /// later, and another path's commit fits in that gap just as well as it fits
  /// in a longer one.
  ///
  /// Combines, in precedence order: envelope fail-closed, record quarantine,
  /// durable active replacement block, isolate incident, owner fail-closed. A
  /// store without the snapshot seam can only offer the isolate registry, and
  /// says so rather than reporting "clear" from evidence it does not have.
  HydratedSafetyState _hydrateSafetyNow(
    PosSyncScope scope,
    String orderId,
    SnapshotResult? snapshot,
  ) {
    final canonical = CanonicalOrderId.tryFrom(orderId);
    if (canonical == null) {
      return const SafetyOwnerFailClosed(IncidentReason.storageUntrusted);
    }
    // THE LIVE READ. Nothing between here and the caller's mint suspends.
    final registry = paymentSafetyRegistry();
    if (snapshot != null) {
      return hydratePaymentSafety(snapshotResult: snapshot, registry: registry);
    }
    final key = PaymentActivityKey(scope: scope, orderId: canonical);
    final incident = registry.incidentOf(key);
    if (incident != null && incident.state == IncidentState.active) {
      return SafetyIncident(incident);
    }
    final handoff = registry.ownerOf(key)?.handoff;
    if (handoff is OwnerHandoffFailClosed) {
      return SafetyOwnerFailClosed(handoff.reason);
    }
    return const SafetyClear();
  }

  /// The ACTIVE incident for this order carrying accepted/APPLIED truth, read
  /// straight from the isolate registry.
  ///
  /// Deliberately NOT routed through `hydratePaymentSafety`: that function is
  /// the mint gate and its rung order is correct for that job — an unreadable
  /// envelope must fail closed before anything else is considered. This asks a
  /// different question, so it must not inherit that precedence.
  ///
  /// It is never consulted about eligibility. See the call site.
  PaymentFailClosedIncident? _knownAcceptedIncident(
    PosSyncScope scope,
    String orderId,
  ) {
    final canonical = CanonicalOrderId.tryFrom(orderId);
    if (canonical == null) return null;
    final incident = paymentSafetyRegistry().incidentOf(
      PaymentActivityKey(scope: scope, orderId: canonical),
    );
    if (incident == null || incident.state != IncidentState.active) return null;
    return incident.acceptedTruth == null ? null : incident;
  }

  /// The honest public answer when the pre-mint gate refuses a fresh identity.
  ///
  /// THE PRIORITY RULE: known accepted/APPLIED money truth is never erased by a
  /// safety or storage failure. When the blocking evidence itself CARRIES an
  /// accepted-class server truth, the answer is accepted-class — with
  /// `localSaveFailed: true` and no effects — rather than a diagnostic.
  ///
  /// An earlier draft returned `PaymentAttemptUnconfirmed(identityCollision)`
  /// here. That was wrong twice over: `identityCollision` documents "the server
  /// holds a DIFFERENT operation under our key", whereas this evidence is the
  /// SAME operation reported APPLIED; and `PaymentAttemptUnconfirmed` offers
  /// Check-status and Resume, both inert for a record that is already terminal.
  PaymentAttemptOutcome _blockedMintOutcome(
    HydratedSafetyState safety,
    PaymentFailClosedIncident? knownAccepted,
  ) {
    // A DURABLE ACTIVE BLOCK. It carries both the contradicted parent and the
    // accepted truth, so the money can be stated exactly without a store read.
    if (safety is SafetyDurableBlocked) {
      final truth = safety.block.serverTruth;
      if (truth is AcceptedTruth) {
        return PaymentAttemptAccepted(
          attempt: safety.parent,
          payment: _paymentFromFrozen(safety.parent, truth.resolution),
          replay: true,
          // NEVER re-armed: this is a refusal to mint, not a payment edge.
          automaticEffectsArmed: false,
          // This device's durable record is NOT the proof — it still reads as
          // the contradicted terminal state. `movedUnproven`, not `moved`.
          localSaveFailed: true,
        );
      }
    }

    // AN ISOLATE INCIDENT holding accepted truth. The 17-field binding it
    // carries is enough to state the money exactly.
    if (safety is SafetyIncident) {
      final truth = safety.incident.acceptedTruth;
      if (truth != null) {
        final live = state.attempts[safety.incident.binding.identityKey];
        return PaymentAttemptAccepted(
          attempt: live ?? _frozenFromBinding(safety.incident.binding),
          payment: _paymentFromBinding(
            safety.incident.binding,
            truth.resolution,
          ),
          replay: true,
          automaticEffectsArmed: false,
          localSaveFailed: true,
        );
      }
    }

    // OD-1 — KNOWN ACCEPTED MONEY OUTRANKS A STORAGE FAILURE.
    //
    // Reached when the gate's ladder answered something non-accepted — most
    // often `SafetyEnvelopeFailClosed` for a key that is untrusted only because
    // a write is still in flight — while the registry holds an ACTIVE incident
    // with exact accepted/APPLIED truth for this very order. The refusal to
    // mint stands unchanged; only the way it is SAID changes, from "nothing was
    // sent" to the truth.
    if (knownAccepted != null) {
      final truth = knownAccepted.acceptedTruth!;
      final live = state.attempts[knownAccepted.binding.identityKey];
      return PaymentAttemptAccepted(
        attempt: live ?? _frozenFromBinding(knownAccepted.binding),
        payment: _paymentFromBinding(knownAccepted.binding, truth.resolution),
        replay: true,
        // Still a refusal to mint, not a payment edge.
        automaticEffectsArmed: false,
        // Still degraded: this device's own record is not the proof.
        localSaveFailed: true,
      );
    }

    return switch (safety) {
      // "A stored attempt that may concern this order cannot be read."
      SafetyRecordQuarantined() => const PaymentAttemptQuarantined(),

      // The envelope itself is unusable, so nothing could be minted, stored or
      // sent — exactly what SaveBlocked says, and what the store would have
      // answered a moment later. This gate simply refuses BEFORE an identity is
      // allocated rather than after.
      SafetyEnvelopeFailClosed() => const PaymentAttemptSaveBlocked(),

      // Blocking evidence whose truth is NOT accepted-class: the outcome for
      // this order is not established and no new tender may start.
      SafetyDurableBlocked() ||
      SafetyIncident() ||
      SafetyOwnerFailClosed() => const PaymentAttemptQuarantined(),

      // Unreachable: `eligibilityOfSafety(SafetyClear())` is `freshMintAllowed`
      // and never reaches this helper.
      SafetyClear() => const PaymentAttemptSaveBlocked(),
    };
  }

  /// The [CashPayment] a frozen record plus an accepted resolution describe.
  ///
  /// Field for field what `PaymentAttempt.payment` builds, but usable on a
  /// record whose own `resolution` is null — the contradicted terminal parent.
  CashPayment _paymentFromFrozen(
    PaymentAttempt frozen,
    PaymentAttemptResolution r,
  ) => CashPayment(
    paymentId: r.paymentId,
    orderId: frozen.orderId.isEmpty ? null : frozen.orderId,
    orderNumber: frozen.orderNumber,
    deviceId: frozen.deviceId,
    localOperationId: frozen.localOperationId,
    method: r.method,
    status: PaymentStatus.completed,
    amountMinor: frozen.amountMinor,
    tenderedMinor: frozen.amountTenderedMinor,
    changeMinor: r.changeDueMinor,
    currencyCode: frozen.currencyCode,
    receiptNumber: r.receiptNumber,
    paidAt: DateTime.tryParse(frozen.clientCreatedAt) ?? DateTime.now(),
    orderStatus: r.orderStatus,
  );

  /// The same, from the incident's own 17-field binding.
  CashPayment _paymentFromBinding(
    ExactAttemptBinding b,
    PaymentAttemptResolution r,
  ) => CashPayment(
    paymentId: r.paymentId,
    orderId: b.orderId.isEmpty ? null : b.orderId,
    orderNumber: b.orderNumber,
    deviceId: b.deviceId,
    localOperationId: b.localOperationId,
    method: r.method,
    status: PaymentStatus.completed,
    amountMinor: b.amountMinor,
    tenderedMinor: b.amountTenderedMinor,
    changeMinor: r.changeDueMinor,
    currencyCode: b.currencyCode,
    receiptNumber: r.receiptNumber,
    paidAt: DateTime.tryParse(b.clientCreatedAt) ?? DateTime.now(),
    orderStatus: r.orderStatus,
  );

  /// The contradicted terminal record the incident was raised against, rebuilt
  /// from its binding for reporting only. Used when the live record is not in
  /// this controller's memory (a rebuild) and the block is isolate-only.
  PaymentAttempt _frozenFromBinding(ExactAttemptBinding b) => PaymentAttempt(
    localOperationId: b.localOperationId,
    targetId: b.targetId,
    clientCreatedAt: b.clientCreatedAt,
    identityKey: b.identityKey,
    orderId: b.orderId,
    orderNumber: b.orderNumber,
    expectedRevision: b.expectedRevision,
    tenderType: b.tenderType,
    amountMinor: b.amountMinor,
    amountTenderedMinor: b.amountTenderedMinor,
    currencyCode: b.currencyCode,
    organizationId: b.organizationId,
    restaurantId: b.restaurantId,
    branchId: b.branchId,
    deviceId: b.deviceId,
    employeeProfileId: b.employeeProfileId,
    phase: PaymentAttemptPhase.refused,
    lastOutcome: PaymentAttemptLastOutcome.none,
    sentAt: b.clientCreatedAt,
    resolvedAt: b.clientCreatedAt,
    resolution: null,
    refusal: PaymentRefusalCode.generic,
    refusalMemoized: true,
    autoEffectsReservedAt: null,
    supersedes: b.supersedes,
    mayHaveExecuted: true,
  );

  /// OD-2 — the ISOLATE half of Owner-B containment.
  ///
  /// Puts the activity key into a fail-closed posture carrying the exact
  /// accepted truth, so `eligibilityOfSafety` answers `forbidden` and no new
  /// payment identity can be minted for this order.
  ///
  /// It writes NOTHING durable and claims NO effect: no reservation, no arming,
  /// no receipt, no drawer, no session merge, no controller state. That is what
  /// makes it legal to run from a REPLACED controller, which is exactly when it
  /// matters most.
  ///
  /// Idempotent, and deliberately so — OD-1. An existing owner is reused, and an
  /// existing incident is never replaced: a later observation may not overwrite
  /// accepted/APPLIED money truth that is already recorded.
  ///
  /// Entering fail-closed bumps the safety epoch, so every reservation taken
  /// before this instant is stale and can never promote.
  void _latchAcceptedFailClosed({
    required PaymentActivityKey key,
    required ExactAttemptBinding binding,
    required String operationId,
    required AcceptedTruth truth,
    required IncidentReason reason,
  }) {
    // B1 — EVERY STEP COMMITS AGAINST THE LIVE REGISTRY, KEY-SCOPED.
    //
    // An earlier draft threaded one sampled `registry` value through all three
    // steps and assigned it wholesale at the end. Each step is cheap and
    // synchronous, so that was survivable here — but it is the same shape that
    // was NOT survivable across the promotion await, and one rule beats a rule
    // with an exception. Nothing in this method can now publish a view of
    // another order's key.
    final existing = paymentSafetyRegistry().ownerOf(key);
    final ownerToken = existing?.ownerToken ?? ActivityOwnerToken.issue(key);
    if (existing == null) {
      final begun = commitSafetyTransition(
        (live) => beginOwner(
          registry: live,
          key: key,
          ownerToken: ownerToken,
          binding: binding,
        ),
      );
      if (begun is! SafetyCommitApplied) return;
    }

    // Entering fail-closed bumps the safety epoch, so every reservation taken
    // before this instant is stale and can never promote.
    if (!(paymentSafetyRegistry().ownerOf(key)?.handoff.isFailClosed ??
        false)) {
      final closed = commitSafetyTransition(
        (live) => enterOwnerFailClosed(
          registry: live,
          key: key,
          expectedOwnerToken: ownerToken,
          reason: reason,
        ),
      );
      if (closed is! SafetyCommitApplied) return;
    }

    // OD-1 — never replace an incident that already stands. A later
    // observation may not overwrite recorded accepted/APPLIED money truth.
    if (paymentSafetyRegistry().incidentOf(key) == null) {
      commitSafetyTransition(
        (live) => installIncidentIfAbsent(
          registry: live,
          key: key,
          incident: PaymentFailClosedIncident(
            key: key,
            // No durable block yet; promotion, where it is legal, allocates
            // the occurrence.
            occurrence: null,
            operationId: operationId,
            binding: binding,
            serverTruth: truth,
            reason: reason,
            observedAt: _safetyNowIso(),
            durability: const IsolateLatchOnly(),
            state: IncidentState.active,
            conflictingDiagnosticEvidence: const <ServerTruth>[],
          ),
        ),
      );
    }
  }

  /// OWNER OPTION B + OD-2 — the DURABLE half: an ACTIVE `replacement_block` on
  /// the contradicted parent, so containment survives a process restart.
  ///
  /// [parent] has ALREADY been selected exactly by
  /// [_reconcileAcceptedSafetyEvidence] — one in-scope record for this
  /// operation, the authoritative order and derived identity, the authoritative
  /// raw scope, and no aliased or unreadable evidence for this order. The two
  /// checks repeated here are defence in depth, not the selection.
  ///
  /// THE CONTROLLER GENERATION IS NOT CONSULTED. Under OD-2 the generation is
  /// authority over this controller's UI, session and effects — never over
  /// money-safety evidence. An earlier draft returned early on
  /// `_stillAuthoritative(gen)` after the snapshot read, so a provider rebuild
  /// landing during that read discarded the ONLY record of the contradiction,
  /// and the rebuilt controller then minted a second identity for money that had
  /// already moved.
  ///
  /// Returns true iff an ACTIVE block is now on disk AND proven durable.
  Future<bool> _installOwnerBIncident({
    required SharedPrefsPaymentAttemptStore store,
    required PosSyncScope scope,
    required PaymentActivityKey key,
    required PaymentAttempt parent,
    required PaymentAttempt attempt,
    required AcceptedTruth truth,
    required bool promote,
  }) async {
    // EXACT evidence, or nothing.
    if (parent.phase != PaymentAttemptPhase.refused &&
        parent.phase != PaymentAttemptPhase.settledElsewhere) {
      return false;
    }
    if (!parent.describesSameDecisionAs(attempt)) return false;

    // 1 — the isolate latch, first and unconditionally.
    _latchAcceptedFailClosed(
      key: key,
      binding: ExactAttemptBinding.of(parent),
      operationId: parent.localOperationId,
      truth: truth,
      reason: IncidentReason.ownerBContradiction,
    );

    if (!promote) return false;
    final registry = paymentSafetyRegistry();
    final incident = registry.incidentOf(key);
    final owner = registry.ownerOf(key);
    if (incident == null || owner == null) return false;

    // 2 — make it survive a process restart.
    //
    // The durable parent exists (it is the record just selected) and it is
    // replacement-eligible, so promotion is available here. This is NOT a
    // "second write after a failed write": `resolveAccepted` refuses this case
    // in its reconcile branch and throws BEFORE attempting any write, so the
    // key's durability is untested rather than implicated.
    final IncidentPromotionResult promotion;
    try {
      promotion = await store.promoteIncidentToDurable(
        scope: scope,
        registry: registry,
        incident: incident,
        expectedOwnerToken: owner.ownerToken,
        expectedSafetyEpoch: owner.safetyEpoch,
        blockId: _safetyIds.newId(),
        at: _safetyNowIso(),
      );
    } catch (_) {
      // Promotion could not even run — a disposed container, or the store
      // itself. The committed isolate latch still blocks this order for the
      // life of this isolate; a process restart for THIS contradiction remains
      // uncertified.
      return false;
    }
    // Bound to its own local: the closure below reads it, and a captured
    // late-assigned local does not type-promote inside one.
    final promoted = promotion;
    if (promoted is IncidentPromoted) {
      // B1 — KEY-SCOPED, AGAINST THE LIVE REGISTRY.
      //
      // `promotion.registry` is derived from `registry`, which was sampled
      // BEFORE the await above — an await that spans a prefs resolve, a bounded
      // snapshot read and a durable write. Installing it wholesale published
      // the whole isolate as it looked before that window and erased any other
      // order's owner or incident committed inside it. The classes that latch
      // WITHOUT promoting (a lost record, a pending parent under a replaced
      // controller) have no second write to restore them, so for those keys the
      // erasure was permanent and the next confirm minted a second identity.
      //
      // Only this key's incident crosses, and only if this key is still exactly
      // where the promotion believed it was.
      final committed = commitSafetyTransition(
        (live) => replaceIncidentIfExact(
          registry: live,
          key: key,
          expectedOccurrence: incident.occurrence,
          nextIncident: promoted.incident,
        ),
      );
      return committed is SafetyCommitApplied;
    }
    // Any other result leaves the committed isolate latch exactly as it is:
    // still active, still fail-closed, still blocking a new identity.
    return false;
  }

  /// The single in-scope entry carrying [operationId], or null when there is not
  /// exactly one.
  ///
  /// ONLY called after `selectExactAttemptSubject` has already passed every
  /// exactness check for this operation on this snapshot and refused solely on
  /// the STATE of the replacement block. It re-derives nothing and is not a
  /// second, weaker selector.
  static PaymentAttempt? _exactParentIn(
    SnapshotReady snap,
    String operationId,
  ) {
    PaymentAttempt? hit;
    var matches = 0;
    for (final e in snap.entries) {
      if (e.kind != FrozenEntryKind.inScope) continue;
      if (e.attempt!.localOperationId != operationId) continue;
      matches++;
      hit ??= e.attempt;
    }
    return matches == 1 ? hit : null;
  }

  /// OD-2 — WHAT THE DURABLE RECORD SAYS ABOUT AN EXACT ACCEPTED SERVER TRUTH.
  ///
  /// Runs on EVERY accepted response, BEFORE the controller-generation check,
  /// because an exact accepted/APPLIED answer is knowledge about MONEY: a
  /// replaced controller losing its right to touch the UI is not a reason to
  /// forget it. The classification itself is PASSIVE — it reads and never
  /// writes — and each class below takes the narrowest action that prevents a
  /// SECOND payment identity, while claiming no effect whatsoever.
  ///
  /// * **A / accepted parent** — the durable record already carries an
  ///   acceptance. `submitAttempt`'s `accepted` arm returns before the pre-mint
  ///   gate is ever reached, so no replacement can be authorised from here.
  ///   Nothing is installed.
  /// * **B / pending parent** — the same attempt, unresolved. When THIS
  ///   controller is going to finalize it is about to write the acceptance
  ///   itself, so latching would fail-close every ordinary successful payment:
  ///   nothing is done. When it will NOT (a replaced controller), nothing else
  ///   is going to record this money, so the isolate latches — a pending parent
  ///   is not replacement-eligible, so no durable block is legal here.
  /// * **C / refused or settledElsewhere parent** — THE R-A CASE. A
  ///   replacement-eligible terminal record contradicts an accepted server
  ///   truth. Latched and promoted to a durable ACTIVE block, regardless of
  ///   generation.
  /// * **D / no record** — money moved and this device has no record of it. No
  ///   durable parent exists, so none is fabricated; the isolate latches with
  ///   `recordLoss`, and a process restart is explicitly NOT certified for this
  ///   case.
  /// * **E / another decision** — a record under this operation id whose 17-field
  ///   binding is not ours. This truth is never installed against it and that
  ///   decision's payment is never published.
  /// * **F / unusable storage** — an unreadable, untrusted, non-canonical,
  ///   ambiguous, aliased, quarantined or malformed envelope. Every one of these
  ///   already makes `hydratePaymentSafety` fail the pre-mint gate closed, and
  ///   none of them names an exact parent this truth could be recorded against,
  ///   so nothing is installed and nothing is erased.
  Future<void> _reconcileAcceptedSafetyEvidence({
    required PaymentAttemptStore store,
    required PosSyncScope scope,
    required PaymentAttempt attempt,
    required PaymentAttemptResolution resolution,
    required BlockEvidenceSource evidenceSource,
    required bool Function() latchPendingSameAttempt,
  }) async {
    // A store without the snapshot seam (demo / a hand-written fake) cannot be
    // classified — and cannot hold a replacement block either, so the pre-mint
    // gate falls back to the isolate registry alone. Class F.
    if (store is! SharedPrefsPaymentAttemptStore) return;
    final orderId = CanonicalOrderId.tryFrom(attempt.orderId);
    if (orderId == null) return;

    final SnapshotResult snapshot;
    try {
      snapshot = await store.readEnvelopeSnapshot(scope, orderId);
    } catch (_) {
      return; // class F
    }

    final key = PaymentActivityKey(scope: scope, orderId: orderId);
    final truth = AcceptedTruth(
      resolution: resolution,
      evidenceSource: evidenceSource,
    );

    // D — THE ENVELOPE ITSELF IS GONE. This is a record loss, not a storage
    // fault, and it must be latched rather than left to the gate: `SnapshotAbsent`
    // is the ONE unreadable-looking result `hydratePaymentSafety` does NOT fail
    // closed on (rung 1 lets a PROVEN absence through, so a virgin order can
    // still be paid), and it would otherwise hydrate `SafetyClear` and authorise
    // a fresh mint for money that has already moved.
    if (snapshot is SnapshotAbsent) {
      _latchAcceptedFailClosed(
        key: key,
        binding: ExactAttemptBinding.of(attempt),
        operationId: attempt.localOperationId,
        truth: truth,
        reason: IncidentReason.recordLoss,
      );
      return;
    }
    // Every other non-ready snapshot already fails the pre-mint gate closed at
    // rung 1, and names no exact parent. Class F.
    if (snapshot is! SnapshotReady) return;

    var selection = selectExactAttemptSubject(
      snapshot: snapshot,
      key: key,
      localOperationId: attempt.localOperationId,
      requireActiveReplacementBlock: false,
    );
    // A block already stands on this parent. Ask again under the active-block
    // contract, so an ACTIVE one yields the subject rather than a refusal.
    final blockAlreadyPresent = selection is SubjectBlockPresent;
    if (blockAlreadyPresent) {
      selection = selectExactAttemptSubject(
        snapshot: snapshot,
        key: key,
        localOperationId: attempt.localOperationId,
        requireActiveReplacementBlock: true,
      );
    }
    final PaymentAttempt? parent;
    if (selection is SubjectSelected) {
      parent = selection.subject.parent;
    } else if (blockAlreadyPresent) {
      // A block DECODED on this parent but the active-block contract refused
      // it - `SubjectBlockPresent` is emitted only from `BlockDecoded`, so the
      // reachable case here is `SubjectBlockNotActive`: a RESOLVED block, which
      // rule S6d permits only on an ACCEPTED parent. It matters because
      // `hydratePaymentSafety` rung 3 blocks on an ACTIVE block alone, so a
      // resolved one leaves the gate open and the isolate latch below is the
      // only containment for a NEW contradiction on that record.
      //
      // Every exactness check already passed on the first selection - order,
      // derived identity, raw scope, exactly one in-scope record, no aliased or
      // unreadable evidence - so the single matching entry IS the exact parent.
      parent = _exactParentIn(snapshot, attempt.localOperationId);
    } else if (selection is SubjectNotFound) {
      // D — RECORD ABSENT.
      _latchAcceptedFailClosed(
        key: key,
        binding: ExactAttemptBinding.of(attempt),
        operationId: attempt.localOperationId,
        truth: truth,
        reason: IncidentReason.recordLoss,
      );
      return;
    } else {
      return; // class F
    }
    if (parent == null) return; // class F

    // E — the record under this operation id describes ANOTHER decision.
    if (!parent.describesSameDecisionAs(attempt)) return;

    // B4 — THE COMMIT BARRIER. Exact evidence is now classified and nothing has
    // been committed yet, so this is the one instant at which a test can land a
    // provider rebuild inside the window OD-2 is about. Null in production, and
    // the only statement between classification and commit.
    final barrier = debugPaymentSafetyCommitBarrier;
    if (barrier != null) await barrier();

    switch (parent.phase) {
      case PaymentAttemptPhase.accepted:
        return; // class A

      case PaymentAttemptPhase.pending:
        // B. The same attempt, still unresolved on disk.
        //
        // EVALUATED HERE, NOT SAMPLED AT THE CALL SITE. Between the call and
        // this line the snapshot read has awaited - `_resolvePrefs`, and up to
        // four independent reads on an untrusted key - and authority can lapse
        // inside that window. A bool captured before the await would say "a
        // writer is coming" about a controller that has since been replaced,
        // and the acceptance would then be recorded by nobody. Same shape as
        // the `authority` predicate `resolveAccepted` re-evaluates inside its
        // own serialized mutation, and for the same reason.
        if (!latchPendingSameAttempt()) return;
        _latchAcceptedFailClosed(
          key: key,
          binding: ExactAttemptBinding.of(parent),
          operationId: parent.localOperationId,
          truth: truth,
          reason: IncidentReason.recordLoss,
        );

      case PaymentAttemptPhase.refused:
      case PaymentAttemptPhase.settledElsewhere:
        // C — THE R-A CASE.
        await _installOwnerBIncident(
          store: store,
          scope: scope,
          key: key,
          parent: parent,
          attempt: attempt,
          truth: truth,
          // A promotion CREATES the first block; `promoteIncidentToDurable`
          // refuses with `SubjectBlockPresent` when one already stands. An
          // existing ACTIVE block is already the containment this would have
          // written, and the idempotent latch above covers the rest.
          promote: !blockAlreadyPresent,
        );
    }
  }

  /// Why a PENDING attempt may NOT simply be resumed by this call, or null when
  /// it may.
  PaymentAttemptOutcome? _resumeGuard(
    PaymentAttempt attempt, {
    required String? employee,
    required String orderId,
    required String tenderType,
    required int amountMinor,
    required int amountTenderedMinor,
    required String currencyCode,
  }) {
    // PDR-007 — FAIL CLOSED on identity. The previous rule refused only when
    // both sides were present and different, so a missing stored actor, a
    // missing current actor, or both missing all passed and allowed a re-send
    // under an actor nobody could name. A resend now requires two non-empty
    // identities that are equal; every other combination keeps the record and
    // permits only the existing authorized passive checking. Re-authenticating
    // the SAME employee yields the same id and is unaffected.
    final storedActor = attempt.employeeProfileId?.trim() ?? '';
    final currentActor = employee?.trim() ?? '';
    if (storedActor.isEmpty ||
        currentActor.isEmpty ||
        storedActor != currentActor) {
      return PaymentAttemptOtherActor(attempt);
    }
    if (!attempt.sameDecision(
      orderId: orderId,
      tenderType: tenderType,
      amountMinor: amountMinor,
      amountTenderedMinor: amountTenderedMinor,
      currencyCode: currencyCode,
    )) {
      return PaymentAttemptUnresolved(attempt);
    }
    return null;
  }

  /// Applies the server's answer for [attempt]: persists the resolution, merges
  /// the payment into the session state (only if this is still the same
  /// world), and reports the typed outcome.
  Future<PaymentAttemptOutcome> _resolve({
    required int gen,
    required PosSyncScope scope,
    required SyncSession session,
    required PaymentAttemptStore store,
    required PaymentAttempt attempt,
    required PaymentSendResult result,

    /// PDR-005. False for a PASSIVE resolution (Check Status, boot,
    /// hydration, refresh): the evidence still resolves the attempt and the
    /// one-time effect claim is still consumed so nothing can fire it later,
    /// but a query is never a payment edge and never arms paper or a drawer.
    bool armEffects = true,
  }) async {
    // B2 — REF-FREE UNTIL CONTAINMENT.
    //
    // This is the FIRST statement executed in the continuation of
    // `await sender.sendAttempt(...)`, and it used to be `_nowIso()`, which is
    // `ref.read(posSyncClockProvider)`. `ref` is unusable in two states this
    // exact continuation can land in: a DISPOSED container (a `StateError`, in
    // every build mode), and riverpod's dirty window — a watched dependency
    // changed but the element has not rebuilt — where `_generation` has NOT
    // moved, so `_stillAuthoritative` still answers true, yet every `ref`
    // function throws.
    //
    // Either way the throw escaped `_resolve` before a single line of
    // containment had run: the exact accepted/APPLIED answer was discarded, no
    // incident was installed, no block was promoted, and the caller got an
    // exception instead of the truth about its own money. `_safetyClock` was
    // captured in `build`, where `ref` is always legal, and reading a field
    // cannot throw.
    //
    // Everything from here to the containment call is ref-free; see the
    // inventory on `_reconcileAcceptedSafetyEvidence`. Current-controller
    // finalization may use `ref` again AFTER containment, and does.
    final now = _safetyNowIso();
    switch (result) {
      case PaymentSendAccepted(:final resolution):
        // ONE write: the accepted resolution AND the one-time effect
        // reservation, decided against the LIVE stored record (so a second
        // writer that already reserved cannot arm the effects again).
        PaymentAttempt resolved = attempt.accepted(
          resolution,
          at: now,
          reserveEffects: true,
        );
        var saved = true;
        var armed = false;

        // ===================================================================
        // OD-2 — SAFETY EVIDENCE FIRST, CONTROLLER AUTHORITY SECOND.
        //
        // Controller-generation authority and money-safety evidence are
        // different things. This classification therefore runs on EVERY
        // accepted response, BEFORE the authority check below, and it is
        // passive with respect to effects: it never reserves, arms, prints,
        // kicks a drawer, merges session state, clears a disclosure or
        // publishes UI.
        //
        // R-A was exactly the opposite order. The stale branch returned before
        // the store was ever consulted, so a durable terminal REFUSAL
        // contradicting this acceptance was never discovered, nothing durable
        // recorded it, and the rebuilt controller hydrated "clear" and minted a
        // SECOND identity for money that had already moved.
        // ===================================================================
        final evidenceSource = armEffects
            ? BlockEvidenceSource.directSend
            : BlockEvidenceSource.passiveStatusLookup;
        try {
          await _reconcileAcceptedSafetyEvidence(
            store: store,
            scope: scope,
            attempt: attempt,
            resolution: resolution,
            evidenceSource: evidenceSource,
            // The one thing the generation is asked on the safety path, and
            // only this: "is anyone going to write this acceptance down?". If a
            // replaced controller is holding it, nobody is, so an unresolved
            // parent has to be latched rather than left to a writer that is
            // never coming.
            latchPendingSameAttempt: () => !_stillAuthoritative(gen),
          );
        } catch (_) {
          // LAST RESORT, and deliberately silent. Containment is best effort;
          // the server has ALREADY taken this money, so an exception escaping
          // here would replace "your payment went through" with a crash and
          // leave the cashier with nothing. Everything inside is total by
          // construction — the snapshot algebra does not throw, the registry is
          // pure, and the clock and id source are frozen in `build` — so this
          // catches only the genuinely unforeseen.
        }

        // S1-R4 / F001 — an acceptance from a replaced world may not claim the
        // one-time effect reservation, merge into the new world's session, or
        // publish into its UI. It still tells the caller the truth about its own
        // money, and under OD-2 the safety evidence above already stands.
        if (!_stillAuthoritative(gen)) {
          final disclosed = attempt.accepted(
            resolution,
            // Frozen clock here too. `ref` is legal again at this point — the
            // containment above has already run — but this line builds the
            // honest money answer for a caller whose world may be the very one
            // that went away, and there is no reason to let the disclosure
            // throw when the evidence did not.
            at: _safetyNowIso(),
            reserveEffects: false,
          );
          return PaymentAttemptAccepted(
            attempt: disclosed,
            payment: disclosed.payment!,
            replay: resolution.replay,
            automaticEffectsArmed: false,
            // THIS call persisted nothing.
            localSaveFailed: true,
          );
        }

        try {
          final acceptance = await store.resolveAccepted(
            scope,
            attempt,
            resolution,
            at: now,
            armCaller: armEffects,
            // S1-R5 / F001: the check above happens BEFORE the store's
            // physical-key queue is entered, so it cannot see authority lapse
            // while this closure waits its turn. The store re-evaluates this
            // predicate inside the same serialized mutation, immediately
            // before it writes or reserves anything.
            authority: () => _stillAuthoritative(gen),
          );
          resolved = acceptance.attempt;
          armed = acceptance.armed;
        } catch (_) {
          saved = false;
          // SECOND PASS - AND IT IS NOT REDUNDANT.
          //
          // The first pass reads the envelope OUTSIDE the store's write queue
          // (`readEnvelopeSnapshot` is documented as a queue-free read), while
          // `resolveAccepted` adjudicates INSIDE it. Another writer can
          // terminalize this very record in that gap - a concurrent
          // `checkStatus` resolution, a second tab, another isolate - so the
          // store routinely discovers a contradiction the pre-read could not
          // see. THIS THROW IS THAT DISCOVERY: `reconcilePaymentAttempt`
          // answered `conflict` because a terminal answer now stands.
          //
          // Without this pass the first pass had classified the record as a
          // PENDING same attempt, correctly done nothing, and left a durable
          // `refused` record with no block beside an empty registry - so the
          // next confirm hydrates `SafetyClear` and mints a SECOND identity for
          // money that already moved. That is R-A reinstated through the
          // concurrency door instead of the generation door.
          //
          // It cannot double-write: `installIncidentIfAbsent` never replaces an
          // existing incident, and `promoteIncidentToDurable` refuses with
          // `SubjectBlockPresent` before writing when a block already stands.
          // The cost is one extra snapshot read on a path that has already
          // failed.
          try {
            await _reconcileAcceptedSafetyEvidence(
              store: store,
              scope: scope,
              attempt: attempt,
              resolution: resolution,
              evidenceSource: evidenceSource,
              // DELIBERATELY FALSE, even though this finalize just failed.
              //
              // What this pass is for is what the STORE discovered and the
              // pre-read could not: a terminal contradiction (class C) or a
              // record that is gone (class D). A parent still read as PENDING
              // is a different thing - a write that did not stick - and it is
              // already contained without a latch, because a pending record is
              // adopted by the `pending` arm under its own identity and can
              // only be RESUMED, never replaced by a new one. Latching it here
              // would fail-close an order after any transient storage hiccup,
              // which is a cost with no safety gain. The stale case is already
              // decided by the first pass.
              latchPendingSameAttempt: () => false,
            );
          } catch (_) {
            // As above: containment is best effort, and never an exception in
            // place of the caller's money outcome.
          }
        }
        final payment = resolved.payment!;
        // In memory the attempt IS resolved either way — the server said so.
        // On disk it stays pending when the save failed, and resolves again
        // (as a replay) on the next resume. Effects are NEVER armed without
        // the durable reservation: a missed automatic receipt is recoverable
        // by the manual reprint; a duplicate is not.
        _setAttempt(gen, resolved);
        final sameWorld = _mergePayment(
          gen,
          scope,
          session,
          resolved.identityKey,
          payment,
          armed: saved && armed,
        );
        return PaymentAttemptAccepted(
          attempt: resolved,
          payment: payment,
          replay: resolution.replay,
          // The automatic receipt/drawer fire ONLY in the world this payment
          // was taken in. A till re-paired into another branch (or signed in
          // as someone else) mid-flight must not push this order's paper out
          // of the new branch's printer; the reservation is spent, the sheet
          // says the receipt is unconfirmed, and the manual reprint stands.
          automaticEffectsArmed: saved && armed && sameWorld,
          localSaveFailed: !saved,
        );
      case PaymentSendRefused(:final code, :final memoized):
        // S1-F004 — AMBIGUITY IS MONOTONIC.
        //
        // Once a send of this attempt may have executed, a later answer that
        // only proves the LATER invocation was refused before the server
        // reached its operation ledger says nothing about the earlier one. The
        // previous build retired the attempt on any refusal, so a transient
        // no-open-shift on the retry freed the original identity and the next
        // Confirm minted a replacement — while the first request had already
        // completed a payment.
        //
        // A refusal is terminal only when it carries the ledger's own memoized
        // evidence for THIS identity. Everything else leaves the attempt
        // exactly as it was: same key, same target, same frozen bytes, still
        // blocking a replacement.
        // S1-R3 / F004: the test is the MONOTONIC durable fact, not the
        // latest enum. `lastOutcome` holds only the most recent answer, so
        // `unconfirmed -> authRequired -> non-memoized refusal` erased the
        // ambiguity and retired an identity whose money may already have
        // moved; and a FAILED ambiguity-marker write left the durable record
        // reading `none`, so a rebuilt controller reading that record made the
        // same mistake. `mayHaveExecuted` is stamped in the pre-dispatch write
        // and never cleared, so it survives both.
        if (!memoized && attempt.mayHaveExecuted) {
          _setAttempt(gen, attempt);
          return PaymentAttemptUnconfirmed(
            attempt: attempt,
            reason: PaymentUnconfirmedReason.transport,
          );
        }
        // PDR-006 — a refusal of THIS attempt is recorded as exactly that.
        //
        // The previous build asked whether the ORDER was paid and, if it was,
        // rewrote the outcome as "settled by another attempt". A paid order
        // cannot say which operation paid it: `pos_order_snapshots` and
        // `pos_order_detail` expose no `device_id` and no
        // `local_operation_id`. That inference could therefore attribute this
        // cashier's refused attempt to an imaginary other till. Order-level
        // paid state is still shown on the row; it never resolves an attempt.
        final resolved = attempt.refused(code, at: now, memoized: memoized);
        // S1-R3 / F004: the outcome of this write is REPORTED, not swallowed.
        // S1-R4 / F001: and it is only attempted while this world is still the
        // authoritative one.
        var localSaveFailed = false;
        if (!_stillAuthoritative(gen)) {
          localSaveFailed = true;
        } else {
          try {
            final merge = await store.update(scope, resolved);
            // A refusal the store did NOT apply — because a newer terminal
            // answer already stands, or because the two disagree — is not a
            // recorded refusal, and the cashier is told so.
            localSaveFailed = !merge.writes;
            // K3-B06 rule B — a LIVE DURABLE ACCEPTED record OUTRANKS a later
            // refusal, in the PUBLIC answer as well as on disk.
            //
            // `reconcilePaymentAttempt` already refuses the downgrade: a stored
            // terminal acceptance versus a proposed terminal refusal is a
            // `conflict`, and `merge.record` is then the record that STANDS —
            // the stored accepted one. Reporting `PaymentAttemptRefused` here
            // told the cashier that captured money had been refused. The
            // public answer now matches what the store kept.
            //
            // The EXACT frozen decision is required. `reconcilePaymentAttempt`
            // returns `conflict` for two different reasons: a different
            // terminal answer for the SAME decision, and a proposal that is not
            // about this decision at all (its first rule,
            // `!current.describesSameDecisionAs(proposed)`). Only the first is
            // a live acceptance of THIS attempt; publishing the second would
            // hand the cashier another decision's payment.
            final live = merge.record;
            if (!merge.writes &&
                live.phase == PaymentAttemptPhase.accepted &&
                live.describesSameDecisionAs(resolved)) {
              final livePayment = live.payment;
              if (livePayment != null) {
                _setAttempt(gen, live);
                // The same reconciliation the sibling accepted path performs:
                // the payment must land in session state, and the refusal
                // disclosure must be cleared, or the cashier keeps seeing a
                // refusal banner over a settled order.
                _mergePayment(
                  gen,
                  scope,
                  session,
                  live.identityKey,
                  livePayment,
                  // NEVER re-armed: the one-time effect claim was consumed when
                  // this acceptance was first written.
                  armed: false,
                );
                if (_stillAuthoritative(gen)) {
                  _clearDisclosure(
                    scope,
                    PosOrderIdentity.of(
                      orderId: live.orderId,
                      orderNumber: live.orderNumber,
                    ),
                    live,
                  );
                }
                return PaymentAttemptAccepted(
                  attempt: live,
                  payment: livePayment,
                  replay: true,
                  automaticEffectsArmed: false,
                  // The acceptance IS durably recorded — it is the live record
                  // — so this device's record is the proof.
                  localSaveFailed: false,
                );
              }
            }
          } catch (_) {
            localSaveFailed = true;
          }
        }
        _setAttempt(gen, resolved);
        if (resolved.phase == PaymentAttemptPhase.settledElsewhere) {
          return PaymentAttemptSettledElsewhere(resolved);
        }
        // S1-R4 / F004e: both truths are recorded where a recreated sheet and
        // a rebuilt provider can still find them. The exact refusal stays
        // exact; the failed save is a separate fact beside it.
        //
        // S1-R5 / F004: and ONLY by a callback that still speaks for this
        // device. R4 refused the stale durable WRITE but still called
        // `_discloseForAttempt` unconditionally, so a superseded operation A's
        // refusal became the banner shown for the newer accepted operation B
        // on the same order. Record and disclosure now require the same
        // authority; a stale callback still reports its own outcome to its own
        // awaiting caller, and changes nothing the current world can see.
        if (_stillAuthoritative(gen)) {
          final identity = PosOrderIdentity.of(
            orderId: attempt.orderId,
            orderNumber: attempt.orderNumber,
          );
          if (localSaveFailed) {
            _discloseForAttempt(
              scope,
              identity,
              resolved,
              PaymentAttemptDisclosure(
                refusalCode: code,
                localSaveFailed: true,
              ),
            );
          } else {
            _clearDisclosure(scope, identity, resolved);
          }
        }
        return PaymentAttemptRefused(
          attempt: resolved,
          code: code,
          localSaveFailed: localSaveFailed,
        );
      case PaymentSendUnconfirmed(:final reason):
        final marked = attempt.withLastOutcome(
          reason == PaymentUnconfirmedReason.identityCollision
              ? PaymentAttemptLastOutcome.collision
              : PaymentAttemptLastOutcome.unconfirmed,
        );
        await _bestEffortUpdate(store, scope, marked, gen: gen);
        _setAttempt(gen, marked);
        return PaymentAttemptUnconfirmed(attempt: marked, reason: reason);
      case PaymentSendNotApplied():
        final marked = attempt.withLastOutcome(
          PaymentAttemptLastOutcome.notApplied,
        );
        await _bestEffortUpdate(store, scope, marked, gen: gen);
        _setAttempt(gen, marked);
        return PaymentAttemptNotApplied(marked);
      case PaymentSendAuthRequired():
        final marked = attempt.withLastOutcome(
          PaymentAttemptLastOutcome.authRequired,
        );
        await _bestEffortUpdate(store, scope, marked, gen: gen);
        _setAttempt(gen, marked);
        return PaymentAttemptAuthRequired(marked);
    }
  }

  Future<bool> _bestEffortUpdate(
    PaymentAttemptStore store,
    PosSyncScope scope,
    PaymentAttempt attempt, {
    required int gen,
  }) async {
    // S1-R4 / F001: a diagnostic note from a world that has already been
    // replaced is not written at all. The record it would have touched belongs
    // to the current owner, which will reconcile it from the server's own
    // ledger; a stale completion is not evidence about the payment.
    if (!_stillAuthoritative(gen)) return false;
    try {
      final merge = await store.update(scope, attempt);
      return merge.writes;
    } catch (_) {
      // The record is already durable as `pending`; the last-outcome note is
      // advisory.
      return false;
    }
  }

  /// Merges an ACCEPTED payment into the session state — only when the world
  /// it was taken in is still the current one. [armed] marks the ONE edge at
  /// which this process may fire the automatic receipt/drawer triggers.
  /// Returns whether the merge happened, i.e. whether the world this payment
  /// was taken in is still the current one.
  bool _mergePayment(
    int gen,
    PosSyncScope scope,
    SyncSession session,
    String identityKey,
    CashPayment payment, {
    bool armed = false,
  }) {
    if (gen != _generation) return false;
    // STALE SCOPE / SESSION. The till was re-paired or re-signed-in while this
    // payment was in flight. The payment itself is REAL — the server took it —
    // but it must not be merged into the NEW world's session state, where it
    // would roll a different branch's cash into this one's drawer figure. It
    // stays durable in its own scope's store and on the server.
    if (ref.read(posSyncScopeProvider)?.key != scope.key) return false;
    if (ref.read(posSyncSessionProvider)?.pinSessionId !=
        session.pinSessionId) {
      return false;
    }
    state = state.copyWith(
      shift: _repo.shiftContext(),
      payments: {...state.payments, identityKey: payment},
      effectsArmed: armed
          ? {...state.effectsArmed, identityKey}
          : state.effectsArmed,
    );
    return true;
  }

  /// READ-ONLY: what became of the pending attempt for [identity]? Executes
  /// nothing on the server; resolves the local record only from the ledger's
  /// stored outcome (plus the by-id order read for "settled elsewhere").
  Future<PaymentAttemptStatusCheck> checkStatus(
    PosOrderIdentity identity,
  ) async {
    final repo = _repo;
    if (repo is! PaymentAttemptSender) {
      return const PaymentAttemptStatusNothingPending();
    }
    final sender = repo as PaymentAttemptSender;
    final scope = ref.read(posSyncScopeProvider);
    final session = ref.read(posSyncSessionProvider);
    final store = ref.read(paymentAttemptStoreProvider);
    final gen = _generation;
    if (scope == null || session == null) {
      return const PaymentAttemptStatusCheckUnavailable('no_scope');
    }
    await ensureHydrated();
    final attempt = state.pendingAttemptFor(identity);
    if (attempt == null) return const PaymentAttemptStatusNothingPending();
    if (_inFlight.contains(identity.key)) {
      return PaymentAttemptStatusStillPending(attempt);
    }
    final lookup = await sender.lookupAttemptStatus(attempt);
    switch (lookup) {
      case PaymentAttemptStatusApplied(:final resolution):
        return PaymentAttemptStatusResolved(
          await _resolve(
            gen: gen,
            scope: scope,
            session: session,
            store: store,
            attempt: attempt,
            armEffects: false,
            result: PaymentSendAccepted(resolution),
          ),
        );
      case PaymentAttemptStatusRefused(:final code):
        return PaymentAttemptStatusResolved(
          await _resolve(
            gen: gen,
            scope: scope,
            session: session,
            store: store,
            attempt: attempt,
            armEffects: false,
            result: PaymentSendRefused(code, memoized: true),
          ),
        );
      case PaymentAttemptStatusCollision():
        return PaymentAttemptStatusResolved(
          await _resolve(
            gen: gen,
            scope: scope,
            session: session,
            store: store,
            attempt: attempt,
            armEffects: false,
            result: const PaymentSendUnconfirmed(
              PaymentUnconfirmedReason.identityCollision,
            ),
          ),
        );
      case PaymentAttemptStatusInProgress():
        // The server holds our row undecided: still pending, nothing more.
        return PaymentAttemptStatusStillPending(attempt);
      case PaymentAttemptStatusNotFound():
        // PDR-006 — ABSENCE IS NOT ATTRIBUTION.
        //
        // No matching ledger row means the request never arrived, is still
        // executing, or its row is outside the window this bounded scan can
        // see (retention, a timestamp gap, delayed visibility). None of that
        // is evidence about THIS attempt, and a paid order does not identify
        // the operation that paid it. The record stays unresolved and keeps
        // blocking a replacement identity until exact terminal evidence
        // arrives or an explicit recovery policy is defined.
        return PaymentAttemptStatusStillPending(attempt);
      case PaymentAttemptStatusUnavailable(:final reason):
        return PaymentAttemptStatusCheckUnavailable(reason);
    }
  }

  /// Re-sends the PENDING attempt for [identity] under its frozen identity and
  /// inputs. An explicit cashier action — never automatic.
  Future<PaymentAttemptOutcome> resumeAttempt(PosOrderIdentity identity) async {
    await ensureHydrated();
    final attempt = state.pendingAttemptFor(identity);
    if (attempt == null) return const PaymentAttemptSaveBlocked();
    return submitAttempt(
      identity: identity,
      orderId: attempt.orderId,
      orderNumber: attempt.orderNumber,
      amountMinor: attempt.amountMinor,
      tenderedMinor: attempt.amountTenderedMinor,
      currencyCode: attempt.currencyCode,
      method: attempt.method,
      expectedRevision: attempt.expectedRevision,
    );
  }

  /// The pre-durable path: the demo store and hand-written repositories that
  /// implement only [PaymentRepository]. Frozen inputs + the single-flight
  /// guard still apply; there is no server and nothing to recover.
  Future<PaymentAttemptOutcome> _submitLegacy({
    required PosOrderIdentity identity,
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    required PaymentMethod method,
    required int? expectedRevision,
  }) async {
    final key = identity.key;
    if (_inFlight.contains(key)) return const PaymentAttemptBusy(null);
    final scopeKey = ref.read(posSyncScopeProvider)?.key;
    final gen = _generation;
    _inFlight.add(key);
    try {
      final CashPayment payment;
      try {
        payment = await _repo.recordCashPayment(
          orderId: orderId,
          orderNumber: orderNumber,
          amountMinor: amountMinor,
          tenderedMinor: tenderedMinor,
          currencyCode: currencyCode,
          method: method,
          expectedRevision: expectedRevision,
        );
      } on PaymentException catch (e) {
        return _legacyOutcome(e);
      }
      if (gen == _generation &&
          ref.read(posSyncScopeProvider)?.key == scopeKey) {
        state = state.copyWith(
          shift: _repo.shiftContext(),
          payments: {...state.payments, key: payment},
          // The legacy path has no durable attempt to reserve: every call IS
          // a real payment edge, exactly as before this ticket.
          effectsArmed: {...state.effectsArmed, key},
        );
      }
      return PaymentAttemptAccepted(
        attempt: _legacyAttempt(payment, identity, expectedRevision),
        payment: payment,
        replay: false,
        automaticEffectsArmed: true,
        localSaveFailed: false,
      );
    } finally {
      _inFlight.remove(key);
    }
  }

  static PaymentAttempt _legacyAttempt(
    CashPayment p,
    PosOrderIdentity identity,
    int? expectedRevision,
  ) => PaymentAttempt(
    localOperationId: p.localOperationId,
    targetId: p.paymentId,
    clientCreatedAt: p.paidAt.toUtc().toIso8601String(),
    identityKey: identity.key,
    orderId: p.orderId ?? '',
    orderNumber: p.orderNumber,
    expectedRevision: expectedRevision,
    tenderType: p.method.wire,
    amountMinor: p.amountMinor,
    amountTenderedMinor: p.tenderedMinor,
    currencyCode: p.currencyCode,
    organizationId: '',
    restaurantId: '',
    branchId: '',
    deviceId: p.deviceId,
    employeeProfileId: null,
    phase: PaymentAttemptPhase.accepted,
    lastOutcome: PaymentAttemptLastOutcome.none,
    sentAt: null,
    resolvedAt: null,
    resolution: PaymentAttemptResolution(
      paymentId: p.paymentId,
      receiptNumber: p.receiptNumber,
      changeDueMinor: p.changeMinor,
      method: p.method,
      replay: false,
      orderStatus: p.orderStatus,
    ),
    refusal: null,
    refusalMemoized: false,
    autoEffectsReservedAt: null,
    supersedes: null,
  );

  /// Maps a legacy repository's typed exception onto the outcome vocabulary so
  /// the sheet has ONE switch. No durable record exists on this path, so
  /// unconfirmed/not-applied are reported without an attempt.
  PaymentAttemptOutcome _legacyOutcome(PaymentException e) {
    PaymentAttempt placeholder() => PaymentAttempt(
      localOperationId: '',
      targetId: '',
      clientCreatedAt: '',
      identityKey: '',
      orderId: '',
      orderNumber: '',
      expectedRevision: null,
      tenderType: e.attempt?.method.wire ?? PaymentMethod.cash.wire,
      amountMinor: e.attempt?.amountMinor ?? 0,
      amountTenderedMinor: e.attempt?.amountTenderedMinor ?? 0,
      currencyCode: e.attempt?.currencyCode ?? '',
      organizationId: '',
      restaurantId: '',
      branchId: '',
      deviceId: '',
      employeeProfileId: null,
      phase: PaymentAttemptPhase.pending,
      lastOutcome: PaymentAttemptLastOutcome.none,
      sentAt: null,
      resolvedAt: null,
      resolution: null,
      refusal: null,
      refusalMemoized: false,
      autoEffectsReservedAt: null,
      supersedes: null,
    );
    if (e.notChargeable) {
      return PaymentAttemptRefused(
        attempt: placeholder(),
        code: PaymentRefusalCode.notChargeable,
      );
    }
    if (e.conflict) {
      return PaymentAttemptRefused(
        attempt: placeholder(),
        code: PaymentRefusalCode.revisionConflict,
      );
    }
    if (e.shiftRequired) {
      return PaymentAttemptRefused(
        attempt: placeholder(),
        code: PaymentRefusalCode.shiftRequired,
      );
    }
    if (e.unconfirmed) {
      return PaymentAttemptUnconfirmed(
        attempt: placeholder(),
        reason: PaymentUnconfirmedReason.transport,
      );
    }
    if (e.authRequired) return PaymentAttemptAuthRequired(placeholder());
    if (e.saveBlocked) return const PaymentAttemptSaveBlocked();
    // Every other legacy failure keeps its historical meaning: a plain,
    // retryable failure with no durable attempt behind it.
    return PaymentAttemptRefused(
      attempt: placeholder(),
      code: PaymentRefusalCode.generic,
    );
  }

  /// The payment recorded for [identity] this session, or null.
  CashPayment? paymentFor(PosOrderIdentity identity) =>
      state.paymentFor(identity);
}

/// The cash-payment repository. Selects by client runtime mode (M7): the
/// in-memory [DemoPaymentStore] in demo mode (the DEFAULT), or the real
/// [RealPaymentRepository] in real mode (RF-130), which posts a `payment.create`
/// op to `public.sync_push` over the shared [posAuthTransportProvider] transport
/// and [posSyncSessionProvider] session (RF-131); with no transport or no session
/// it fails closed. Tests can override this provider, [runtimeConfigProvider],
/// [posAuthTransportProvider], or [posSyncSessionProvider] to force a mode.
final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  final cfg = ref.watch(runtimeConfigProvider);
  if (cfg.isDemoMode) return DemoPaymentStore();
  return RealPaymentRepository(
    ref.watch(posAuthTransportProvider),
    ref.watch(posSyncSessionProvider),
    ref.watch(clientIdGeneratorProvider),
    clock: ref.watch(posSyncClockProvider),
  );
});

/// The POS payment controller (shift context + recorded payments).
final paymentControllerProvider =
    NotifierProvider<PaymentController, PaymentState>(PaymentController.new);
