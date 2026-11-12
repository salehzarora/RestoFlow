/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F — the provider-card controller: the POS
/// side of the integrated card lifecycle (execution packet §6–§10).
///
/// It owns no money rule of its own: the server decides every outcome, and the
/// controller only (1) persists the attempt before anything leaves the device,
/// (2) sends exactly the frozen bytes, at most one request at a time per
/// attempt, (3) records what each answer PROVES, and (4) offers the next safe
/// action. It never retries automatically, never sends `start` again after an
/// uncertain one, never mints a replacement, and never calls the provider while
/// recording or resuming.
///
/// Automatic work is limited to: status checks while a visible card view holds
/// a foreground lease (bounded, single-flight, backing off), the FIRST send of
/// the recording leg right after an envelope said `approved_unrecorded` (that
/// answer is the fresh context proof), and the refusal report that follows a
/// refused leg (API_CONTRACT §4.55.7); a report that could not be delivered
/// then goes with the next explicit Check status or Resume. Everything else
/// is an explicit action.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceSessionSecretStore;
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../data/ids.dart';
import '../data/online_order_inbox.dart'
    show onlineOrderInboxSecretStoreProvider;
import '../data/order_identity.dart';
import '../data/provider_card_attempt.dart';
import '../data/provider_card_capability.dart';
import '../data/provider_card_edge.dart';
import '../data/provider_card_recording.dart';
import '../data/provider_card_store.dart';
import '../data/sync_cursor_store.dart' show PosSyncScope;
import 'discount_controller.dart'
    show staffCapabilitiesProvider, staffCapabilitiesRepositoryProvider;
import 'order_sync_controller.dart' show posSyncClockProvider;
import 'pos_session.dart'
    show
        posAuthTransportProvider,
        posSignedInEmployeeProfileIdProvider,
        posSyncSessionProvider;
import 'pos_sync_scope_provider.dart' show posSyncScopeProvider;

// ---------------------------------------------------------------------------
// Posture and the lab toggle (packet §9)
// ---------------------------------------------------------------------------

/// The posture the payment sheet acts on, whether the probe is still answering,
/// and whether it comes from the probe at all ([probed] is false where no card
/// call is possible: demo, no transport, no session).
@immutable
class ProviderCardPostureView {
  const ProviderCardPostureView(
    this.posture, {
    required this.loading,
    this.probed = true,
  });
  final ProviderCardPosture posture;
  final bool loading;
  final bool probed;
}

/// The card posture the last fresh read of this till found
/// ([ProviderCardController.readPosture]): newer than the PIN-session probe
/// until the probe answers again or the PIN session changes. A fresh read
/// never refreshes the probe itself: every capability of the PIN session
/// hangs on it, and a read that fails must leave them as they were.
final providerCardFreshPostureProvider = StateProvider<ProviderCardPosture?>((
  ref,
) {
  ref.watch(posSyncSessionProvider);
  ref.watch(staffCapabilitiesProvider.select((caps) => caps.valueOrNull));
  return null;
});

/// The till's posture: from the PIN-session probe the POS already makes
/// (`staffCapabilitiesProvider`) or a fresh read newer than it
/// ([providerCardFreshPostureProvider]), absent where no card call is
/// possible at all (demo, no transport, no session), unknown while the probe
/// has not answered or after it failed: no integrated start is offered then,
/// and a hand-recorded Card send reads the posture again first (packet §9.1).
final providerCardPostureProvider = Provider<ProviderCardPostureView>((ref) {
  final cfg = ref.watch(runtimeConfigProvider);
  final transport = ref.watch(posAuthTransportProvider);
  final session = ref.watch(posSyncSessionProvider);
  if (cfg.isDemoMode || transport == null || session == null) {
    return const ProviderCardPostureView(
      ProviderCardPostureAbsent(),
      loading: false,
      probed: false,
    );
  }
  final fresh = ref.watch(providerCardFreshPostureProvider);
  if (fresh != null) return ProviderCardPostureView(fresh, loading: false);
  final caps = ref.watch(staffCapabilitiesProvider);
  return caps.when(
    data: (c) => ProviderCardPostureView(
      c == null ? const ProviderCardPostureUnknown() : c.cardTerminal,
      loading: false,
    ),
    loading: () => const ProviderCardPostureView(
      ProviderCardPostureUnknown(),
      loading: true,
    ),
    error: (_, _) => const ProviderCardPostureView(
      ProviderCardPostureUnknown(),
      loading: false,
    ),
  );
});

/// The per-device TEST lab toggle (packet §9.3): in memory only, default OFF,
/// reset by every PIN-session change. UX only — it never overrides the server
/// posture and never applies to LIVE. It decides only whether a NEW TEST
/// attempt may start: an unresolved one stays shown and recoverable without it
/// (correction packet §4).
final providerCardLabEnabledProvider = StateProvider<bool>((ref) {
  ref.watch(posSyncSessionProvider);
  return false;
});

// ---------------------------------------------------------------------------
// Polling policy (packet §10)
// ---------------------------------------------------------------------------

@immutable
class ProviderCardPollPolicy {
  const ProviderCardPollPolicy({
    this.firstDelay = const Duration(seconds: 3),
    this.interval = const Duration(seconds: 4),
    this.backoff = const <Duration>[
      Duration(seconds: 8),
      Duration(seconds: 16),
      Duration(seconds: 30),
    ],
    this.budget = 60,
  });

  /// The first automatic check after a view attaches.
  final Duration firstDelay;

  /// Between readable answers (the Edge enforces 3 s between lookups).
  final Duration interval;

  /// After consecutive unreadable / unavailable / uncertain answers; the last
  /// step repeats.
  final List<Duration> backoff;

  /// Automatic checks per foreground lease, then a manual check is asked for.
  final int budget;
}

final providerCardPollPolicyProvider = Provider<ProviderCardPollPolicy>(
  (ref) => const ProviderCardPollPolicy(),
);

/// The process-wide monotonic clock the settle window is also measured on
/// (packet §7.3): a wall-clock step never shortens it.
final Stopwatch _processClock = Stopwatch()..start();

final providerCardMonotonicProvider = Provider<Duration Function()>(
  (ref) =>
      () => _processClock.elapsed,
);

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// What is in flight for an attempt (one request at a time).
enum ProviderCardBusy { starting, checking, releasing, recording, resuming }

/// A transient note about the last action, where the attempt itself did not
/// change (packet §6: a status failure never changes the attempt).
enum ProviderCardNote {
  notSent,
  signInAgain,
  refusedBeforeProcessing,
  unavailable,
  pollLimit,
  autoChecksPaused,
  releaseNotConfirmed,
  saveFailed,
  managerRequired,
  managerProofUnavailable,
  notRecoverable,
  roleCannot,
  terminalUnavailable,
  postureUnknown,
}

/// The answer to a start request.
enum ProviderCardStartRequest {
  /// A new attempt was persisted and its `start` was sent.
  started,

  /// An open attempt of the same order and mode exists; it is shown instead.
  adopted,

  /// The posture does not permit a new start of this mode now.
  notPermitted,

  /// The inputs cannot form a valid `start` (no authoritative order, amount,
  /// currency or revision).
  invalid,

  /// A stored card record cannot be read: new starts are blocked.
  quarantined,

  /// The journal holds its [kProviderCardJournalCap] records and none of them
  /// is safe and final enough to drop (correction packet §5): nothing was
  /// minted, saved or sent. Resolving existing attempts makes room; they stay
  /// usable meanwhile. Not a quarantine.
  journalFull,

  /// The attempt could not be durably saved: NOTHING was sent.
  saveBlocked,

  /// Another request for this order is already in flight.
  busy,

  /// No scope or session (not signed in on a paired till).
  unavailable,
}

@immutable
class ProviderCardState {
  const ProviderCardState({
    required this.hydrated,
    required this.quarantined,
    required this.byIdentity,
    this.busy = const <String, ProviderCardBusy>{},
    this.notes = const <String, ProviderCardNote>{},
    this.receiptArmed = const <String>{},
    this.autoPaused = const <String>{},
  });

  /// False until the journal was read for the current scope.
  final bool hydrated;

  /// A stored record or envelope cannot be read: new starts are blocked.
  final bool quarantined;

  /// The readable attempts per order identity key, oldest first.
  final Map<String, List<ProviderCardAttempt>> byIdentity;

  /// attempt id → the request in flight.
  final Map<String, ProviderCardBusy> busy;

  /// attempt id → the last action's note.
  final Map<String, ProviderCardNote> notes;

  /// Attempt ids whose ONE automatic receipt this process reserved and the
  /// sheet has not consumed yet.
  final Set<String> receiptArmed;

  /// Attempt ids whose automatic checks stopped (`poll_limit` or the lease
  /// budget); Check status remains.
  final Set<String> autoPaused;

  ProviderCardAttempt? byId(String attemptId) {
    for (final list in byIdentity.values) {
      for (final a in list) {
        if (a.attemptId == attemptId) return a;
      }
    }
    return null;
  }

  /// The attempt the payment sheet shows for [identity]: an open LIVE attempt,
  /// else an open TEST one — whatever [includeTest] says, since an unresolved
  /// TEST attempt stays recoverable (correction packet §4) — else the newest
  /// attempt of the shown modes (a final TEST result only with
  /// [includeTest]). Null when the order has none.
  ProviderCardAttempt? currentFor(
    PosOrderIdentity identity, {
    required bool includeTest,
  }) {
    final list = byIdentity[identity.key];
    if (list == null || list.isEmpty) return null;
    final shown = [
      for (final a in list)
        if (includeTest || a.isLive || a.isOpen) a,
    ];
    if (shown.isEmpty) return null;
    for (final a in shown.reversed) {
      if (a.isLive && a.isOpen) return a;
    }
    for (final a in shown.reversed) {
      if (a.isOpen) return a;
    }
    return shown.last;
  }

  ProviderCardState copyWith({
    bool? hydrated,
    bool? quarantined,
    Map<String, List<ProviderCardAttempt>>? byIdentity,
    Map<String, ProviderCardBusy>? busy,
    Map<String, ProviderCardNote>? notes,
    Set<String>? receiptArmed,
    Set<String>? autoPaused,
  }) => ProviderCardState(
    hydrated: hydrated ?? this.hydrated,
    quarantined: quarantined ?? this.quarantined,
    byIdentity: byIdentity ?? this.byIdentity,
    busy: busy ?? this.busy,
    notes: notes ?? this.notes,
    receiptArmed: receiptArmed ?? this.receiptArmed,
    autoPaused: autoPaused ?? this.autoPaused,
  );
}

/// A visible card view's claim on automatic checks. [release] it when the view
/// is disposed or the app pauses.
class ProviderCardLease {
  ProviderCardLease._(this._onRelease);
  final void Function() _onRelease;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _onRelease();
  }
}

class _Poll {
  int leases = 0;
  int budget = 0;
  int failures = 0;
  Timer? timer;
}

/// What one `status` exchange proved: nothing, a readable answer, or an
/// envelope (the only answer that is a fresh context proof).
enum _StatusAnswer { none, readable, envelope }

// ---------------------------------------------------------------------------
// The controller
// ---------------------------------------------------------------------------

class ProviderCardController extends Notifier<ProviderCardState> {
  int _generation = 0;

  /// The generation of the world built last: none is current once the
  /// container is disposed.
  int _built = 0;
  Future<void>? _hydration;

  late ProviderCardStore _store;
  PosSyncScope? _scope;
  SyncSession? _session;
  SyncRpcTransport? _transport;
  DeviceSessionSecretStore? _secretStore;
  late ClientIdGenerator _ids;
  late DateTime Function() _clock;
  late ProviderCardPollPolicy _policy;

  /// attempt id → the status request in flight (an automatic and a manual
  /// check collide into this one request).
  final Map<String, Future<_StatusAnswer>> _statusInFlight =
      <String, Future<_StatusAnswer>>{};

  /// attempt id → how many of its exchanges are on the wire now, whatever
  /// world started them. A rebuild clears the in-memory request slot but
  /// cannot recall a request already handed off, so no new request for the
  /// attempt starts until it returns (packet §10).
  final Map<String, int> _onWire = <String, int>{};

  /// identity keys with a `start` request being prepared.
  final Set<String> _starting = <String>{};

  final Map<String, _Poll> _polls = <String, _Poll>{};

  /// attempt id → the operation running on it (its kind and the world that
  /// began it), whatever world is current. A rebuild cannot recall it: the
  /// new world shows the attempt busy until it ends, then reads what it
  /// stored (packet §10).
  final Map<String, ({int gen, ProviderCardBusy busy})> _running =
      <String, ({int gen, ProviderCardBusy busy})>{};

  /// attempt id → the in-doubt start send this process waits on (its
  /// `start_last_sent_at`, a stamp no other send of the attempt carries) and
  /// when it began to wait, on the monotonic clock: the end of a start
  /// exchange it ran, or the first time it saw that send — sound because a
  /// send that another controller world or an earlier process began can no
  /// longer be handed off once that world has ended or that process has died
  /// (packet §7.3). A wait on one send never measures another. Survives
  /// rebuilds; a new process starts over.
  final Map<String, ({String? sentAt, Duration since})> _inDoubtSince =
      <String, ({String? sentAt, Duration since})>{};

  /// The posture read in flight ([readPosture]).
  Future<ProviderCardPosture>? _postureRead;

  late Duration Function() _monotonic;

  @override
  ProviderCardState build() {
    _store = ref.watch(providerCardStoreProvider);
    _session = ref.watch(posSyncSessionProvider);
    _transport = ref.watch(posAuthTransportProvider);
    _secretStore = ref.watch(onlineOrderInboxSecretStoreProvider);
    _policy = ref.watch(providerCardPollPolicyProvider);
    // The journal belongs to tills where a card call is possible at all: demo
    // mode and a build without an RPC transport have no integrated card (the
    // posture is absent there too) and never touch it, as the base payment
    // controller hydrates only where it can send.
    final demo = ref.watch(runtimeConfigProvider).isDemoMode;
    _scope = demo || _transport == null
        ? null
        : ref.watch(posSyncScopeProvider);
    // A rebuild is a NEW WORLD: every late callback of the previous one must
    // leave this state alone, and no timer survives it. The leases of the
    // visible card views do (those views still show their attempts), and
    // hydration re-arms them.
    final gen = ++_generation;
    _built = gen;
    _ids = ref.read(clientIdGeneratorProvider);
    _clock = ref.read(posSyncClockProvider);
    _monotonic = ref.read(providerCardMonotonicProvider);
    _statusInFlight.clear();
    _starting.clear();
    _postureRead = null;
    _stopTimers();
    ref.onDispose(() {
      _stopTimers();
      // A late answer of a disposed world may not re-arm anything.
      _generation++;
    });
    final scope = _scope;
    _hydration = scope == null ? Future<void>.value() : _hydrate(gen, scope);
    return ProviderCardState(
      hydrated: scope == null,
      quarantined: false,
      byIdentity: const <String, List<ProviderCardAttempt>>{},
      // An operation an earlier world began is still running: its attempt
      // shows busy here until it ends.
      busy: <String, ProviderCardBusy>{
        for (final e in _running.entries) e.key: e.value.busy,
      },
    );
  }

  bool _current(int gen) => gen == _generation && gen == _built;

  /// The state of world [gen], or null once that world has ended. Reading
  /// [state] first runs a rebuild still pending (a dependency changed), and
  /// that rebuild ends the world, so the generation is checked after it.
  ProviderCardState? _stateOf(int gen) {
    if (!_current(gen)) return null;
    final s = state;
    return _current(gen) ? s : null;
  }

  String _now() => canonicalInstantOf(_clock());

  Future<void> _hydrate(int gen, PosSyncScope scope) async {
    final load = await _store.load(scope);
    if (!_current(gen)) return;
    final grouped = <String, List<ProviderCardAttempt>>{};
    final now = _monotonic();
    final inDoubt = <String>{};
    for (final a in load.attempts) {
      grouped.putIfAbsent(a.identityKey, () => <ProviderCardAttempt>[]).add(a);
      // An in-doubt start: a wait this process began on that very send
      // stands; any other send's settle window is measured from now on the
      // monotonic clock (packet §7.3).
      if (a.server == null && !a.startHasNoPossibleEffect) {
        inDoubt.add(a.attemptId);
        final held = _inDoubtSince[a.attemptId];
        if (held == null || held.sentAt != a.startLastSentAt) {
          _inDoubtSince[a.attemptId] = (sentAt: a.startLastSentAt, since: now);
        }
      }
    }
    _inDoubtSince.removeWhere((id, _) => !inDoubt.contains(id));
    final s = _stateOf(gen);
    if (s == null) return;
    state = s.copyWith(
      hydrated: true,
      quarantined: load.blocksNewStarts,
      byIdentity: grouped,
    );
    // Views that kept their lease across the rebuild resume their checks.
    for (final id in _polls.keys.toList()) {
      _kick(gen, id);
    }
  }

  void _stopTimers() {
    for (final p in _polls.values) {
      p.timer?.cancel();
      p.timer = null;
    }
  }

  /// Completes once the journal was read for the current scope.
  Future<void> ensureHydrated() => _hydration ?? Future<void>.value();

  // ---- state helpers ------------------------------------------------------

  void _put(int gen, ProviderCardAttempt a) {
    _bind(a);
    final s = _stateOf(gen);
    if (s == null) return;
    final by = <String, List<ProviderCardAttempt>>{
      for (final e in s.byIdentity.entries)
        e.key: List<ProviderCardAttempt>.of(e.value),
    };
    final list = by.putIfAbsent(a.identityKey, () => <ProviderCardAttempt>[]);
    final i = list.indexWhere((x) => x.attemptId == a.attemptId);
    if (i < 0) {
      list.add(a);
    } else {
      list[i] = a;
    }
    state = s.copyWith(byIdentity: by);
    _kick(gen, a.attemptId);
  }

  /// Keeps the settle-window wait of [a] bound to the send it measures
  /// (packet §7.3): a wait on another send, or on a record that cannot be in
  /// doubt any more, is dropped.
  void _bind(ProviderCardAttempt a) {
    final held = _inDoubtSince[a.attemptId];
    if (held != null &&
        (held.sentAt != a.startLastSentAt ||
            a.server != null ||
            a.startHasNoPossibleEffect)) {
      _inDoubtSince.remove(a.attemptId);
    }
  }

  void _setBusy(int gen, String id, ProviderCardBusy? busy) {
    if (busy == null && _running[id]?.gen == gen) {
      _running.remove(id);
      if (!_current(gen)) {
        // An operation an earlier world began has ended: the current world
        // shows what it stored, then stops showing the attempt busy.
        final now = _generation;
        if (_current(now)) unawaited(_reloadCarried(now, id));
        return;
      }
    }
    final s = _stateOf(gen);
    if (s == null) return;
    if (busy != null) _running[id] = (gen: gen, busy: busy);
    final next = Map<String, ProviderCardBusy>.of(s.busy);
    if (busy == null) {
      next.remove(id);
    } else {
      next[id] = busy;
    }
    state = s.copyWith(busy: next);
  }

  /// Shows in world [gen] what the journal holds for [attemptId] once this
  /// world's own hydration is done, then ends the busy it carried for an
  /// operation an earlier world ran on it (packet §10).
  Future<void> _reloadCarried(int gen, String attemptId) async {
    try {
      final scope = _scope;
      if (scope == null) return;
      await ensureHydrated();
      if (!_current(gen)) return;
      final load = await _store.load(scope);
      for (final a in load.attempts) {
        if (a.attemptId == attemptId) {
          _put(gen, a);
          break;
        }
      }
    } catch (_) {
      // Unread: the attempt shows what this world read last.
    } finally {
      _setBusy(gen, attemptId, null);
    }
  }

  void _note(int gen, String id, ProviderCardNote? note) {
    final s = _stateOf(gen);
    if (s == null) return;
    final next = Map<String, ProviderCardNote>.of(s.notes);
    if (note == null) {
      next.remove(id);
    } else {
      next[id] = note;
    }
    state = s.copyWith(notes: next);
  }

  void _pauseAuto(int gen, String id) {
    final s = _stateOf(gen);
    if (s == null) return;
    state = s.copyWith(autoPaused: {...s.autoPaused, id});
  }

  /// A transition that MUST be durable before a send, applied to the FRESHEST
  /// stored record. Null (and no state change) when it is not durable: the
  /// caller sends nothing.
  Future<ProviderCardAttempt?> _persistBeforeSend(
    int gen,
    PosSyncScope scope,
    String attemptId,
    ProviderCardAttempt Function(ProviderCardAttempt) transform,
  ) async {
    final ProviderCardAttempt written;
    try {
      written = await _store.update(scope, attemptId, transform);
    } catch (_) {
      _note(gen, attemptId, ProviderCardNote.saveFailed);
      return null;
    }
    _put(gen, written);
    return written;
  }

  /// Records what an answer proved, applied to the freshest stored record.
  /// When the write fails the knowledge is still kept in memory (the stored
  /// record then still reads "may have been sent", the conservative reading
  /// after a restart). Returns the record and whether it was saved.
  Future<(ProviderCardAttempt?, bool)> _persistAfter(
    int gen,
    PosSyncScope scope,
    String attemptId,
    ProviderCardAttempt Function(ProviderCardAttempt) transform,
  ) async {
    try {
      final written = await _store.update(scope, attemptId, transform);
      _put(gen, written);
      return (written, true);
    } catch (_) {
      final latest = _latest(attemptId);
      if (latest == null) return (null, false);
      final next = transform(latest);
      _put(gen, next);
      _note(gen, attemptId, ProviderCardNote.saveFailed);
      return (next, false);
    }
  }

  ProviderCardEdgeClient _edge(int gen) => ProviderCardEdgeClient(
    transport: _transport,
    session: _session,
    secretStore: _secretStore,
    isCurrent: () => _current(gen),
  );

  ProviderCardRecordingSender _sender() =>
      ProviderCardRecordingSender(transport: _transport, session: _session);

  ProviderCardAttempt? _latest(String attemptId) => state.byId(attemptId);

  bool _idle(String attemptId) =>
      !state.busy.containsKey(attemptId) &&
      !_statusInFlight.containsKey(attemptId) &&
      !_onWire.containsKey(attemptId);

  /// Runs one exchange of [attemptId] while marking it on the wire.
  Future<T> _wire<T>(String attemptId, Future<T> Function() exchange) async {
    _onWire.update(attemptId, (n) => n + 1, ifAbsent: () => 1);
    try {
      return await exchange();
    } finally {
      final left = (_onWire[attemptId] ?? 1) - 1;
      if (left <= 0) {
        _onWire.remove(attemptId);
      } else {
        _onWire[attemptId] = left;
      }
    }
  }

  // ---- posture --------------------------------------------------------------

  /// One fresh read of this till's card posture (packet §9.1), shared by every
  /// caller while it is under way. It never refreshes the PIN-session probe
  /// every capability of the session hangs on (`staffCapabilitiesProvider`):
  /// a read that fails leaves the probe's answer as it was and is unknown, and
  /// one that succeeds publishes only the card posture it found
  /// ([providerCardFreshPostureProvider]). Where no card call is possible at
  /// all nothing is read.
  Future<ProviderCardPosture> readPosture() {
    final view = ref.read(providerCardPostureProvider);
    if (!view.probed) return Future<ProviderCardPosture>.value(view.posture);
    final inFlight = _postureRead;
    if (inFlight != null) return inFlight;
    final run = _readPostureOnce();
    _postureRead = run;
    unawaited(
      run.whenComplete(() {
        if (identical(_postureRead, run)) _postureRead = null;
      }),
    );
    return run;
  }

  Future<ProviderCardPosture> _readPostureOnce() async {
    try {
      final repository = ref.read(staffCapabilitiesRepositoryProvider);
      final caps = await repository.fetch();
      // An answer for a PIN session no longer signed in decides nothing.
      if (caps == null ||
          !identical(
            ref.read(staffCapabilitiesRepositoryProvider),
            repository,
          )) {
        return const ProviderCardPostureUnknown();
      }
      ref.read(providerCardFreshPostureProvider.notifier).state =
          caps.cardTerminal;
      return caps.cardTerminal;
    } catch (_) {
      return const ProviderCardPostureUnknown();
    }
  }

  // ---- start ----------------------------------------------------------------

  /// Starts a NEW integrated card attempt for the order — an explicit cashier
  /// action. Adopts an open attempt of the same order and mode instead of
  /// creating a second.
  Future<ProviderCardStartRequest> start({
    required PosOrderIdentity identity,
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required String currencyCode,
    required int? expectedRevision,
    required ProviderCardMode mode,
  }) async {
    final gen = _generation;
    final scope = _scope;
    final session = _session;
    // Everything read from `ref` is read before the first await.
    final posture = ref.read(providerCardPostureProvider).posture;
    final lab = ref.read(providerCardLabEnabledProvider);
    final employee = ref.read(posSignedInEmployeeProfileIdProvider);
    if (scope == null ||
        session == null ||
        session.deviceId != scope.deviceId) {
      return ProviderCardStartRequest.unavailable;
    }
    if (posture is! ProviderCardPosturePresent ||
        posture.mode != mode ||
        !posture.enabled ||
        (mode == ProviderCardMode.test && !lab)) {
      return ProviderCardStartRequest.notPermitted;
    }
    final live = mode == ProviderCardMode.live;
    final revision = expectedRevision;
    if (orderId.trim().isEmpty ||
        identity.key != PosOrderIdentity.server(orderId).key ||
        orderNumber.trim().isEmpty ||
        orderNumber.length > 64 ||
        !isProviderCardAmount(amountMinor) ||
        !kProviderCardCurrencies.contains(currencyCode) ||
        (live &&
            (!isProviderCardUuid(orderId) ||
                revision == null ||
                revision < 0 ||
                revision > kProviderCardMaxRevision))) {
      return ProviderCardStartRequest.invalid;
    }
    if (_starting.contains(identity.key)) return ProviderCardStartRequest.busy;
    _starting.add(identity.key);
    try {
      await ensureHydrated();
      final hydrated = _stateOf(gen);
      if (hydrated == null) return ProviderCardStartRequest.unavailable;
      if (hydrated.quarantined) return ProviderCardStartRequest.quarantined;
      // The identity is minted inside the journal's admission and only once a
      // new record is admitted: an adopted or refused start mints none
      // (correction packet §5).
      final ids = _ids;
      final clock = _clock;
      final ProviderCardCreate created;
      try {
        created = await _store.createIfAbsent(
          scope,
          identityKey: identity.key,
          mode: mode,
          mint: () {
            final attemptId = ids.newId();
            if (!isProviderCardUuidV4(attemptId)) throw const _InvalidMint();
            return ProviderCardAttempt.create(
              attemptId: attemptId,
              organizationId: scope.organizationId,
              restaurantId: scope.restaurantId,
              branchId: scope.branchId,
              deviceId: scope.deviceId,
              orderId: orderId,
              orderNumber: orderNumber,
              mode: mode,
              amountMinor: amountMinor,
              currencyCode: currencyCode,
              expectedRevision: live ? revision : null,
              employeeProfileId: (employee == null || employee.trim().isEmpty)
                  ? null
                  : employee,
              now: clock(),
            );
          },
        );
      } catch (e) {
        return e is _InvalidMint
            ? ProviderCardStartRequest.invalid
            : ProviderCardStartRequest.saveBlocked;
      }
      switch (created) {
        case ProviderCardCreateQuarantined():
          final s = _stateOf(gen);
          if (s != null) state = s.copyWith(quarantined: true);
          return ProviderCardStartRequest.quarantined;
        case ProviderCardCreateFull():
          // Not a quarantine: every stored attempt stays usable.
          return ProviderCardStartRequest.journalFull;
        case ProviderCardAdopted(:final attempt):
          _put(gen, attempt);
          return ProviderCardStartRequest.adopted;
        case ProviderCardCreated(:final attempt):
          _put(gen, attempt);
          await _sendStart(gen, scope, attempt.attemptId);
          return ProviderCardStartRequest.started;
      }
    } finally {
      _starting.remove(identity.key);
    }
  }

  /// Sends the SAME `start` again — only for an attempt no `start` of which can
  /// have had a ledger effect (never sent, or answered 401), after a fresh
  /// session and device check. Explicit only. To the server it is a first
  /// start, so the posture must still permit one (packet §9); one not known
  /// yet is read once more first, and a card view gone by then sends nothing.
  /// A 401 can clear under the same PIN session (an access token the SDK
  /// refreshes), so the same session is not refused here; the server decides.
  Future<void> retryStart(String attemptId) async {
    final gen = _generation;
    final scope = _scope;
    final a = _latest(attemptId);
    if (scope == null || a == null || !_idle(attemptId)) return;
    if (a.phase != ProviderCardPhase.notSent &&
        a.phase != ProviderCardPhase.authRequired) {
      return;
    }
    var posture = ref.read(providerCardPostureProvider).posture;
    var reread = false;
    if (posture is ProviderCardPostureUnknown) {
      // Not known yet (a probe under way, or one that failed): read it once
      // more before deciding, as a hand-recorded Card send does. The attempt
      // shows as being prepared meanwhile.
      _setBusy(gen, attemptId, ProviderCardBusy.starting);
      try {
        posture = await readPosture();
      } finally {
        _setBusy(gen, attemptId, null);
      }
      if (!_current(gen)) return;
      reread = true;
    }
    final bool lab;
    try {
      lab = ref.read(providerCardLabEnabledProvider);
    } catch (_) {
      // The world changed while the posture was read: nothing is sent.
      return;
    }
    if (posture is ProviderCardPostureUnknown) {
      _note(gen, attemptId, ProviderCardNote.postureUnknown);
      return;
    }
    if (posture is! ProviderCardPosturePresent ||
        posture.mode != a.mode ||
        !posture.enabled ||
        (a.mode == ProviderCardMode.test && !lab)) {
      _note(gen, attemptId, ProviderCardNote.terminalUnavailable);
      return;
    }
    // A card view that went away while the posture was read sends nothing:
    // nobody watches the terminal the request would prompt.
    if (reread && (_polls[attemptId]?.leases ?? 0) <= 0) {
      _note(gen, attemptId, ProviderCardNote.notSent);
      return;
    }
    if (!_idle(attemptId)) return;
    await _sendStart(gen, scope, attemptId);
  }

  Future<void> _sendStart(int gen, PosSyncScope scope, String attemptId) async {
    _setBusy(gen, attemptId, ProviderCardBusy.starting);
    try {
      final sentAt = _now();
      var refused = false;
      // Persist-before-send: the record says "may have been sent" first —
      // and NEVER for an attempt a `start` of which may have executed. The
      // send is stamped later than every send of the attempt before it, so
      // its stamp names this send alone (packet §7.3).
      final before = await _persistBeforeSend(gen, scope, attemptId, (c) {
        if (!c.startHasNoPossibleEffect ||
            c.server != null ||
            c.closed != null) {
          refused = true;
          return c;
        }
        final stamp = _nextSendStamp(c.startLastSentAt, sentAt);
        return c.copyWith(
          startInDoubt: true,
          startLastSentAt: stamp,
          // A new send voids every earlier not-found answer.
          serverNotFoundAt: null,
          updatedAt: stamp,
        );
      });
      if (before == null || refused) return;
      final sentStamp = before.startLastSentAt;
      _note(gen, attemptId, null);
      final result = await _wire(attemptId, () => _edge(gen).start(before));
      // The exchange has ended: nothing of it can be handed off any more, so
      // the settle window of an answer that proves nothing runs from here on
      // the monotonic clock, bound to this send (packet §7.3). An envelope,
      // or an outcome after which no start can have had an effect, leaves
      // nothing to wait on.
      if (result is ProviderCardEdgeEnvelope ||
          result is ProviderCardEdgeNotSent ||
          result is ProviderCardEdgeUnauthenticated ||
          result is ProviderCardEdgeNotApplied) {
        _inDoubtSince.remove(attemptId);
      } else {
        _inDoubtSince[attemptId] = (sentAt: sentStamp, since: _monotonic());
      }
      final at = _now();
      final (after, _) = await _persistAfter(
        gen,
        scope,
        attemptId,
        (c) => _applyStart(c, result, at),
      );
      if (result is ProviderCardEdgeEnvelope && after != null) {
        await _maybeFirstLeg(gen, scope, after);
      }
    } finally {
      _setBusy(gen, attemptId, null);
    }
  }

  static ProviderCardAttempt _applyStart(
    ProviderCardAttempt a,
    ProviderCardEdgeResult r,
    String at,
  ) => switch (r) {
    ProviderCardEdgeEnvelope(:final facts) => a.copyWith(
      startInDoubt: false,
      startMayHaveExecuted: true,
      startOutcome: ProviderCardStartOutcome.answered,
      server: facts,
      serverNotFoundAt: null,
      updatedAt: at,
    ),
    ProviderCardEdgeRefusal(:final error, :final detail, :final attemptState) =>
      a.copyWith(
        startInDoubt: false,
        startMayHaveExecuted: true,
        startOutcome: ProviderCardStartOutcome.refused,
        startRefusal: ProviderCardStartRefusal(error, detail),
        // The same identity holds different frozen fields on the server.
        safetyStop: error == 'conflict' && attemptState != null
            ? ProviderCardSafetyStop.attemptConflict
            : a.safetyStop,
        updatedAt: at,
      ),
    ProviderCardEdgeContradiction(:final stop) => a.copyWith(
      startInDoubt: false,
      startMayHaveExecuted: true,
      startOutcome: ProviderCardStartOutcome.answered,
      safetyStop: stop,
      updatedAt: at,
    ),
    ProviderCardEdgeNotSent() => a.copyWith(
      startInDoubt: false,
      startOutcome: ProviderCardStartOutcome.notSent,
      serverNotFoundAt: null,
      updatedAt: at,
    ),
    ProviderCardEdgeUnauthenticated() => a.copyWith(
      startInDoubt: false,
      startOutcome: ProviderCardStartOutcome.authRequired,
      serverNotFoundAt: null,
      updatedAt: at,
    ),
    ProviderCardEdgeNotApplied() => a.copyWith(
      startInDoubt: false,
      startOutcome: ProviderCardStartOutcome.notApplied,
      serverNotFoundAt: null,
      updatedAt: at,
    ),
    ProviderCardEdgeUncertain() || ProviderCardEdgeUnreadable() => a.copyWith(
      startInDoubt: false,
      startMayHaveExecuted: true,
      startOutcome: ProviderCardStartOutcome.uncertain,
      updatedAt: at,
    ),
  };

  // ---- status ---------------------------------------------------------------

  /// Check status — explicit (`source: operator`). Joins a check already in
  /// flight for the attempt instead of sending a second one.
  Future<void> checkStatus(String attemptId) async {
    final s = state; // a rebuild still pending runs first
    final gen = _generation;
    if (!_current(gen)) return;
    if (s.autoPaused.contains(attemptId) && _idle(attemptId)) {
      // A manual check is the operator follow-up a `poll_limit` asks for;
      // while a request is under way nothing is checked, so nothing clears.
      _note(gen, attemptId, null);
    }
    await _status(gen, attemptId, operator: true);
  }

  /// One `status` exchange. True when a readable answer arrived (the poller's
  /// back-off signal). [allowFirstLeg]: an `approved_unrecorded` answer may
  /// trigger the automatic first send of the leg.
  Future<_StatusAnswer> _status(
    int gen,
    String attemptId, {
    required bool operator,
    bool allowFirstLeg = true,
  }) {
    final inFlight = _statusInFlight[attemptId];
    if (inFlight != null) return inFlight;
    final scope = _scope;
    final s = _stateOf(gen);
    final a = s?.byId(attemptId);
    if (scope == null ||
        s == null ||
        a == null ||
        a.closed != null ||
        a.startHasNoPossibleEffect ||
        s.busy.containsKey(attemptId) ||
        _onWire.containsKey(attemptId)) {
      return Future<_StatusAnswer>.value(_StatusAnswer.none);
    }
    final run = _statusRun(
      gen,
      scope,
      a,
      operator: operator,
      allowFirstLeg: allowFirstLeg,
    );
    _statusInFlight[attemptId] = run;
    return run.whenComplete(() {
      if (identical(_statusInFlight[attemptId], run)) {
        _statusInFlight.remove(attemptId);
      }
    });
  }

  Future<_StatusAnswer> _statusRun(
    int gen,
    PosSyncScope scope,
    ProviderCardAttempt a, {
    required bool operator,
    required bool allowFirstLeg,
  }) async {
    ProviderCardAttempt? approved;
    _StatusAnswer answer;
    _setBusy(gen, a.attemptId, ProviderCardBusy.checking);
    try {
      final sentAt = _now();
      final sentMono = _monotonic();
      // An explicit check delivers a refusal report still owed (packet §8.4),
      // under whatever session is signed in now: the one that received the
      // refusal may be the very one the server no longer accepts.
      final hint = operator ? a.refusalReportPending : null;
      final r = await _wire(
        a.attemptId,
        () => _edge(
          gen,
        ).status(a, operator: operator, recordingRefusedHint: hint),
      );
      final readable = await _applyStatus(
        gen,
        scope,
        a.attemptId,
        r,
        sentAt: sentAt,
        sentMono: sentMono,
        sentFor: a.startLastSentAt,
        reportedHint: hint,
      );
      answer = !readable
          ? _StatusAnswer.none
          : r is ProviderCardEdgeEnvelope
          ? _StatusAnswer.envelope
          : _StatusAnswer.readable;
      if (r is ProviderCardEdgeEnvelope) approved = _latest(a.attemptId);
    } finally {
      _setBusy(gen, a.attemptId, null);
    }
    final latest = approved;
    if (allowFirstLeg && latest != null) {
      await _maybeFirstLeg(gen, scope, latest);
    }
    return answer;
  }

  /// Applies one `status` (or `release`) answer. True when it was readable.
  /// [sentMono] is the request's send instant on the monotonic clock,
  /// [sentFor] the `start_last_sent_at` of the record it was sent for, and
  /// [reportedHint] the refusal report it carried, if any.
  Future<bool> _applyStatus(
    int gen,
    PosSyncScope scope,
    String attemptId,
    ProviderCardEdgeResult r, {
    required String sentAt,
    required Duration sentMono,
    required String? sentFor,
    String? reportedHint,
  }) async {
    final at = _now();
    switch (r) {
      case ProviderCardEdgeEnvelope(:final facts):
        _inDoubtSince.remove(attemptId);
        _note(
          gen,
          attemptId,
          facts.refusalCode == 'release_failed' &&
                  (facts.state == 'sent' || facts.state == 'unknown')
              ? ProviderCardNote.releaseNotConfirmed
              : null,
        );
        await _persistAfter(
          gen,
          scope,
          attemptId,
          (c) => c.copyWith(
            startInDoubt: false,
            startMayHaveExecuted: true,
            server: facts,
            serverNotFoundAt: null,
            // The report this request carried is delivered.
            refusalReportPending:
                reportedHint != null && c.refusalReportPending == reportedHint
                ? null
                : c.refusalReportPending,
            updatedAt: at,
          ),
        );
        return true;
      case ProviderCardEdgeRefusal(:final error):
        switch (error) {
          case 'attempt_not_found':
            final a = _latest(attemptId);
            if (a == null || a.server != null) {
              // An attempt this device saw cannot vanish: unreadable evidence.
              _note(gen, attemptId, ProviderCardNote.unavailable);
              return false;
            }
            _note(gen, attemptId, null);
            // Conclusive only once the window has passed on the monotonic
            // clock since this process began to wait on the very send this
            // request asked about (the end of a start exchange it ran, or the
            // first time it saw that send), so no wall-clock step changes it;
            // that decision is what is recorded. A wait on another send never
            // measures this one: this answer begins the wait and decides
            // nothing. An inconclusive answer is not recorded, and an answer
            // for an earlier send, or for a record no start of which can have
            // had an effect, is never recorded.
            final held = _inDoubtSince[attemptId];
            if (held == null || held.sentAt != sentFor) {
              _inDoubtSince[attemptId] = (sentAt: sentFor, since: sentMono);
              return true;
            }
            if (sentMono - held.since < kProviderCardStartSettleWindow) {
              return true;
            }
            await _persistAfter(
              gen,
              scope,
              attemptId,
              (c) =>
                  c.server != null ||
                      c.startHasNoPossibleEffect ||
                      c.startLastSentAt != sentFor
                  ? c
                  : c.copyWith(serverNotFoundAt: sentAt, updatedAt: at),
            );
            return true;
          case 'poll_limit':
            _note(gen, attemptId, ProviderCardNote.pollLimit);
            _pauseAuto(gen, attemptId);
            return true;
          case 'permission_denied':
            // This session may not act on card attempts: no proof of
            // anything, and automatic checks back off.
            _note(gen, attemptId, ProviderCardNote.roleCannot);
            return false;
          default:
            _note(gen, attemptId, ProviderCardNote.unavailable);
            return false;
        }
      case ProviderCardEdgeContradiction(:final stop):
        await _persistAfter(
          gen,
          scope,
          attemptId,
          (c) => c.copyWith(
            startInDoubt: false,
            startMayHaveExecuted: true,
            safetyStop: stop,
            updatedAt: at,
          ),
        );
        return true;
      case ProviderCardEdgeNotSent():
        _note(gen, attemptId, ProviderCardNote.notSent);
        return false;
      case ProviderCardEdgeUnauthenticated():
        _note(gen, attemptId, ProviderCardNote.signInAgain);
        return false;
      case ProviderCardEdgeNotApplied():
        _note(gen, attemptId, ProviderCardNote.refusedBeforeProcessing);
        return false;
      case ProviderCardEdgeUncertain() || ProviderCardEdgeUnreadable():
        _note(gen, attemptId, ProviderCardNote.unavailable);
        return false;
    }
  }

  // ---- release --------------------------------------------------------------

  /// Cancel on the terminal — advisory, one request per explicit tap. A
  /// release never proves that no charge exists and never marks the order
  /// unpaid; the same attempt and Check status remain.
  Future<void> release(String attemptId) async {
    final gen = _generation;
    final scope = _scope;
    final a = _latest(attemptId);
    final facts = a?.server;
    if (scope == null ||
        a == null ||
        facts == null ||
        facts.resolution != null ||
        (facts.state != 'sent' && facts.state != 'unknown') ||
        !_idle(attemptId)) {
      return;
    }
    _setBusy(gen, attemptId, ProviderCardBusy.releasing);
    try {
      final sentAt = _now();
      final sentMono = _monotonic();
      final r = await _wire(attemptId, () => _edge(gen).release(a));
      await _applyStatus(
        gen,
        scope,
        attemptId,
        r,
        sentAt: sentAt,
        sentMono: sentMono,
        sentFor: a.startLastSentAt,
      );
      if (r is ProviderCardEdgeUncertain || r is ProviderCardEdgeUnreadable) {
        _note(gen, attemptId, ProviderCardNote.releaseNotConfirmed);
      }
    } finally {
      _setBusy(gen, attemptId, null);
    }
  }

  // ---- the recording leg ----------------------------------------------------

  /// The automatic FIRST send: right after an envelope said
  /// `approved_unrecorded` (that answer is the fresh context proof) and only
  /// when the leg was never built or sent. Called only from inside the `start`
  /// or `status` exchange that received the envelope — that exchange still
  /// holds the attempt's one request slot, so nothing else can interleave.
  Future<void> _maybeFirstLeg(
    int gen,
    PosSyncScope scope,
    ProviderCardAttempt seen,
  ) async {
    final a = _latest(seen.attemptId) ?? seen;
    final facts = a.server;
    if (!_current(gen) ||
        !a.isLive ||
        facts == null ||
        facts.classification != 'approved_unrecorded' ||
        facts.recorded ||
        a.safetyStop != null ||
        a.closed != null ||
        a.recording != null ||
        a.recordingOutcome != null) {
      return;
    }
    await _sendLeg(gen, scope, a.attemptId, resume: null, firstOnly: true);
  }

  /// Send the recording again — explicit, an active cashier or higher on the
  /// same device; a fresh `status` proves the context first and must still say
  /// `approved`, not recorded. Never calls the provider.
  Future<void> resendRecording(String attemptId) async {
    final gen = _generation;
    final scope = _scope;
    final a = _latest(attemptId);
    if (scope == null || a == null || !a.isLive || !_idle(attemptId)) return;
    final outcome = a.recordingOutcome;
    final allowed =
        a.phase == ProviderCardPhase.approvedRecording ||
        (a.phase == ProviderCardPhase.recordingUnconfirmed &&
            (outcome == null || outcome.resendable));
    if (!allowed) return;
    final proven = await _freshProof(gen, scope, attemptId);
    if (proven == null) return;
    // The proof itself never sends the leg; but if anything else moved the
    // leg meanwhile, this explicit action does not send it twice.
    if (proven.recordingOutcome != a.recordingOutcome ||
        proven.recordingMayHaveExecuted != a.recordingMayHaveExecuted ||
        proven.recording != a.recording) {
      return;
    }
    await _sendLeg(gen, scope, attemptId, resume: null);
  }

  /// A manager sends a row a Resume reopened (`resume_authority_required`):
  /// the same leg, without a new `recording_resume`.
  Future<void> managerSend(String attemptId) async {
    final gen = _generation;
    final scope = _scope;
    final a = _latest(attemptId);
    if (scope == null ||
        a == null ||
        a.phase != ProviderCardPhase.managerMustSend ||
        !_idle(attemptId)) {
      return;
    }
    if (!await _proveManager(gen, attemptId)) return;
    final proven = await _freshProof(gen, scope, attemptId);
    if (proven == null ||
        proven.recordingOutcome !=
            ProviderCardRecordingOutcome.resumeAuthorityRequired) {
      return;
    }
    await _sendLeg(gen, scope, attemptId, resume: null);
  }

  /// The D-054 Resume recording — manager-or-higher, explicit (packet §8.4).
  Future<void> resumeRecording(String attemptId) async {
    final gen = _generation;
    final scope = _scope;
    final a = _latest(attemptId);
    if (scope == null ||
        a == null ||
        !a.isLive ||
        a.recording == null ||
        (a.phase != ProviderCardPhase.recordingRefused &&
            a.phase != ProviderCardPhase.resumeRefused) ||
        !_idle(attemptId)) {
      return;
    }
    // 1. A refusal report still owed is performed first.
    if (a.refusalReportPending != null) {
      await _reportRefusal(gen, attemptId);
      final after = _latest(attemptId);
      if (after == null || after.refusalReportPending != null) return;
    }
    // 2. A fresh manager proof (an active PIN session and membership).
    if (!await _proveManager(gen, attemptId)) return;
    // 3. A fresh device proof that still allows the Resume, with its count.
    final proven = await _freshProof(gen, scope, attemptId);
    if (proven == null) return;
    final facts = proven.server!;
    final count = facts.resumeCount;
    if (facts.recoverable != true ||
        count == null ||
        count >= kProviderCardMaxResumes ||
        (proven.phase != ProviderCardPhase.recordingRefused &&
            proven.phase != ProviderCardPhase.resumeRefused)) {
      _note(gen, attemptId, ProviderCardNote.notRecoverable);
      return;
    }
    await _sendLeg(gen, scope, attemptId, resume: count);
  }

  Future<bool> _proveManager(int gen, String attemptId) async {
    _setBusy(gen, attemptId, ProviderCardBusy.resuming);
    try {
      final proof = await proveProviderCardManager(
        transport: _transport,
        session: _session,
      );
      switch (proof) {
        case ProviderCardManagerProof.proven:
          return _current(gen);
        case ProviderCardManagerProof.notManager:
          _note(gen, attemptId, ProviderCardNote.managerRequired);
          return false;
        case ProviderCardManagerProof.unavailable:
          _note(gen, attemptId, ProviderCardNote.managerProofUnavailable);
          return false;
      }
    } finally {
      _setBusy(gen, attemptId, null);
    }
  }

  /// A fresh `status` (`operator`) that must answer an envelope still saying
  /// `approved`, not recorded: the context proof the leg waits for. It never
  /// sends the leg itself. Returns the updated attempt, or null (nothing may
  /// be sent).
  Future<ProviderCardAttempt?> _freshProof(
    int gen,
    PosSyncScope scope,
    String attemptId,
  ) async {
    // Only an envelope of THIS exchange proves the context; a readable refusal
    // (a session that may not act, a poll limit) proves nothing.
    final answer = await _status(
      gen,
      attemptId,
      operator: true,
      allowFirstLeg: false,
    );
    if (answer != _StatusAnswer.envelope || !_current(gen)) return null;
    final a = _latest(attemptId);
    final facts = a?.server;
    if (a == null ||
        facts == null ||
        facts.state != 'approved' ||
        facts.classification != 'approved_unrecorded' ||
        facts.recorded ||
        a.payment != null ||
        a.safetyStop != null) {
      return null;
    }
    return a;
  }

  Future<void> _sendLeg(
    int gen,
    PosSyncScope scope,
    String attemptId, {
    required int? resume,
    bool firstOnly = false,
  }) async {
    // The leg goes out under the session of the world that proved it, or not
    // at all: its sender is taken before anything can rebuild that world.
    final sender = _sender();
    if (!_current(gen)) return;
    ProviderCardRecordingResult? result;
    ProviderCardAttempt? after;
    _setBusy(
      gen,
      attemptId,
      resume == null ? ProviderCardBusy.recording : ProviderCardBusy.resuming,
    );
    try {
      final builtAt = _now();
      var refused = false;
      // Persist-before-send: the leg (built ONCE — its target id is minted
      // only then — and reused byte for byte afterwards) and the doubt are on
      // disk first.
      final before = await _persistBeforeSend(gen, scope, attemptId, (c) {
        // Re-proven on the FRESHEST stored record, not on memory: approved and
        // not recorded, no payment, nothing closed or stopped, and, for the
        // automatic first send, never built or sent before.
        final f = c.server;
        if (!c.isLive ||
            c.safetyStop != null ||
            c.closed != null ||
            f == null ||
            f.classification != 'approved_unrecorded' ||
            f.recorded ||
            c.payment != null ||
            (firstOnly &&
                (c.recording != null || c.recordingOutcome != null))) {
          refused = true;
          return c;
        }
        var leg = c.recording;
        if (leg == null) {
          final targetId = _ids.newId();
          if (isProviderCardUuidV4(targetId)) {
            leg = ProviderCardRecordingOperation(
              localOperationId: c.attemptId,
              targetId: targetId,
              clientCreatedAt: builtAt,
              orderId: c.orderId,
              amountTenderedMinor: c.amountMinor,
            );
          }
        }
        if (leg == null) {
          refused = true;
          return c;
        }
        return c.copyWith(
          recording: leg,
          recordingInDoubt: true,
          updatedAt: builtAt,
        );
      });
      if (before == null || refused) return;
      _note(gen, attemptId, null);
      // The world may have changed while the leg was written: it then goes out
      // under no other session (it reads "may have been sent" and waits for an
      // explicit resend after a fresh proof).
      if (!_current(gen)) return;
      final r = await _wire(
        attemptId,
        () => sender.send(before, recordingResume: resume),
      );
      result = r;
      final at = _now();
      var reserved = false;
      final (next, saved) = await _persistAfter(gen, scope, attemptId, (c) {
        final applied = _applyLeg(c, r, at);
        if (r is ProviderCardRecordingApplied && c.receiptReservedAt == null) {
          reserved = true;
        }
        return applied;
      });
      after = next;
      final s = reserved && saved ? _stateOf(gen) : null;
      if (s != null) {
        // The ONE automatic receipt: reserved durably by this device's own
        // applied reply, armed for this process and the world that received
        // it only.
        state = s.copyWith(receiptArmed: {...s.receiptArmed, attemptId});
      }
    } finally {
      _setBusy(gen, attemptId, null);
    }
    if (after?.refusalReportPending != null) {
      await _reportRefusal(gen, attemptId);
    }
    if (result is ProviderCardRecordingResumeDenied) {
      // Nothing was consumed; re-read the count and recoverability.
      await _status(gen, attemptId, operator: true, allowFirstLeg: false);
    }
  }

  static ProviderCardAttempt _applyLeg(
    ProviderCardAttempt a,
    ProviderCardRecordingResult r,
    String at,
  ) {
    // A recorded attempt stays recorded: a late answer of an earlier send
    // (another world's, or one overtaken by a resend) never rewrites it.
    if (a.payment != null ||
        a.recordingOutcome == ProviderCardRecordingOutcome.applied) {
      return a;
    }
    ProviderCardAttempt outcome(
      ProviderCardRecordingOutcome o, {
      bool mayHave = true,
    }) => a.copyWith(
      recordingInDoubt: false,
      recordingMayHaveExecuted: a.recordingMayHaveExecuted || mayHave,
      recordingOutcome: o,
      refusalReportPending: null,
      resumeDenied: null,
      updatedAt: at,
    );
    return switch (r) {
      ProviderCardRecordingApplied(:final payment) => a.copyWith(
        recordingInDoubt: false,
        recordingMayHaveExecuted: true,
        recordingOutcome: ProviderCardRecordingOutcome.applied,
        refusalReportPending: null,
        resumeDenied: null,
        payment: payment,
        receiptReservedAt: a.receiptReservedAt ?? at,
        updatedAt: at,
      ),
      ProviderCardRecordingRefused(:final hint) => a.copyWith(
        recordingInDoubt: false,
        recordingMayHaveExecuted: true,
        recordingOutcome: ProviderCardRecordingOutcome.refused,
        recordingRefusal: hint,
        refusalReportPending: hint,
        resumeDenied: null,
        updatedAt: at,
      ),
      ProviderCardRecordingCollision() => a.copyWith(
        recordingInDoubt: false,
        recordingMayHaveExecuted: true,
        recordingOutcome: ProviderCardRecordingOutcome.collision,
        recordingRefusal: 'conflict',
        refusalReportPending: 'conflict',
        resumeDenied: null,
        updatedAt: at,
      ),
      ProviderCardRecordingPending() => outcome(
        ProviderCardRecordingOutcome.pending,
      ),
      ProviderCardRecordingResumeAuthorityRequired() => outcome(
        ProviderCardRecordingOutcome.resumeAuthorityRequired,
      ),
      ProviderCardRecordingResumeDenied(:final token) => a.copyWith(
        recordingInDoubt: false,
        recordingOutcome: ProviderCardRecordingOutcome.resumeDenied,
        refusalReportPending: null,
        resumeDenied: token,
        updatedAt: at,
      ),
      ProviderCardRecordingUnconfirmed() => outcome(
        ProviderCardRecordingOutcome.unconfirmed,
      ),
      ProviderCardRecordingNotSent() => outcome(
        ProviderCardRecordingOutcome.notSent,
        mayHave: false,
      ),
      ProviderCardRecordingAuthRequired() => outcome(
        ProviderCardRecordingOutcome.authRequired,
        mayHave: false,
      ),
      ProviderCardRecordingNotApplied() => outcome(
        ProviderCardRecordingOutcome.notApplied,
        mayHave: false,
      ),
      ProviderCardRecordingSafetyStop(:final stop) => a.copyWith(
        recordingInDoubt: false,
        recordingMayHaveExecuted: true,
        safetyStop: stop,
        updatedAt: at,
      ),
    };
  }

  /// Reports a refused leg: an explicit `status` (`operator`) carries the owed
  /// `recording_refused` hint ([_statusRun]). A readable envelope clears it;
  /// anything else keeps it owed for the next Check status or Resume, which
  /// deliver it under the session signed in then (packet §8.4). Called only
  /// from inside the attempt's request slot (the leg send that received the
  /// refusal, possibly within the status run that started it, or a Resume),
  /// so it runs the exchange directly instead of joining the slot it holds.
  Future<void> _reportRefusal(int gen, String attemptId) async {
    final scope = _scope;
    final a = _latest(attemptId);
    final s = _stateOf(gen);
    if (scope == null ||
        a == null ||
        a.refusalReportPending == null ||
        s == null ||
        s.busy.containsKey(attemptId)) {
      return;
    }
    await _statusRun(gen, scope, a, operator: true, allowFirstLeg: false);
  }

  // ---- local closure --------------------------------------------------------

  /// Sets the attempt aside to take payment another way — only where no charge
  /// can exist (packet §7.3). A never-sent request is recorded as abandoned.
  /// True only when the stored record is closed now.
  Future<bool> setAside(String attemptId) async {
    final gen = _generation;
    final scope = _scope;
    final a = _latest(attemptId);
    if (scope == null || a == null || !a.mayBeSetAside || !_idle(attemptId)) {
      return false;
    }
    final at = _now();
    final written = await _persistBeforeSend(gen, scope, attemptId, (c) {
      if (!c.mayBeSetAside) return c;
      final closure =
          c.phase == ProviderCardPhase.notSent && c.startHasNoPossibleEffect
          ? ProviderCardClosure.abandoned
          : ProviderCardClosure.setAside;
      return c.copyWith(closed: closure, updatedAt: at);
    });
    return written?.closed != null;
  }

  /// True exactly once per armed attempt: the sheet requests the one automatic
  /// receipt when this returns true.
  bool consumeReceipt(String attemptId) {
    if (!state.receiptArmed.contains(attemptId)) return false;
    state = state.copyWith(
      receiptArmed: {...state.receiptArmed}..remove(attemptId),
    );
    return true;
  }

  // ---- automatic checks -----------------------------------------------------

  /// A visible card view's lease on automatic checks for [attemptId].
  ProviderCardLease attachForeground(String attemptId) {
    final gen = _generation;
    final poll = _polls.putIfAbsent(attemptId, _Poll.new);
    poll.leases++;
    if (poll.leases == 1) {
      poll.budget = _policy.budget;
      poll.failures = 0;
      // A new lease is a new foreground session: the lease budget restarts;
      // a server `poll_limit` stays until a manual check clears it.
      if (state.autoPaused.contains(attemptId) &&
          state.notes[attemptId] != ProviderCardNote.pollLimit) {
        state = state.copyWith(
          autoPaused: {...state.autoPaused}..remove(attemptId),
        );
      }
      _schedule(gen, attemptId, _policy.firstDelay);
    }
    return ProviderCardLease._(() {
      final p = _polls[attemptId];
      if (p == null || !identical(p, poll)) return;
      p.leases--;
      if (p.leases <= 0) {
        p.timer?.cancel();
        _polls.remove(attemptId);
      }
    });
  }

  /// Whether automatic checks apply to [a] now.
  bool pollable(ProviderCardAttempt a) {
    if (state.autoPaused.contains(a.attemptId)) return false;
    return switch (a.phase) {
      ProviderCardPhase.uncertain ||
      ProviderCardPhase.waiting ||
      ProviderCardPhase.released ||
      ProviderCardPhase.approvedRecording ||
      ProviderCardPhase.testWaiting ||
      ProviderCardPhase.testReleased => true,
      _ => false,
    };
  }

  /// Re-arms a leased attempt that became pollable while no timer was set.
  void _kick(int gen, String attemptId) {
    final poll = _polls[attemptId];
    if (poll == null || poll.leases <= 0 || poll.timer?.isActive == true) {
      return;
    }
    final a = _latest(attemptId);
    if (a != null && pollable(a)) _schedule(gen, attemptId, _policy.interval);
  }

  void _schedule(int gen, String attemptId, Duration delay) {
    final poll = _polls[attemptId];
    if (poll == null || !_current(gen)) return;
    poll.timer?.cancel();
    poll.timer = Timer(delay, () => unawaited(_autoCheck(gen, attemptId)));
  }

  Future<void> _autoCheck(int gen, String attemptId) async {
    final poll = _polls[attemptId];
    if (poll == null || poll.leases <= 0 || !_current(gen)) return;
    poll.timer = null;
    final a = _latest(attemptId);
    if (a == null || !pollable(a)) return;
    if (poll.budget <= 0) {
      _note(gen, attemptId, ProviderCardNote.autoChecksPaused);
      _pauseAuto(gen, attemptId);
      return;
    }
    if (!_idle(attemptId)) {
      _schedule(gen, attemptId, _policy.interval);
      return;
    }
    poll.budget--;
    final answer = await _status(gen, attemptId, operator: false);
    if (!identical(_polls[attemptId], poll) || !_current(gen)) return;
    final readable = answer != _StatusAnswer.none;
    poll.failures = readable ? 0 : poll.failures + 1;
    final backoff = _policy.backoff;
    final next = readable || backoff.isEmpty
        ? _policy.interval
        : backoff[math.min(poll.failures - 1, backoff.length - 1)];
    final latest = _latest(attemptId);
    if (latest != null && pollable(latest)) _schedule(gen, attemptId, next);
  }
}

/// The canonical UTC instant spelling the journal uses.
String canonicalInstantOf(DateTime t) => t.toUtc().toIso8601String();

/// The stamp of a new `start` send of an attempt whose last send was stamped
/// [previous]: [now], or one millisecond after [previous] when [now] is not
/// later (a wall clock that stands still or stepped back). A millisecond is
/// the finest step every platform's clock keeps, so no two sends of an
/// attempt share a stamp.
String _nextSendStamp(String? previous, String now) {
  if (previous == null) return now;
  final last = DateTime.parse(previous);
  return DateTime.parse(now).isAfter(last)
      ? now
      : canonicalInstantOf(last.add(const Duration(milliseconds: 1)));
}

/// The id source gave no lowercase UUID v4: nothing is written or sent.
class _InvalidMint implements Exception {
  const _InvalidMint();
}

final providerCardControllerProvider =
    NotifierProvider<ProviderCardController, ProviderCardState>(
      ProviderCardController.new,
    );
