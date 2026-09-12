/// PAYMENT-ATTEMPT-RECOVERY-001 — the DURABLE store for payment attempts.
///
/// House `shared_preferences` JSON-envelope idiom (the durable outbox, the
/// drawer claim store, the addition journal), NOT a new storage subsystem:
/// one schema-versioned envelope `{version, attempts[]}` per operational
/// SCOPE (`org.restaurant.branch.device`), so a record written by one till
/// under one pairing is never read under another.
///
/// The durability contract is the MONEY-DURABLE-STORES-003B one, verbatim:
///
///   * a write is durable when `setString` reported success, or — when it
///     reported failure — when an INDEPENDENT backing read returns the exact
///     bytes we meant to store. "It did not throw" is not good enough, and
///     neither is re-reading through the adapter that just failed, because
///     that returns its own optimistic cache (PDR-001). Anything unproven
///     THROWS [PosPersistenceException] and the caller must send NOTHING;
///   * a record this build cannot READ is not a record it is entitled to
///     DESTROY: unreadable records are re-emitted byte-verbatim on every write
///     and reported as quarantined, never dropped;
///   * build + serialize BEFORE touching storage; the whole value is swapped
///     or the previous value stays intact.
///
/// CONCURRENCY — and its EXACT bound, stated rather than implied.
///
/// Every operation runs on a per-instance serial chain, so WITHIN ONE PROCESS
/// [createIfAbsent] is an atomic read-check-write: two controllers racing to
/// start a payment for one order observe exactly one created record, and the
/// loser adopts it.
///
/// ACROSS PROCESSES there is no such guarantee and this seam does not pretend
/// to one. `shared_preferences` exposes no compare-and-set, and each adapter
/// instance answers reads from its own in-memory cache — so two /pos browser
/// tabs on one origin (two instances over one localStorage) can each mint an
/// attempt for the same order without seeing each other. That is a bounded,
/// tested outcome, not an unknown one: the SERVER remains the authority, its
/// one-completed-payment-per-order index REFUSES the second attempt, and the
/// losing tab records that refusal — no second charge, and no automatic
/// receipt or drawer pulse for the attempt that lost. It does NOT conclude
/// that some other attempt settled the order, because no read available to a
/// POS can name the operation that paid it (PDR-006). The physical drawer is
/// additionally deduplicated by the existing per-`payment_id` durable claim,
/// which both tabs share.
///
/// A cross-process guarantee would need a storage seam with atomic
/// create-if-absent (the Drift spool has one, but it is native-only and not
/// composed into the POS). Adding one is out of this ticket's scope.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        defaultTargetPlatform,
        immutable,
        kIsWeb,
        visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_storage_health.dart';
import 'payment_attempt.dart';
import 'payment_replacement_block.dart';
import 'payment_safety.dart';
import 'sync_cursor_store.dart' show PosPersistenceException, PosSyncScope;

/// PAYMENT-ATTEMPT-RECOVERY-001 / K3-B04 — the envelope entry MINUS the
/// optional 27th key.
///
/// `PaymentAttempt.allowedKeys` holds exactly 26 names and `fromJson` throws on
/// anything else (`payment_attempt.dart:750-777`, `:784-788`). The optional
/// `replacement_block` therefore rides BESIDE the record rather than inside it,
/// and every call into the shipped strict decoder goes through this projection.
/// A record without a block is returned unchanged, so the 26-key wire contract
/// and every existing stored envelope are untouched.
Object? paymentAttemptProjection(Object? entry) {
  if (entry is! Map) return entry;
  if (!entry.containsKey(kReplacementBlockKey)) return entry;
  final out = <String, Object?>{};
  for (final e in entry.entries) {
    final k = e.key;
    // A non-String key is not ours to repair; hand the original to the strict
    // decoder so it quarantines the record exactly as it does today.
    if (k is! String) return entry;
    if (k == kReplacementBlockKey) continue;
    out[k] = e.value;
  }
  return out;
}

/// The raw `replacement_block` value of an entry, or null when the key is
/// absent. A PRESENT-NULL value is returned as null here and rejected by
/// [decodeReplacementBlockField] (rule `P1`), which is the only place the
/// distinction is load-bearing.
Object? paymentAttemptRawBlock(Object? entry) {
  if (entry is! Map) return null;
  if (!entry.containsKey(kReplacementBlockKey)) return null;
  return entry[kReplacementBlockKey];
}

/// The storage key for one scope's attempts, as the WRITER passes it to
/// `SharedPreferences`.
String paymentAttemptsStorageKey(String scopeKey) {
  final safe = scopeKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return 'restoflow.pos.payment_attempts.v1.$safe';
}

/// The PHYSICAL key the same record occupies in the backing store.
///
/// The legacy `SharedPreferences` API prefixes every key it writes with
/// `flutter.` in its shared Dart layer
/// (`shared_preferences-2.5.5/lib/src/shared_preferences_legacy.dart`, `_prefix`
/// and `_setValue`), so an independent reader that does NOT go through that
/// layer must ask for the prefixed name. Pinned by a regression, because the
/// prefix is a package-internal default rather than a published contract.
String paymentAttemptsPhysicalKey(String scopeKey) =>
    '$kLegacySharedPreferencesKeyPrefix${paymentAttemptsStorageKey(scopeKey)}';

/// The legacy adapter's key prefix. See [paymentAttemptsPhysicalKey].
const String kLegacySharedPreferencesKeyPrefix = 'flutter.';

/// The COMPLETE set of envelope keys this build writes and understands.
const Set<String> kPaymentAttemptEnvelopeKeys = <String>{'version', 'attempts'};

/// The physical storage namespace every POS payment key lives in.
///
/// S1-R3 / F001: the trust boundary is named after the storage the writer
/// ACTUALLY uses — the legacy `shared_preferences` key space — so that two
/// different Dart wrapper objects addressing the same bytes land on the same
/// boundary. It is deliberately NOT derived from any wrapper's identity.
const String kPaymentAttemptStorageNamespace = 'shared_preferences:legacy';

/// The canonical boundary name for [physicalKey].
String paymentAttemptGuardKey(String physicalKey) =>
    '$kPaymentAttemptStorageNamespace|$physicalKey';

/// S1-R3 / F001 — ONE trust-and-serialization boundary per physical payment
/// key, shared by every store, controller and provider in this Dart isolate.
///
/// The R2 build attached containment to the writing `SharedPreferences`
/// object. Codex proved that insufficient: a different wrapper over the same
/// bytes carried no mark, and because the mark was installed only AFTER the
/// platform result arrived, a replacement store could read the optimistic
/// cache while the first write was still unresolved. The untrustworthy thing
/// is the KEY while a write against it is unresolved — not one Dart object.
///
/// Two facts live here:
///
///   * [_serial] — every authority-bearing read-modify-write for this key runs
///     in one queue, so an overlapping store cannot observe a half-applied
///     write at all. This is what closes the provider-rebind and in-flight
///     races.
///   * [_unverifiedGeneration] — the highest write generation whose exact
///     intended bytes were never proven durable. While it is set, the writer's
///     cache is not evidence for this key and every read must come from an
///     independent backing reader; with no such reader the key is unreadable
///     and every authority-bearing path fails closed.
///
/// Generations are monotonic within the isolate, so only a write at least as
/// NEW as the failure can clear it. An older completion arriving late can
/// never launder a newer failure, and a success never overwrites newer
/// trusted content because the queue orders them.
///
/// LIFETIME, named accurately: a Dart isolate-wide static. It survives store,
/// controller, provider-container, session, scope and sheet recreation, and
/// distinct wrapper objects. It is NOT cross-isolate or cross-OS-process, and
/// a genuine process restart reloads the platform backing and starts clean.
/// Nothing clears it from a disposer, a new wrapper, or a health reset.
class _PaymentKeyGuard {
  Future<void> _serial = Future<void>.value();
  int _generation = 0;
  int _writesInFlight = 0;
  int? _unverifiedGeneration;
  String? _intendedEnvelope;

  /// True only when no write is unresolved and none is in flight.
  bool get isTrusted => _writesInFlight == 0 && _unverifiedGeneration == null;

  /// Whether a cache-mutating write against this key is happening right now.
  bool get hasWriteInFlight => _writesInFlight > 0;

  /// The monotonic write generation for this key. An independent read that
  /// began at one generation and finished at another describes a store state
  /// that no longer exists (S1-R4 / F001).
  int get generation => _generation;

  /// The exact bytes an unresolved write meant to store, retained so a later
  /// independent read can be compared against them rather than against
  /// whatever the backing happens to hold.
  String? get intendedEnvelope => _intendedEnvelope;

  Future<T> serialize<T>(Future<T> Function() op) {
    final run = _serial.then((_) => op());
    _serial = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Entered BEFORE any cache-mutating platform write. From this instant the
  /// key is not trusted, so nothing can adopt optimistic bytes even if the
  /// platform result never arrives.
  int beginWrite(String intended) {
    _writesInFlight++;
    _intendedEnvelope = intended;
    return ++_generation;
  }

  /// The write is proven durable (the adapter reported success, or an
  /// independent read returned the exact intended bytes).
  void completeVerified(int generation) {
    _writesInFlight--;
    final unverified = _unverifiedGeneration;
    if (unverified != null && unverified <= generation) {
      _unverifiedGeneration = null;
      _intendedEnvelope = null;
    }
  }

  /// The write is NOT proven durable. The key stays untrusted until a write at
  /// least this new succeeds.
  void completeUnverified(int generation, String intended) {
    _writesInFlight--;
    final unverified = _unverifiedGeneration;
    if (unverified == null || generation > unverified) {
      _unverifiedGeneration = generation;
      _intendedEnvelope = intended;
    }
  }
}

/// S1-R4 / F001 — the adapters whose OWN Dart cache holds bytes for a key that
/// never reached the backing store.
///
/// The shared key guard says whether ANY write for a key is unresolved. It is
/// necessarily cleared once a newer write is confirmed. But the wrapper that
/// made the unconfirmed write still holds its optimistic value in its own
/// `_preferenceCache`, and `shared_preferences` only refreshes that on an
/// explicit `reload()` this build never calls. Codex proved the consequence:
/// after a newer write cleared the shared mark, the OLD wrapper was trusted
/// again and served its phantom, bypassing the durable current record.
///
/// So the two facts are tracked separately and BOTH must be clean before a
/// wrapper's cache is evidence: the key must have no unresolved write, and
/// THIS wrapper must not be holding a phantom for it.
final Expando<Set<String>> _adapterPhantomKeys = Expando<Set<String>>();

Set<String> _phantomKeysOf(SharedPreferences prefs) =>
    _adapterPhantomKeys[prefs] ??= <String>{};

/// Whether [prefs] holds bytes for [physicalKey] that were never confirmed.
@visibleForTesting
bool paymentAttemptAdapterHoldsPhantom(
  SharedPreferences prefs,
  String physicalKey,
) => _phantomKeysOf(prefs).contains(physicalKey);

final Map<String, _PaymentKeyGuard> _paymentKeyGuards =
    <String, _PaymentKeyGuard>{};

_PaymentKeyGuard _guardFor(String physicalKey) => _paymentKeyGuards.putIfAbsent(
  paymentAttemptGuardKey(physicalKey),
  _PaymentKeyGuard.new,
);

/// Whether [physicalKey] may no longer be read through ANY writing adapter in
/// this isolate.
@visibleForTesting
bool paymentAttemptKeyIsUntrusted(String physicalKey) =>
    !_guardFor(physicalKey).isTrusted;

/// Retained for the S1/S1-R2 regressions and the external reviewer harnesses.
/// S1-R3: the boundary is the physical KEY, so [prefs] no longer selects it —
/// two different wrappers over the same bytes now answer identically, which is
/// exactly the corrected behaviour.
@visibleForTesting
bool paymentAttemptAdapterIsUntrusted(
  // ignore: avoid_unused_constructor_parameters
  SharedPreferences prefs,
  String physicalKey,
) => paymentAttemptKeyIsUntrusted(physicalKey);

/// TEST ONLY. Drops every key boundary so one test's contained key cannot leak
/// into the next in the same isolate. Never called by product code: the guard
/// is deliberately impossible to clear at runtime. Adapter phantoms live on the
/// adapter objects themselves and die with them.
@visibleForTesting
void resetPaymentAttemptKeyGuardsForTest() => _paymentKeyGuards.clear();

/// Moves the write generation for [physicalKey] forward by one.
///
/// Exists so a regression can model the one condition the generation guard is
/// for: another writer advancing the key WHILE an independent read is already
/// in flight, which makes that read describe a store state that no longer
/// exists. There is no production caller and no production need for one.
/// Whether a cache-mutating write for [physicalKey] is running RIGHT NOW.
///
/// Distinct from [paymentAttemptKeyIsUntrusted], which is also true for a key
/// left unverified by a COMPLETED write. A regression needs to tell the two
/// apart: the snapshot refuses to answer ABSENT only for the in-flight case,
/// and resolves the unverified case through the bounded retry.
@visibleForTesting
bool paymentAttemptKeyHasWriteInFlightForTest(String physicalKey) =>
    _guardFor(physicalKey).hasWriteInFlight;

@visibleForTesting
void bumpPaymentAttemptGenerationForTest(String physicalKey) {
  final guard = _guardFor(physicalKey);
  // `completeUnverified`, NOT `completeVerified`. An earlier version used the
  // verified form, which leaves `_writesInFlight == 0` AND
  // `_unverifiedGeneration == null` - i.e. `isTrusted == true` - so the seam
  // bumped the generation but produced a TRUSTED guard and no test using it
  // ever reached the untrusted path it claimed to exercise. The unverified form
  // advances the generation and leaves the key untrusted with no write in
  // flight, which is exactly the state the retry loop exists for.
  final intended = guard.intendedEnvelope ?? '';
  guard.completeUnverified(guard.beginWrite(intended), intended);
}

/// Thrown internally when an untrusted scope cannot be read independently.
class _UntrustedScopeUnreadable implements Exception {
  const _UntrustedScopeUnreadable();
}

/// Reads raw stored values WITHOUT the writing adapter's cache in the way.
///
/// PDR-001: the only thing that may contradict a reported write failure. An
/// implementation must reach the same physical backend and key as the writer
/// on the target it runs on; where it cannot, it must fail rather than guess.
abstract class PaymentAttemptBackingReader {
  /// The stored value for [physicalKey], or null when absent. Throws when the
  /// backing store cannot be read at all.
  Future<String?> readRaw(String physicalKey);
}

/// Resolved records beyond this many NEWEST ones are pruned on write. Only
/// RESOLVED records are ever pruned — a pending attempt is never evicted, and a
/// quarantined (unreadable) record is never touched.
const int kPaymentAttemptsResolvedRetention = 200;

/// One stored record this build could not interpret. It stays on disk
/// verbatim; the operator is told; and — because an unreadable record might
/// be an unresolved attempt for [orderId] — no NEW attempt is started for that
/// order (or for any order, when the order cannot even be read) until a build
/// that understands the record arrives.
class PaymentAttemptQuarantine {
  const PaymentAttemptQuarantine({required this.reason, this.orderId});

  /// `record` (one entry undecodable), `scope` (a decodable entry bound to a
  /// different scope), or `envelope` (the whole value unreadable / unknown
  /// version).
  final String reason;

  /// Best-effort order id read as a plain string from the raw entry, or null.
  final String? orderId;

  /// Whether this quarantine blocks a new attempt for [orderId].
  bool blocks(String orderId) =>
      this.orderId == null || this.orderId == orderId;
}

class PaymentAttemptLoad {
  const PaymentAttemptLoad({required this.attempts, required this.quarantined});

  static const PaymentAttemptLoad empty = PaymentAttemptLoad(
    attempts: <PaymentAttempt>[],
    quarantined: <PaymentAttemptQuarantine>[],
  );

  /// Every readable record for the scope, oldest first.
  final List<PaymentAttempt> attempts;
  final List<PaymentAttemptQuarantine> quarantined;

  bool blocksNewAttemptFor(String orderId) =>
      quarantined.any((q) => q.blocks(orderId));
}

/// The result of [PaymentAttemptStore.createIfAbsent].
class PaymentAttemptClaim {
  const PaymentAttemptClaim({required this.attempt, required this.created});

  /// The record now durably on disk for the order: the caller's when
  /// [created], otherwise the EXISTING pending attempt the caller must adopt.
  final PaymentAttempt attempt;
  final bool created;
}

abstract class PaymentAttemptStore {
  /// Loads every readable record for [scope]. Never throws and never writes:
  /// an unreadable envelope yields NO attempts plus an `envelope` quarantine.
  Future<PaymentAttemptLoad> load(PosSyncScope scope);

  /// Atomically (per instance) records [attempt] for [scope] UNLESS a PENDING
  /// attempt for the same order is already on disk, in which case that
  /// record is returned untouched and NOTHING is written.
  ///
  /// Returns only after the write is CONFIRMED. Throws
  /// [PosPersistenceException] when it is not — and only after re-reading the
  /// store to rule out a write that completed before reporting failure.
  Future<PaymentAttemptClaim> createIfAbsent(
    PosSyncScope scope,
    PaymentAttempt attempt,
  );

  /// S1-R4 / F001 — proposes a transition for the record with [attempt]'s
  /// `local_operation_id`, reconciled against what is ACTUALLY stored.
  ///
  /// The caller's value is a proposal, never a replacement: a stale snapshot
  /// can no longer downgrade a newer terminal record or erase a one-time
  /// effect reservation. The returned [PaymentAttemptMerge] says what really
  /// holds now — `applied`, `redundant`, `stale` or `conflict` — and carries
  /// the record that stands. Throws [PosPersistenceException] when there is no
  /// stored record to transition, or when the write does not stick.
  Future<PaymentAttemptMerge> update(
    PosSyncScope scope,
    PaymentAttempt attempt,
  );

  /// Persists the ACCEPTED resolution for [attempt] and reserves its one-time
  /// automatic effects — atomically per instance, and re-reading the LIVE
  /// record first: if any writer (another controller, another tab) already
  /// holds the reservation, the resolution is written WITHOUT re-reserving
  /// and `armed` is false. Throws [PosPersistenceException] when the write
  /// does not stick.
  /// [armCaller] is false for a PASSIVE resolution (a status query, boot or
  /// hydration). The one-time effect claim is still consumed, so nothing can
  /// arm it later, but the caller is never told it may fire an effect.
  Future<PaymentAttemptAcceptance> resolveAccepted(
    PosSyncScope scope,
    PaymentAttempt attempt,
    PaymentAttemptResolution resolution, {
    required String at,
    required bool armCaller,

    /// S1-R5 / F001 — the caller's own authority, re-evaluated INSIDE the
    /// serialized physical-key mutation, immediately before anything is
    /// written. A caller that has been replaced while its closure waited in
    /// the queue no longer speaks for this device.
    bool Function()? authority,
  });
}

/// The result of [PaymentAttemptStore.resolveAccepted].
class PaymentAttemptAcceptance {
  const PaymentAttemptAcceptance({required this.attempt, required this.armed});

  /// The record now on disk (phase accepted).
  final PaymentAttempt attempt;

  /// True exactly once per attempt: THIS write created the reservation.
  final bool armed;
}

/// The `shared_preferences`-backed store (see the library doc).
class SharedPrefsPaymentAttemptStore
    implements PaymentAttemptStore, PosDurableStoreHealth {
  SharedPrefsPaymentAttemptStore(
    SharedPreferences prefs, {
    PaymentAttemptBackingReader? backingReader,
  }) : _resolvePrefs = (() async => prefs),
       _backingReader = backingReader;

  /// Resolves the preferences lazily on first use (the production provider
  /// default; `main.dart` may also hand in the boot instance).
  SharedPrefsPaymentAttemptStore.lazy({
    Future<SharedPreferences> Function()? prefs,
    PaymentAttemptBackingReader? backingReader,
  }) : _resolvePrefs = prefs ?? SharedPreferences.getInstance,
       _backingReader = backingReader;

  final Future<SharedPreferences> Function() _resolvePrefs;

  /// PDR-001: the independent read used to adjudicate a reported write
  /// failure. Null means no independent evidence is obtainable, so a reported
  /// failure is final.
  final PaymentAttemptBackingReader? _backingReader;

  static const int schemaVersion = PaymentAttempt.schemaVersion;

  bool _degraded = false;
  final Map<String, int> _unreadable = <String, int>{};

  @override
  bool get isDegraded => _degraded;

  @override
  int unreadableRecordCount(String scopeKey) => _unreadable[scopeKey] ?? 0;

  /// A WRITE path. Two things happen here that a read does not need.
  ///
  /// First, if a cache-mutating write for this physical key is ALREADY in
  /// flight — from any store, wrapper or provider in this isolate — this call
  /// is refused immediately with a typed persistence failure. It does not wait
  /// on a platform call that may never return, and it certainly does not
  /// proceed to read the optimistic cache the way the R2 build did when a
  /// replacement store overlapped an unresolved write.
  ///
  /// Second, everything that does proceed runs in ONE queue per physical key,
  /// so two stores can never interleave a read-modify-write.
  Future<T> _serializedWrite<T>(PosSyncScope scope, Future<T> Function() op) {
    final guard = _guardFor(paymentAttemptsPhysicalKey(scope.key));
    if (guard.hasWriteInFlight) {
      _degraded = true;
      return Future<T>.error(
        const PosPersistenceException(
          'payment attempts: another write for this payment key is still in '
          'flight, so this one cannot be resolved safely',
        ),
      );
    }
    return guard.serialize(op);
  }

  static String? _rawOrderId(Object? entry) {
    if (entry is Map) {
      final id = entry['order_id'];
      if (id is String && id.trim().isNotEmpty) return id;
    }
    return null;
  }

  static String? _rawOpId(Object? entry) {
    if (entry is Map) {
      final id = entry['local_operation_id'];
      if (id is String && id.isNotEmpty) return id;
    }
    return null;
  }

  /// The decoded envelope, split into readable attempts, raw entries kept
  /// verbatim (readable AND unreadable, in stored order), and quarantines.
  /// `envelopeUnreadable` means the value itself cannot be interpreted —
  /// nothing may be written over it.
  ({
    List<PaymentAttempt> attempts,
    List<Object?> raws,
    List<PaymentAttemptQuarantine> quarantined,
    bool envelopeUnreadable,
  })
  _read(String? raw, PosSyncScope scope) {
    if (raw == null || raw.isEmpty) {
      return (
        attempts: <PaymentAttempt>[],
        raws: <Object?>[],
        quarantined: <PaymentAttemptQuarantine>[],
        envelopeUnreadable: false,
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      decoded = null;
    }
    // S1-F003: the version must be the EXACT supported integer. `1.5` used to
    // truncate to 1 and be accepted, and a string version escaped as an
    // uncaught TypeError instead of taking the quarantine route.
    final version = decoded is Map ? decoded['version'] : null;
    // S1-R3 / F003: the envelope carries EXACTLY these keys. An extra key is a
    // shape some other build wrote, and it may be authority-bearing — quietly
    // ignoring it would mean acting on a record set we only half understand.
    final unknownEnvelopeKey =
        decoded is Map &&
        decoded.keys.any((k) => !kPaymentAttemptEnvelopeKeys.contains(k));
    if (decoded is! Map ||
        unknownEnvelopeKey ||
        version is! int ||
        version != schemaVersion ||
        decoded['attempts'] is! List) {
      return (
        attempts: <PaymentAttempt>[],
        raws: <Object?>[],
        quarantined: const [PaymentAttemptQuarantine(reason: 'envelope')],
        envelopeUnreadable: true,
      );
    }
    final attempts = <PaymentAttempt>[];
    final raws = <Object?>[];
    final quarantined = <PaymentAttemptQuarantine>[];
    for (final e in decoded['attempts'] as List) {
      raws.add(e);
      PaymentAttempt? a;
      try {
        a = PaymentAttempt.fromJson(paymentAttemptProjection(e));
      } catch (_) {
        quarantined.add(
          PaymentAttemptQuarantine(reason: 'record', orderId: _rawOrderId(e)),
        );
        continue;
      }
      if (a.organizationId != scope.organizationId ||
          a.restaurantId != scope.restaurantId ||
          a.branchId != scope.branchId ||
          a.deviceId != scope.deviceId) {
        // A decodable record bound to ANOTHER scope under this key: kept, never
        // acted on, and it blocks its own order only.
        quarantined.add(
          PaymentAttemptQuarantine(reason: 'scope', orderId: a.orderId),
        );
        continue;
      }
      attempts.add(a);
    }
    return (
      attempts: attempts,
      raws: raws,
      quarantined: quarantined,
      envelopeUnreadable: false,
    );
  }

  @override
  Future<PaymentAttemptLoad> load(PosSyncScope scope) => _loadUnqueued(scope);

  /// Reads never join the write queue: the key guard already decides whether
  /// the writer's cache may be believed, so a platform write that never
  /// returns cannot block the cashier's view.
  Future<PaymentAttemptLoad> _loadUnqueued(PosSyncScope scope) => (() async {
    final SharedPreferences prefs;
    try {
      prefs = await _resolvePrefs();
    } catch (_) {
      return const PaymentAttemptLoad(
        attempts: <PaymentAttempt>[],
        quarantined: [PaymentAttemptQuarantine(reason: 'envelope')],
      );
    }
    final ({
      List<PaymentAttempt> attempts,
      List<Object?> raws,
      List<PaymentAttemptQuarantine> quarantined,
      bool envelopeUnreadable,
    })
    r;
    try {
      r = _read(await _rawEnvelope(prefs, scope), scope);
    } catch (_) {
      // S1-F001: an untrusted scope with no independent read is NOT an empty
      // store. Reporting it empty would let a caller mint a fresh attempt for
      // an order that may already have one on disk.
      _unreadable[scope.key] = 1;
      return const PaymentAttemptLoad(
        attempts: <PaymentAttempt>[],
        quarantined: [PaymentAttemptQuarantine(reason: 'untrusted')],
      );
    }
    _unreadable[scope.key] = r.quarantined.length;
    return PaymentAttemptLoad(attempts: r.attempts, quarantined: r.quarantined);
  })();

  /// The envelope bytes for [scope].
  ///
  /// S1-R3 / F001: while ANY write against this physical key is unresolved or
  /// in flight — whichever store, wrapper or provider issued it — the writer's
  /// cache is not evidence. The bytes then come from the INDEPENDENT reader,
  /// and with no reader the scope is unreadable so every caller fails closed.
  Future<String?> _rawEnvelope(
    SharedPreferences prefs,
    PosSyncScope scope,
  ) async {
    final physical = paymentAttemptsPhysicalKey(scope.key);
    final guard = _guardFor(physical);
    // S1-R4 / F001: BOTH facts must be clean. The key must have no unresolved
    // write, AND this particular adapter must not be holding a phantom for it
    // — a newer write by someone else clears the first but can never repair
    // the second.
    if (guard.isTrusted && !_phantomKeysOf(prefs).contains(physical)) {
      return prefs.getString(paymentAttemptsStorageKey(scope.key));
    }
    final reader = _backingReader;
    if (reader == null) throw const _UntrustedScopeUnreadable();
    // S1-R4 / F001: an independent read is only evidence about the generation
    // it observed. If the key moved on while this read was in flight, the
    // bytes it returns describe a store state that no longer exists, so the
    // read is retried against the current generation rather than believed.
    for (var attempt = 0; attempt < 4; attempt++) {
      final observed = guard.generation;
      final raw = await reader.readRaw(physical);
      if (guard.generation == observed) return raw;
    }
    throw const _UntrustedScopeUnreadable();
  }

  /// The envelope for a WRITE path. An untrusted scope with no independent
  /// read cannot be written safely either: the rebuild would be based on the
  /// adapter's optimistic guess.
  Future<
    ({
      List<PaymentAttempt> attempts,
      List<Object?> raws,
      List<PaymentAttemptQuarantine> quarantined,
      bool envelopeUnreadable,
    })
  >
  _readForWrite(SharedPreferences prefs, PosSyncScope scope) async {
    try {
      return _read(await _rawEnvelope(prefs, scope), scope);
    } catch (_) {
      // S1-R4 / F001: ANY failure to obtain trustworthy bytes — the untrusted
      // signal, or an independent reader that threw — is a fail-closed write
      // refusal, never an uncaught error escaping into the payment path.
      _degraded = true;
      throw const PosPersistenceException(
        'payment attempts: this scope was left unverified by an earlier failed '
        'write and cannot be read independently on this target',
      );
    }
  }

  /// Writes [raws] (verbatim) + the caller's readable set as one envelope, and
  /// returns whether the bytes are DURABLE.
  ///
  /// PDR-001. The installed adapter mutates its own cache BEFORE the platform
  /// write is awaited (`shared_preferences-2.5.5`
  /// `lib/src/shared_preferences_legacy.dart` `_setValue`), and its class doc
  /// states the cache is not guaranteed to match the device. So when the write
  /// reports failure, reading back through the SAME adapter returns the
  /// adapter's own optimistic guess, not evidence. This build therefore:
  ///
  ///   * treats a reported success as durable, exactly as before — that is the
  ///     adapter's contract and the unchanged happy path;
  ///   * on a reported failure, believes ONLY an independent backing read that
  ///     returns the exact bytes we meant to store;
  ///   * fails closed when no independent reader is available, because an
  ///     unverifiable write must never authorise a send or an effect.
  ///
  /// This removes the cache-only acknowledgement defect. It is NOT a
  /// certification of fsync, OS-process crash, disk-full, eviction or
  /// power-loss safety; that remains open for the storage design slice.
  Future<bool> _write(
    SharedPreferences prefs,
    PosSyncScope scope,
    List<Object?> entries,
  ) async {
    final encoded = jsonEncode(<String, Object?>{
      'version': schemaVersion,
      'attempts': entries,
    });
    // S1-R3 / F001: the boundary is entered BEFORE the cache-mutating call,
    // so no overlapping reader can adopt the optimistic bytes even if the
    // platform result never arrives.
    final guard = _guardFor(paymentAttemptsPhysicalKey(scope.key));
    final generation = guard.beginWrite(encoded);
    bool reported;
    try {
      reported = await prefs.setString(
        paymentAttemptsStorageKey(scope.key),
        encoded,
      );
    } catch (_) {
      reported = false;
    }
    if (reported) {
      // The adapter's own success report IS its durability contract, and this
      // write is at least as new as any earlier failure for this key, so it
      // supersedes it. An OLDER completion can never clear a newer failure.
      guard.completeVerified(generation);
      // S1-R4 / F001: a CONFIRMED write through this adapter also repairs this
      // adapter's own cache for this key — it now holds exactly the bytes that
      // landed. The phantom mark is about a write that did NOT land, so it is
      // cleared only by that adapter writing successfully, never by someone
      // else's write and never by a disposer or a health flag.
      _phantomKeysOf(prefs).remove(paymentAttemptsPhysicalKey(scope.key));
      return true;
    }
    // The comparison is against the EXACT bytes this write meant to store,
    // retained on the boundary, not against whatever the backing happens to
    // hold. Stale, partial, wrong or absent content can never confirm it.
    if (await _verifyDurable(scope, guard.intendedEnvelope ?? encoded)) {
      guard.completeVerified(generation);
      return true;
    }
    // The adapter now holds bytes that never reached the backing store.
    // Nothing in this isolate may read that key through a writer again until a
    // strictly newer write is proven durable.
    _degraded = true;
    guard.completeUnverified(generation, encoded);
    // This adapter's own cache now holds bytes that never landed. Nothing may
    // read THIS object's cache for THIS key again, whatever any other writer
    // later does to the shared boundary.
    _phantomKeysOf(prefs).add(paymentAttemptsPhysicalKey(scope.key));
    return false;
  }

  /// Whether an INDEPENDENT read of the backing store returns exactly
  /// [expected]. Any doubt — no reader, a read failure, absent, stale or
  /// different bytes — answers false.
  Future<bool> _verifyDurable(PosSyncScope scope, String expected) async {
    final reader = _backingReader;
    if (reader == null) return false;
    final String? raw;
    try {
      raw = await reader.readRaw(paymentAttemptsPhysicalKey(scope.key));
    } catch (_) {
      return false;
    }
    return raw == expected;
  }

  // =========================================================================
  // K3-B01 — the AUTHORITATIVE envelope snapshot
  //
  // ONE `PosSyncScope` in; every storage string, the guard and the observed
  // generation derived from it. There is no key/guard triple a caller could
  // make disagree, and none is possible: `_guardFor` and `_PaymentKeyGuard` are
  // library-private, and this reads `_backingReader`, an INSTANCE field — so
  // this must be a private instance method of this class, not a top-level
  // function.
  // =========================================================================

  /// TOTAL. Mirrors `_rawEnvelope` but returns a typed result for every failure
  /// instead of throwing, and carries the exact generation it observed.
  Future<SnapshotResult> _readEnvelopeSnapshotLocked(
    SharedPreferences prefs,
    PaymentEnvelopeIdentity identity,
  ) async {
    final guard = _guardFor(identity.physicalBackingKey);
    final holdsPhantom = _phantomKeysOf(
      prefs,
    ).contains(identity.physicalBackingKey);

    // ---- TRUSTED PATH -----------------------------------------------------
    // `isTrusted` means no write is unresolved AND none is in flight. `get` and
    // `containsKey` are synchronous cache reads, so no await separates the
    // generation sample from the value.
    if (guard.isTrusted && !holdsPhantom) {
      final gen = guard.generation;
      // `containsKey` is what separates a PROVEN absence from a stored empty
      // string; the shipped `_read` collapses the two.
      final present = prefs.containsKey(identity.logicalPrefsKey);
      // The installed adapter's `getString` is an unguarded cast
      // (`shared_preferences_legacy.dart:129`), so a cached value of any other
      // type throws HERE. That throw IS the wrong-cached-type signal, and it is
      // caught precisely — never as a broad `catch (_)` that would also swallow
      // a real fault.
      final String? cached;
      try {
        cached = prefs.getString(identity.logicalPrefsKey);
      } on TypeError {
        return SnapshotWrongCachedType(
          context: EnvelopeSnapshotContext(
            identity,
            gen,
            SnapshotTrust.trusted,
          ),
          observedTypeName: 'non-String',
        );
      }
      return _classifyEnvelope(
        identity,
        gen,
        SnapshotTrust.trusted,
        present,
        cached,
      );
    }

    // ---- UNTRUSTED PATH ---------------------------------------------------
    final reader = _backingReader;
    if (reader == null) {
      return SnapshotUntrusted(
        context: EnvelopeSnapshotContext(
          identity,
          guard.generation,
          SnapshotTrust.untrusted,
        ),
        reason: UntrustedReason.noIndependentReader,
      );
    }

    // A read taken while a cache-mutating write is STILL RUNNING cannot prove
    // ABSENCE: the guard holds bytes that may yet land. The shipped writer
    // refuses the whole operation in exactly this state (`_serializedWrite`),
    // so the reader must not answer "virgin absent" for it either — that would
    // authorise a fresh mint beside bytes that are still landing.
    //
    // The condition is `hasWriteInFlight` ALONE. An earlier draft of this seam
    // also tested `guard.intendedEnvelope != null`, which was a REGRESSION:
    // `completeVerified` clears `_intendedEnvelope` only when a failure was
    // already outstanding, so after any clean write the field stays set for the
    // life of the isolate — and the four-observation retry below became
    // unreachable. An unverified generation needs no extra test here: it
    // already makes the guard untrusted, and the retry against the independent
    // reader is exactly how the shipped `_rawEnvelope` handles it.
    if (guard.hasWriteInFlight) {
      return SnapshotUntrusted(
        context: EnvelopeSnapshotContext(
          identity,
          guard.generation,
          SnapshotTrust.untrusted,
        ),
        reason: UntrustedReason.writeUnresolved,
      );
    }

    // The same bounded four-observation retry the shipped reader uses: an
    // independent read is evidence only about the generation it observed.
    for (var attempt = 0; attempt < 4; attempt++) {
      final observed = guard.generation;
      final String? raw;
      try {
        raw = await reader.readRaw(identity.physicalBackingKey);
      } catch (_) {
        return SnapshotReadFailed(
          context: EnvelopeSnapshotContext(
            identity,
            observed,
            SnapshotTrust.untrusted,
          ),
        );
      }
      if (guard.generation == observed) {
        return _classifyEnvelope(
          identity,
          observed,
          SnapshotTrust.untrusted,
          raw != null,
          raw,
        );
      }
    }
    return SnapshotUntrusted(
      context: EnvelopeSnapshotContext(
        identity,
        guard.generation,
        SnapshotTrust.untrusted,
      ),
      reason: UntrustedReason.generationRaced,
    );
  }

  /// TOTAL. Keeps ABSENT and PRESENT-EMPTY apart (the shipped `_read` collapses
  /// them) and freezes each entry's exact source lexeme for the §8 preservation
  /// proof.
  static SnapshotResult _classifyEnvelope(
    PaymentEnvelopeIdentity identity,
    int generation,
    SnapshotTrust trust,
    bool present,
    String? raw,
  ) {
    final ctx = EnvelopeSnapshotContext(identity, generation, trust);
    if (!present || raw == null) return SnapshotAbsent(context: ctx);
    if (raw.isEmpty) return SnapshotPresentEmpty(context: ctx);

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return SnapshotNotCanonical(
        context: ctx,
        violation: 'envelope: not JSON',
      );
    }
    if (decoded is! Map) {
      return SnapshotNotCanonical(
        context: ctx,
        violation: 'envelope: not an object',
      );
    }
    for (final k in decoded.keys) {
      if (k is! String || !kPaymentAttemptEnvelopeKeys.contains(k)) {
        return SnapshotNotCanonical(
          context: ctx,
          violation: 'envelope: unknown key $k',
        );
      }
    }
    final version = decoded['version'];
    if (version is! int || version != PaymentAttempt.schemaVersion) {
      return SnapshotNotCanonical(context: ctx, violation: 'envelope: version');
    }
    final attemptsRaw = decoded['attempts'];
    if (attemptsRaw is! List) {
      return SnapshotNotCanonical(
        context: ctx,
        violation: 'envelope: attempts',
      );
    }

    // §8 — CANONICALITY. The production encoder must reproduce these exact
    // bytes from the decoded value. If it cannot, the envelope was written by
    // something other than this build's writer and may not be mutated at all.
    final reEncoded = jsonEncode(<String, Object?>{
      'version': version,
      'attempts': attemptsRaw,
    });
    if (reEncoded != raw) {
      return SnapshotNotCanonical(
        context: ctx,
        violation: 'envelope: not canonical under the production encoder',
      );
    }

    final entries = <FrozenEntry>[];
    for (var i = 0; i < attemptsRaw.length; i++) {
      final Object? e = attemptsRaw[i];
      // The frozen source lexeme: what this exact entry must still encode to
      // after any mutation that does not touch it.
      final lexeme = jsonEncode(e);
      PaymentAttempt? a;
      String? violation;
      try {
        a = PaymentAttempt.fromJson(paymentAttemptProjection(e));
      } on FormatException catch (f) {
        violation = f.message;
      } catch (_) {
        violation = 'record: undecodable';
      }
      if (a == null) {
        entries.add(
          FrozenEntry.unreadable(
            index: i,
            value: e,
            lexeme: lexeme,
            orderId: _rawOrderId(e),
            violation: violation ?? 'record: undecodable',
          ),
        );
        continue;
      }
      final inScope =
          a.organizationId == identity.scope.organizationId &&
          a.restaurantId == identity.scope.restaurantId &&
          a.branchId == identity.scope.branchId &&
          a.deviceId == identity.scope.deviceId;
      entries.add(
        inScope
            ? FrozenEntry.inScope(
                index: i,
                value: e,
                lexeme: lexeme,
                attempt: a,
              )
            : FrozenEntry.foreignScope(
                index: i,
                value: e,
                lexeme: lexeme,
                attempt: a,
              ),
      );
    }
    return SnapshotReady(
      context: ctx,
      entries: List<FrozenEntry>.unmodifiable(entries),
      rawBytes: raw,
    );
  }

  /// The snapshot, taken OUTSIDE the write queue exactly as reads are today.
  ///
  /// A production API: the Owner-B mint gate consults it before any identity is
  /// allocated, and the incident callables take it inside the write queue.
  Future<SnapshotResult> readEnvelopeSnapshot(
    PosSyncScope scope,
    CanonicalOrderId orderId,
  ) async {
    final identity = PaymentEnvelopeIdentity.fromScope(scope, orderId);
    final SharedPreferences prefs;
    try {
      prefs = await _resolvePrefs();
    } catch (_) {
      return SnapshotReadFailed(
        context: EnvelopeSnapshotContext(
          identity,
          _guardFor(identity.physicalBackingKey).generation,
          SnapshotTrust.untrusted,
        ),
      );
    }
    return _readEnvelopeSnapshotLocked(prefs, identity);
  }

  /// Whether the generation this snapshot observed is still current.
  bool _generationStillCurrent(
    PaymentEnvelopeIdentity identity,
    int observed,
  ) => _guardFor(identity.physicalBackingKey).generation == observed;

  /// K3-B03 — the durability TRI-STATE.
  ///
  /// `_write` already believes only the adapter's own success report or an
  /// independent read of the exact intended bytes. When it answers false, this
  /// takes ONE further independent read to see whether the PREVIOUS bytes are
  /// provably still there; anything else stays `unknown`. A false from
  /// `_verifyDurable` is not evidence the old bytes survived.
  Future<DurabilityKnowledge> _writeAndClassify(
    SharedPreferences prefs,
    PosSyncScope scope,
    List<Object?> entries,
    String preWriteRaw,
  ) async {
    final ok = await _write(prefs, scope, entries);
    if (ok) return DurabilityKnowledge.verifiedNew;
    final reader = _backingReader;
    if (reader == null) return DurabilityKnowledge.unknown;
    final String? observed;
    try {
      observed = await reader.readRaw(paymentAttemptsPhysicalKey(scope.key));
    } catch (_) {
      return DurabilityKnowledge.unknown;
    }
    if (observed == preWriteRaw) return DurabilityKnowledge.verifiedOld;
    return DurabilityKnowledge.unknown;
  }

  // =========================================================================
  // OWNER-B — the APPLIED incident resolution, and the durable promotion
  // =========================================================================

  /// Promotes an isolate-only fail-closed incident into a DURABLE active
  /// replacement block on its own parent record.
  ///
  /// This is NOT the APPLIED path and shares none of its steps: promotion
  /// CREATES the first block, so it requires that none exists.
  Future<IncidentPromotionResult> promoteIncidentToDurable({
    required PosSyncScope scope,
    required PaymentSafetyRegistry registry,
    required PaymentFailClosedIncident incident,
    required ActivityOwnerToken expectedOwnerToken,
    required int expectedSafetyEpoch,
    required String blockId,
    required String at,
    bool Function()? authority,
  }) => _serializedWrite(scope, () async {
    if (authority != null && !authority()) {
      return IncidentPromotionAuthorityLapsed(registry);
    }
    final SharedPreferences prefs;
    try {
      prefs = await _resolvePrefs();
    } catch (_) {
      _degraded = true;
      return IncidentPromotionSnapshotUnusable(
        registry,
        SnapshotReadFailed(
          context: EnvelopeSnapshotContext(
            PaymentEnvelopeIdentity.fromScope(scope, incident.key.orderId),
            0,
            SnapshotTrust.untrusted,
          ),
        ),
      );
    }
    final identity = PaymentEnvelopeIdentity.fromScope(
      scope,
      incident.key.orderId,
    );
    final snap = await _readEnvelopeSnapshotLocked(prefs, identity);
    if (snap is! SnapshotReady) {
      return IncidentPromotionSnapshotUnusable(registry, snap);
    }

    final selection = selectExactAttemptSubject(
      snapshot: snap,
      key: incident.key,
      localOperationId: incident.operationId,
      requireActiveReplacementBlock: false,
      incident: incident,
    );
    if (selection is! SubjectSelected) {
      return IncidentPromotionSubjectUnusable(registry, selection);
    }
    final subject = selection.subject;

    if (incident.state != IncidentState.active) {
      return IncidentPromotionSubjectUnusable(
        registry,
        const SubjectIncidentDisagrees('X5', 'incident is not active'),
      );
    }
    if (incident.binding != subject.binding) {
      return IncidentPromotionSubjectUnusable(
        registry,
        const SubjectIncidentDisagrees('X3', 'binding != incident binding'),
      );
    }
    final owner = registry.ownerOf(incident.key);
    if (owner == null) {
      return IncidentPromotionOwnerMismatch(
        registry,
        RegistryRefusalReason.noOwner,
      );
    }
    if (owner.ownerToken != expectedOwnerToken) {
      return IncidentPromotionOwnerMismatch(
        registry,
        RegistryRefusalReason.ownerTokenMismatch,
      );
    }
    if (owner.safetyEpoch != expectedSafetyEpoch) {
      return IncidentPromotionOwnerMismatch(
        registry,
        RegistryRefusalReason.ownerEpochMismatch,
      );
    }
    if (!owner.handoff.isFailClosed) {
      return IncidentPromotionOwnerMismatch(
        registry,
        RegistryRefusalReason.ownerNotFailClosed,
      );
    }

    final parent = subject.parent;
    if (parent.phase != PaymentAttemptPhase.refused &&
        parent.phase != PaymentAttemptPhase.settledElsewhere) {
      return IncidentPromotionSubjectUnusable(
        registry,
        const SubjectForeignSubject('parent is not a contradicted terminal'),
      );
    }
    final truth = incident.acceptedTruth;
    if (truth == null) {
      return IncidentPromotionCandidateInvalid(
        registry,
        'incident truth is not accepted-class',
      );
    }
    if (!isCanonicalInstant(at) || blockId.trim().isEmpty) {
      return IncidentPromotionCandidateInvalid(
        registry,
        'observed_at or block_id is not usable',
      );
    }

    // Uniqueness never rests on the id source — the GENERATION carries it.
    final occurrence =
        incident.occurrence ??
        BlockOccurrence(_nextBlockGeneration(snap, parent), blockId);

    final block = PaymentReplacementBlock(
      generation: occurrence.generation,
      blockId: occurrence.blockId,
      status: BlockStatus.active,
      contradictedOperationId: parent.localOperationId,
      contradictedPhase: parent.phase,
      reason: IncidentReason.ownerBContradiction,
      evidenceSource: truth.evidenceSource,
      observedAt: at,
      serverTruth: truth,
      resolution: null,
    );

    // Validate the candidate by re-decoding its own encoding against the parent
    // it will sit on.
    final entry = <String, Object?>{
      ...parent.toJson(),
      kReplacementBlockKey: block.toJson(),
    };
    final check = decodeReplacementBlockField(
      entry,
      PaymentAttemptParentFacts.of(parent),
      incidentOccurrence: occurrence,
      incidentTruth: truth,
      incidentOperationId: incident.operationId,
    );
    if (check is! BlockDecoded || check.block.status != BlockStatus.active) {
      final why = check is BlockMalformed
          ? '${check.rule}: ${check.message}'
          : 'block did not survive re-decode';
      return IncidentPromotionCandidateInvalid(registry, why);
    }

    if (authority != null && !authority()) {
      return IncidentPromotionAuthorityLapsed(registry);
    }
    if (!_generationStillCurrent(identity, snap.context.generation)) {
      return IncidentPromotionGenerationRaced(
        registry,
        snap.context.generation,
        _guardFor(identity.physicalBackingKey).generation,
      );
    }

    final planned = _planEntries(snap, subject.entryIndex, entry);
    final knowledge = await _writeAndClassify(
      prefs,
      scope,
      planned,
      snap.rawBytes,
    );
    if (knowledge != DurabilityKnowledge.verifiedNew) {
      _degraded = true;
      return IncidentPromotionNotDurable(registry, knowledge);
    }

    // Durability only. The incident stays ACTIVE: promotion makes the block
    // durable, it does not resolve anything.
    final t = replaceIncidentIfExact(
      registry: registry,
      key: incident.key,
      expectedOccurrence: incident.occurrence,
      nextIncident: incident.copyWith(
        occurrence: occurrence,
        durability: DurableRecordBlock(occurrence),
      ),
    );
    if (t is RegistryTransitionRefused) {
      return IncidentPromotionOwnerMismatch(registry, t.reason);
    }
    final applied = t as RegistryTransitionApplied;
    return IncidentPromoted(
      applied.registry,
      applied.incident!,
      parent,
      check.block,
    );
  });

  /// K3-B05 + counterexample H — the APPLIED incident resolution.
  ///
  /// Exactly one write, at step 13. Steps 1-12 touch nothing. The incident
  /// clears only after step 14 proved the new bytes durable, and every
  /// condition step 15 can refuse on has already been checked BEFORE the write,
  /// so there is no ordering in which the parent moves and the incident stands.
  Future<IncidentResolutionResult> resolveIncidentApplied({
    required PosSyncScope scope,
    required PaymentSafetyRegistry registry,
    required PaymentFailClosedIncident incident,
    required ActivityOwnerToken expectedOwnerToken,
    required BlockOccurrence expectedOccurrence,
    required int expectedSafetyEpoch,
    required AcceptedTruth freshTruth,
    required String at,
    required bool sameWorld,
    bool Function()? authority,
  }) => _serializedWrite(scope, () async {
    // 1 — authority, inside the serialized window.
    if (authority != null && !authority()) {
      return IncidentResolutionAuthorityLapsed(registry);
    }

    final identity = PaymentEnvelopeIdentity.fromScope(
      scope,
      incident.key.orderId,
    );
    final SharedPreferences prefs;
    try {
      prefs = await _resolvePrefs();
    } catch (_) {
      _degraded = true;
      return IncidentResolutionSubjectUnusable(
        registry,
        const SubjectForeignSubject('preferences unavailable'),
      );
    }

    // 2 — the authoritative snapshot is the ONLY subject source.
    final snap = await _readEnvelopeSnapshotLocked(prefs, identity);
    if (snap is! SnapshotReady) {
      return IncidentResolutionSnapshotUnusable(registry, snap);
    }

    // 3/4 — exact parent by order + operation, with an exact ACTIVE block.
    final selection = selectExactAttemptSubject(
      snapshot: snap,
      key: incident.key,
      localOperationId: incident.operationId,
      requireActiveReplacementBlock: true,
      incident: incident,
    );
    if (selection is! SubjectSelected) {
      return IncidentResolutionSubjectUnusable(registry, selection);
    }
    final subject = selection.subject;
    final activeBlock = subject.activeBlock!;

    // 5 — the REGISTRY's incident is the one being resolved. Checked BEFORE the
    // write, so step 15 cannot refuse after the parent has already moved.
    final live = registry.incidentOf(incident.key);
    if (live == null) {
      return IncidentResolutionRefusedOccurrence(
        registry,
        expectedOccurrence,
        null,
      );
    }
    if (live.state != IncidentState.active ||
        live.occurrence != expectedOccurrence ||
        live.occurrence != activeBlock.occurrence ||
        live.operationId != incident.operationId ||
        live.binding != incident.binding ||
        live.serverTruth != incident.serverTruth) {
      return IncidentResolutionRefusedOccurrence(
        registry,
        expectedOccurrence,
        live.occurrence,
      );
    }

    // 6 — exact owner token, epoch and fail-closed handoff.
    final owner = registry.ownerOf(incident.key);
    if (owner == null) return IncidentResolutionOwnerAbsent(registry);
    if (owner.ownerToken != expectedOwnerToken) {
      return IncidentResolutionOwnerMismatch(
        registry,
        RegistryRefusalReason.ownerTokenMismatch,
      );
    }
    if (owner.safetyEpoch != expectedSafetyEpoch) {
      return IncidentResolutionOwnerMismatch(
        registry,
        RegistryRefusalReason.ownerEpochMismatch,
      );
    }
    if (!owner.handoff.isFailClosed) {
      return IncidentResolutionOwnerMismatch(
        registry,
        RegistryRefusalReason.ownerNotFailClosed,
      );
    }

    // 7 — exact contradicted terminal parent.
    final parent = subject.parent;
    if (parent.phase != PaymentAttemptPhase.refused &&
        parent.phase != PaymentAttemptPhase.settledElsewhere) {
      return IncidentResolutionSubjectUnusable(
        registry,
        const SubjectForeignSubject('parent is not a contradicted terminal'),
      );
    }

    // 8 — OD-1. The recorded truth must be accepted-class AND the fresh truth
    // must be the SAME MONEY. A refusal cannot even reach here: the parameter
    // type is AcceptedTruth.
    final recorded = live.acceptedTruth;
    if (recorded == null) {
      return IncidentResolutionRefusedEvidence(registry, live.serverTruth);
    }
    if (!sameMoneyTruth(freshTruth.resolution, recorded.resolution)) {
      return IncidentResolutionRefusedContradictoryTruth(
        registry,
        recorded,
        freshTruth,
      );
    }

    // 9 — tender gate. `PaymentAttemptResolution.fromJson` applies this only
    // when a tenderType is supplied, and the ServerTruth codec has no attempt.
    if (!truthTenderMatches(freshTruth, parent.tenderType)) {
      return IncidentResolutionTenderMismatch(
        registry,
        freshTruth.resolution.method.wire,
        parent.tenderType,
      );
    }

    // 10/11 — resolved block + the EXPLICIT accepted candidate.
    if (!isCanonicalInstant(at)) {
      return IncidentResolutionCandidateInvalid(
        registry,
        'B4a',
        'at is not a canonical instant',
      );
    }
    final resolvedBlock = activeBlock.resolvedWith(
      BlockResolution(
        kind: BlockResolutionKind.applied,
        resolvedAt: at,
        resolutionOperationId: parent.localOperationId,
        resolutionTruth: freshTruth,
      ),
    );
    final built = buildAcceptedCandidateFromContradictedParent(
      parent: parent,
      freshTruth: freshTruth,
      resolvedBlock: resolvedBlock,
      at: at,
    );
    if (built is AcceptedCandidateInvalid) {
      return IncidentResolutionCandidateInvalid(
        registry,
        built.rule,
        built.message,
      );
    }
    final candidate = built as AcceptedCandidateBuilt;

    // 12 — authority again, then the generation guard.
    if (authority != null && !authority()) {
      return IncidentResolutionAuthorityLapsed(registry);
    }
    if (!_generationStillCurrent(identity, snap.context.generation)) {
      return IncidentResolutionGenerationRaced(
        registry,
        snap.context.generation,
        _guardFor(identity.physicalBackingKey).generation,
      );
    }

    // 13 — ONE write, substituting by index. Every other entry passes through
    // by reference and is proven unchanged by its frozen lexeme.
    final planned = _planEntries(
      snap,
      subject.entryIndex,
      candidate.entryValue,
    );
    if (!_preservesFrozenLexemes(snap, subject.entryIndex, planned)) {
      return IncidentResolutionCandidateInvalid(
        registry,
        'PRES',
        'an untouched entry would not re-encode to its frozen lexeme',
      );
    }
    final knowledge = await _writeAndClassify(
      prefs,
      scope,
      planned,
      snap.rawBytes,
    );

    // 14 — only verifiedNew proceeds.
    if (knowledge != DurabilityKnowledge.verifiedNew) {
      _degraded = true;
      return IncidentResolutionWriteFailed(registry, knowledge);
    }

    // 15 — ONE atomic registry transition, after durable proof.
    final t = clearIncidentAndReleaseOwnerIfExact(
      registry: registry,
      key: incident.key,
      expectedOwnerToken: expectedOwnerToken,
      expectedOccurrence: expectedOccurrence,
      expectedSafetyEpoch: expectedSafetyEpoch,
    );
    if (t is RegistryTransitionRefused) {
      return IncidentResolutionOwnerMismatch(registry, t.reason);
    }

    // 16 — accepted-class public truth. The effect claim is a FIRST claim here
    // by construction: a decoded contradicted parent can never carry one.
    return IncidentResolvedApplied(
      registry: t.registry,
      acceptedParent: candidate.candidate,
      resolvedOccurrence: expectedOccurrence,
      block: candidate.block,
      effectsArmed:
          freshTruth.evidenceSource == BlockEvidenceSource.directSend &&
          sameWorld,
    );
  });

  /// The next block generation for [parent]: one past the highest already
  /// recorded on it, so a retained resolved block forces `generation + 1` and a
  /// stale clear keyed on the old occurrence can never match.
  static int _nextBlockGeneration(SnapshotReady snap, PaymentAttempt parent) {
    var highest = 0;
    for (final e in snap.entries) {
      if (e.attempt?.localOperationId != parent.localOperationId) continue;
      final raw = paymentAttemptRawBlock(e.value);
      if (raw is Map) {
        final g = raw['generation'];
        if (g is int && g > highest) highest = g;
      }
    }
    return highest + 1;
  }

  /// The entry list for a write: [replacement] at [index], every other entry
  /// passed through BY REFERENCE.
  static List<Object?> _planEntries(
    SnapshotReady snap,
    int index,
    Object? replacement,
  ) {
    final out = <Object?>[];
    for (final e in snap.entries) {
      out.add(e.index == index ? replacement : e.value);
    }
    return out;
  }

  /// §8 — every untouched surviving entry must still encode EXACTLY to the
  /// lexeme frozen when the snapshot was taken. Not a substring test, not an
  /// object-identity test: the production encoder is re-run and compared.
  static bool _preservesFrozenLexemes(
    SnapshotReady snap,
    int mutatedIndex,
    List<Object?> planned,
  ) {
    if (planned.length != snap.entries.length) return false;
    for (var i = 0; i < planned.length; i++) {
      if (i == mutatedIndex) continue;
      if (jsonEncode(planned[i]) != snap.entries[i].lexeme) return false;
    }
    return true;
  }

  /// Sentinel meaning "the caller gave no block instruction". A plain `null`
  /// cannot serve, because `null` is itself a meaningful instruction (remove).
  static const Object _absentBlock = Object();

  /// The persisted entry for [a]: its own 26 keys, plus the optional 27th when
  /// a block stands. The record's own `toJson` is never altered.
  static Object? _entryWithBlock(PaymentAttempt a, Object? block) {
    final json = a.toJson();
    if (block == null) return json;
    return <String, Object?>{...json, kReplacementBlockKey: block};
  }

  /// Rebuilds the stored entry list with [replacement] swapped in for its
  /// `local_operation_id` (or appended), pruning only RESOLVED readable
  /// records beyond the retention cap. Unreadable entries pass through
  /// byte-verbatim in their original positions.
  static List<Object?> _rebuild(
    List<Object?> raws,
    PaymentAttempt replacement,
    PosSyncScope scope, {

    /// K3-B04/B05 — the block to install on the replaced entry.
    ///
    /// `_absentBlock` means "no explicit instruction": the entry keeps whatever
    /// block it already carried. That default matters for safety — an ordinary
    /// `update` or `resolveAccepted` write must never silently DROP an active
    /// replacement block that is holding an order fail-closed. Passing `null`
    /// explicitly removes the block; passing a map installs it.
    Object? replacementBlock = _absentBlock,
  }) {
    final out = <Object?>[];
    var replaced = false;
    for (final e in raws) {
      // S1-R4 / F003: the entry to replace is chosen with the SAME scope-aware
      // classification `load` uses, not bare decodability plus a matching
      // operation id. Codex proved the difference: a FOREIGN-SCOPE raw sibling
      // that decodes structurally but belongs to another till was selected and
      // destroyed byte-for-byte, while the healthy in-scope record it should
      // have updated was left stale.
      if (!replaced &&
          _isInScope(e, scope) &&
          _rawOpId(e) == replacement.localOperationId) {
        out.add(
          _entryWithBlock(
            replacement,
            identical(replacementBlock, _absentBlock)
                ? paymentAttemptRawBlock(e)
                : replacementBlock,
          ),
        );
        replaced = true;
      } else {
        out.add(e);
      }
    }
    if (!replaced) {
      out.add(
        _entryWithBlock(
          replacement,
          identical(replacementBlock, _absentBlock) ? null : replacementBlock,
        ),
      );
    }

    // Prune: count resolved readable records newest-last; drop the OLDEST
    // beyond the cap. Never a pending record, never a raw we cannot read.
    //
    // S1-R5 / F003 — the CAP and the VICTIM are two different questions.
    //
    // The cap bounds the whole stored envelope, so every resolved readable
    // record it holds counts against it, whatever scope wrote it. Which record
    // may be deleted to satisfy that cap is a separate matter: a FOREIGN-SCOPE
    // record is evidence belonging to another till, which `load` correctly
    // reports as quarantine and which this device may never destroy. R4
    // counted and pruned with one predicate, so the foreign raw was the first
    // thing deleted while an eligible in-scope record survived.
    //
    // Counting foreign records but refusing to delete them is the
    // conservative direction: this scope's own resolved history is trimmed a
    // little sooner — it is already terminal and recoverable — and no evidence
    // that is not ours is ever lost.
    var resolved = 0;
    for (final e in out) {
      if (_isResolvedReadable(e)) resolved++;
    }
    var toDrop = resolved - kPaymentAttemptsResolvedRetention;
    if (toDrop <= 0) return out;
    final pruned = <Object?>[];
    for (final e in out) {
      if (toDrop > 0 && _isRetentionPrunable(e, scope)) {
        toDrop--;
        continue;
      }
      pruned.add(e);
    }
    return pruned;
  }

  /// Whether [e] decodes AND belongs to [scope] — the exact test `load` uses
  /// to decide a record is ours rather than quarantined foreign evidence.
  static bool _isInScope(Object? e, PosSyncScope scope) {
    final PaymentAttempt a;
    try {
      a = PaymentAttempt.fromJson(paymentAttemptProjection(e));
    } catch (_) {
      return false;
    }
    return a.organizationId == scope.organizationId &&
        a.restaurantId == scope.restaurantId &&
        a.branchId == scope.branchId &&
        a.deviceId == scope.deviceId;
  }

  /// Whether [e] decodes and holds a resolved phase — the CAP question.
  static bool _isResolvedReadable(Object? e) {
    try {
      return PaymentAttempt.fromJson(
        paymentAttemptProjection(e),
      ).phase.isResolved;
    } catch (_) {
      return false;
    }
  }

  /// S1-R5 / F003 — whether [e] is this scope's OWN resolved history, and so
  /// the only kind of entry retention may delete.
  ///
  /// A record that does not decode is unreadable evidence and passes through
  /// byte-verbatim; a record that decodes but belongs to another till is
  /// FOREIGN evidence, which `load` reports as quarantine and which this
  /// device may never destroy to make room for its own history.
  static bool _isRetentionPrunable(Object? e, PosSyncScope scope) =>
      _isInScope(e, scope) &&
      _isResolvedReadable(e) &&
      !_holdsReplacementEvidence(e);

  /// Whether [e] carries replacement-block evidence retention may not destroy.
  ///
  /// Deliberately conservative and decode-free: ANY entry carrying the 27th key
  /// is exempt, whether its block is active, resolved or malformed.
  ///
  ///   * an ACTIVE block is what holds an order fail-closed — pruning it would
  ///     silently release the containment;
  ///   * a RESOLVED block is what forces the next occurrence to `generation + 1`
  ///     — pruning it would let a reused block id match a stale clear, which is
  ///     the ABA the generation exists to prevent;
  ///   * a MALFORMED one is evidence this build cannot read, and a record it
  ///     cannot read is not one it is entitled to destroy.
  static bool _holdsReplacementEvidence(Object? e) =>
      e is Map && e.containsKey(kReplacementBlockKey);

  @override
  Future<PaymentAttemptClaim> createIfAbsent(
    PosSyncScope scope,
    PaymentAttempt attempt,
  ) => _serializedWrite(scope, () async {
    final SharedPreferences prefs;
    try {
      prefs = await _resolvePrefs();
    } catch (_) {
      _degraded = true;
      throw const PosPersistenceException(
        'payment attempts: preferences unavailable',
      );
    }
    final r = await _readForWrite(prefs, scope);
    if (r.envelopeUnreadable) {
      // Never overwrite evidence we cannot read (it may hold an unresolved
      // attempt); the caller reports the quarantine and sends nothing.
      throw const PosPersistenceException(
        'payment attempts: the stored envelope is unreadable',
      );
    }
    // S1-R3 / F003: unreadable evidence whose order cannot be EXCLUDED blocks
    // a new attempt here, at the store, not only in a controller precheck. A
    // record this build cannot decode may be an unresolved attempt for this
    // very order; minting a second identity beside it is how one order gets
    // charged twice.
    for (final q in r.quarantined) {
      if (q.orderId == null || q.orderId == attempt.orderId) {
        _degraded = true;
        throw const PosPersistenceException(
          'payment attempts: unreadable stored evidence for this order must be '
          'resolved before another attempt can be created',
        );
      }
    }
    for (final existing in r.attempts) {
      if (existing.isPending && existing.orderId == attempt.orderId) {
        return PaymentAttemptClaim(attempt: existing, created: false);
      }
    }
    final ok = await _write(prefs, scope, _rebuild(r.raws, attempt, scope));
    if (ok) return PaymentAttemptClaim(attempt: attempt, created: true);

    // PDR-001: `_write` already adjudicated the reported failure against an
    // INDEPENDENT backing read. Re-reading through the writing adapter here
    // would only consult its optimistic cache, so there is nothing further to
    // consider: the record is not provably durable and nothing may be sent.
    _degraded = true;
    throw const PosPersistenceException(
      'payment attempts: the attempt could not be persisted',
    );
  });

  @override
  Future<PaymentAttemptAcceptance> resolveAccepted(
    PosSyncScope scope,
    PaymentAttempt attempt,
    PaymentAttemptResolution resolution, {
    required String at,
    required bool armCaller,
    bool Function()? authority,
  }) => _serializedWrite(scope, () async {
    final SharedPreferences prefs;
    try {
      prefs = await _resolvePrefs();
    } catch (_) {
      _degraded = true;
      throw const PosPersistenceException(
        'payment attempts: preferences unavailable',
      );
    }
    final r = await _readForWrite(prefs, scope);
    if (r.envelopeUnreadable) {
      throw const PosPersistenceException(
        'payment attempts: the stored envelope is unreadable',
      );
    }
    // S1-R5 / F001 — AUTHORITY IS RE-CHECKED INSIDE THE MUTATION.
    //
    // R4 checked the controller's generation once, BEFORE awaiting this call.
    // The physical-key queue can hold this closure for arbitrarily long, so
    // authority could lapse after that check and before the write. Codex
    // proved the consequence: a replaced controller's acceptance still
    // persisted and consumed the one-time automatic-effect reservation for a
    // world that no longer existed. The predicate is therefore evaluated
    // again here — in the same serialized section that performs the write,
    // after the last await that precedes it.
    if (authority != null && !authority()) {
      throw const PosPersistenceException(
        'payment attempts: authority lapsed before the acceptance was written',
      );
    }
    // The LIVE record decides whether the reservation is still free — not
    // the caller's possibly stale copy.
    PaymentAttempt? live;
    for (final a in r.attempts) {
      if (a.localOperationId == attempt.localOperationId) live = a;
    }
    if (live == null) {
      // Resolving is not creating. A caller whose record is not on disk has
      // nothing to resolve, and may not write an acceptance beside the
      // current truth — most likely its own create was never durable, or the
      // record belongs to another scope and is quarantined evidence here.
      // `update` has refused this since R4; the acceptance path had not.
      throw const PosPersistenceException(
        'payment attempts: no stored record for this operation to resolve',
      );
    }
    // S1-R5 / F001 — the SAME guarded transition `update` applies.
    //
    // R4 called `.accepted()` on the live record directly and wrote the
    // result, so this path had neither the full frozen decision identity nor
    // terminal monotonicity. Codex proved both holes: a stored TERMINAL
    // REFUSAL was overwritten into an accepted-plus-refusal record that only
    // the next load's quarantine caught, and a proposal agreeing on nothing
    // but the operation id — a different amount — flipped the stored record
    // to accepted. `reconcilePaymentAttempt` decides first; only an APPLIED
    // outcome is written, and only it may reserve an effect.
    final alreadyReserved = live.autoEffectsReservedAt != null;
    final merge = reconcilePaymentAttempt(
      live,
      attempt.accepted(resolution, at: at, reserveEffects: true),
    );
    switch (merge.outcome) {
      case PaymentAttemptMergeOutcome.stale:
      case PaymentAttemptMergeOutcome.conflict:
        // A terminal answer already stands, or the two records do not describe
        // the same decision. Nothing is written, nothing is reserved, and the
        // stored evidence is left exactly as it is.
        throw const PosPersistenceException(
          'payment attempts: the acceptance contradicts the stored record',
        );
      case PaymentAttemptMergeOutcome.redundant:
        // This exact acceptance is already durable. Its reservation was
        // consumed when it was first written, so nothing is armed again.
        return PaymentAttemptAcceptance(
          attempt: merge.record,
          armed: armCaller && !alreadyReserved,
        );
      case PaymentAttemptMergeOutcome.applied:
        break;
    }
    final resolved = merge.record;
    final ok = await _write(prefs, scope, _rebuild(r.raws, resolved, scope));
    if (!ok) {
      // PDR-001: an unverified acceptance write may never arm an automatic
      // effect. The payment itself is unaffected — the server already took it.
      _degraded = true;
      throw const PosPersistenceException(
        'payment attempts: the acceptance could not be persisted',
      );
    }
    return PaymentAttemptAcceptance(
      attempt: resolved,
      armed: armCaller && !alreadyReserved,
    );
  });

  @override
  Future<PaymentAttemptMerge> update(
    PosSyncScope scope,
    PaymentAttempt attempt,
  ) => _serializedWrite(scope, () async {
    final SharedPreferences prefs;
    try {
      prefs = await _resolvePrefs();
    } catch (_) {
      _degraded = true;
      throw const PosPersistenceException(
        'payment attempts: preferences unavailable',
      );
    }
    final r = await _readForWrite(prefs, scope);
    if (r.envelopeUnreadable) {
      throw const PosPersistenceException(
        'payment attempts: the stored envelope is unreadable',
      );
    }
    // S1-R4 / F001 — a GUARDED TRANSITION, not a wholesale swap.
    //
    // The R3 build replaced the matching record with whatever snapshot the
    // caller happened to be holding. Codex proved the consequence: an old
    // controller whose provider had already been rebound persisted its late
    // `authRequired` diagnostic over a NEWER accepted record, erasing the
    // resolution and the one-time effect reservation, so a later replay armed
    // the automatic receipt and drawer a second time for one payment.
    //
    // The stored record is now the starting point. The caller's value is a
    // PROPOSAL, reconciled against it, and only a genuine advance is written.
    PaymentAttempt? current;
    for (final a in r.attempts) {
      if (a.localOperationId == attempt.localOperationId) current = a;
    }
    if (current == null) {
      // An update is not a create. A caller holding a record that is not on
      // disk has nothing to transition — most likely because its own write was
      // never durable — and may not resurrect it beside the current truth.
      throw const PosPersistenceException(
        'payment attempts: no stored record for this operation to update',
      );
    }
    final merge = reconcilePaymentAttempt(current, attempt);
    if (!merge.writes) {
      // Stale, redundant or conflicting: the stored record stands, and the
      // caller is told what actually holds rather than what it hoped to save.
      return merge;
    }
    final ok = await _write(
      prefs,
      scope,
      _rebuild(r.raws, merge.record, scope),
    );
    if (ok) return merge;
    // PDR-001: adjudicated in `_write` against an independent read.
    _degraded = true;
    throw const PosPersistenceException(
      'payment attempts: the attempt update could not be persisted',
    );
  });
}

/// PDR-001 — the production independent reader.
///
/// Uses `SharedPreferencesAsync` from the SAME already-declared and pinned
/// `shared_preferences` package as the writer. Its reads go straight to the
/// platform with no adapter cache in between
/// (`shared_preferences-2.5.5/lib/src/shared_preferences_async.dart`:
/// `getString` is `_platform.getString(key, _options)`), which is precisely
/// what a reported write failure has to be adjudicated against.
///
/// TARGET MAPPING, which is the whole difficulty.
///
///   * WEB, iOS, macOS, Linux, Windows — the async API addresses the SAME
///     physical store the legacy writer uses, so reading the `flutter.`
///     -prefixed physical key is genuine independent evidence.
///   * ANDROID — it does NOT. The async API defaults to Jetpack DataStore
///     (`shared_preferences_android-2.4.26/lib/src/messages_async.g.dart`,
///     `useDataStore = true`), a different physical store from the legacy XML
///     file `FlutterSharedPreferences` the writer uses
///     (`.../SharedPreferencesPlugin.kt`). Reading it would report every
///     record missing. Pointing the async API back at the legacy backend needs
///     `SharedPreferencesAsyncAndroidOptions`, which lives in
///     `shared_preferences_android` — a TRANSITIVE package this app does not
///     declare. Adding it is a dependency change and is out of this slice.
///
/// So on Android this reader declares itself UNAVAILABLE instead of reading
/// the wrong store. The effect is fail-closed: a reported write failure stays
/// a failure, nothing is sent and no effect is armed. That is safe, it is
/// never a false confirmation, and it is deliberately visible rather than
/// silent. Recovering a genuinely-landed Android write needs the declared
/// dependency; see the S1 report.
/// Why a target can or cannot adjudicate a reported write failure.
enum PaymentAttemptBackingReadSupport {
  /// The async API addresses the SAME physical key space as the writer with no
  /// intervening cache. Installed web 2.4.3 reads `window.localStorage`.
  supported,

  /// The async API addresses a DIFFERENT physical backend. Android async
  /// defaults to Jetpack DataStore while the legacy writer uses the
  /// `FlutterSharedPreferences` XML store.
  differentBackend,

  /// The installed platform implementation registers one singleton that caches
  /// the file contents, so a new facade re-reads that cache (Linux, Windows).
  cachedPlatformSingleton,

  /// The key mapping is source-visible but independence from the platform's
  /// own process cache has NOT been verified here (iOS, macOS).
  independenceNotVerified,
}

class SharedPreferencesAsyncBackingReader
    implements PaymentAttemptBackingReader {
  SharedPreferencesAsyncBackingReader({SharedPreferencesAsync? prefs})
    : _injected = prefs;

  /// Supplied by tests. Production resolves lazily, because constructing
  /// `SharedPreferencesAsync` THROWS when no async platform is registered
  /// (`shared_preferences-2.5.5/lib/src/shared_preferences_async.dart`
  /// constructor) and this seam must never take the payment path down with
  /// it: no reader simply means no independent evidence, which fails closed.
  final SharedPreferencesAsync? _injected;

  /// Why an independent backing read is, or is not, available on this target.
  ///
  /// S1-R3 corrects the R2 classification. Codex read the INSTALLED packages
  /// and found that `shared_preferences_linux-2.4.1`
  /// (`shared_preferences_linux.dart:144-151,287-300,322-328`) and
  /// `shared_preferences_windows-2.4.1`
  /// (`shared_preferences_windows.dart:144-152,288-301,323-329`) register ONE
  /// async platform singleton that keeps its own `_cachedPreferences`. A new
  /// `SharedPreferencesAsync` facade is therefore NOT a fresh backing read
  /// there, and this build never invokes those packages' test-only reload
  /// seam. Claiming independence on those targets would have made a stale
  /// snapshot look like proof.
  static PaymentAttemptBackingReadSupport get targetSupport {
    if (kIsWeb) return PaymentAttemptBackingReadSupport.supported;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return PaymentAttemptBackingReadSupport.differentBackend;
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return PaymentAttemptBackingReadSupport.cachedPlatformSingleton;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
        return PaymentAttemptBackingReadSupport.independenceNotVerified;
    }
  }

  /// Whether an independent read can address the writer's own store here.
  static bool get isSupportedTarget =>
      targetSupport == PaymentAttemptBackingReadSupport.supported;

  @override
  Future<String?> readRaw(String physicalKey) async {
    if (!isSupportedTarget) {
      throw UnsupportedError(
        'payment attempts: no independent backing read is available on this '
        'target (${targetSupport.name}) with the declared dependencies, so a '
        'reported write failure is final',
      );
    }
    final prefs = _injected ?? SharedPreferencesAsync();
    return prefs.getString(physicalKey);
  }
}

/// The file the legacy Android plugin stores preferences in. Recorded for the
/// S1 report and for whoever implements the Android reader later.
const String kLegacyAndroidSharedPreferencesFileName =
    'FlutterSharedPreferences';

/// The store seam. Production resolves `shared_preferences` lazily; tests
/// inject a store over mock-initialised or deliberately failing preferences.
final paymentAttemptStoreProvider = Provider<PaymentAttemptStore>(
  (ref) => SharedPrefsPaymentAttemptStore.lazy(
    backingReader: SharedPreferencesAsyncBackingReader(),
  ),
);

// ===========================================================================
// K3-B01 — authoritative storage identity and the snapshot algebra
// ===========================================================================

/// Everything a payment envelope is addressed by, derived from ONE scope.
///
/// The raw scope is carried WHOLE beside the derived strings, because
/// `PosSyncScope.key` is lossy: it joins the four fields with `.` and `.` is
/// inside its own allowed character class, so two genuinely different tills can
/// share one storage key. Money safety keys on the raw fields (see
/// [PaymentActivityKey]); these strings are storage addresses, not identity.
@immutable
final class PaymentEnvelopeIdentity {
  const PaymentEnvelopeIdentity._(
    this.scope,
    this.orderId,
    this.scopeKey,
    this.logicalPrefsKey,
    this.physicalBackingKey,
    this.guardKey,
  );

  factory PaymentEnvelopeIdentity.fromScope(
    PosSyncScope scope,
    CanonicalOrderId orderId,
  ) {
    final sk = scope.key;
    final physical = paymentAttemptsPhysicalKey(sk);
    return PaymentEnvelopeIdentity._(
      scope,
      orderId,
      sk,
      paymentAttemptsStorageKey(sk),
      physical,
      paymentAttemptGuardKey(physical),
    );
  }

  /// The RAW four-field scope, whole. This — not [scopeKey] — is identity.
  final PosSyncScope scope;
  final CanonicalOrderId orderId;

  /// LOSSY. A derivation input and a diagnostic; never an identity proof.
  final String scopeKey;

  /// What the WRITER passes to `SharedPreferences`.
  final String logicalPrefsKey;

  /// What an INDEPENDENT reader must ask for (the `flutter.` prefix).
  final String physicalBackingKey;

  /// The isolate trust/serialisation boundary name.
  final String guardKey;

  PaymentActivityKey get activityKey =>
      PaymentActivityKey(scope: scope, orderId: orderId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentEnvelopeIdentity &&
          scope == other.scope &&
          orderId == other.orderId;

  @override
  int get hashCode => Object.hash(scope, orderId);
}

enum SnapshotTrust { trusted, untrusted }

enum UntrustedReason {
  noIndependentReader,
  generationRaced,

  /// A cache-mutating write for this key is still in flight, or an earlier one
  /// was never proven durable. An independent read taken now cannot prove
  /// ABSENCE, so it must never become a mint-authorising virgin-absent answer.
  writeUnresolved,
}

@immutable
final class EnvelopeSnapshotContext {
  const EnvelopeSnapshotContext(this.identity, this.generation, this.trust);

  final PaymentEnvelopeIdentity identity;

  /// The EXACT guard generation this read observed.
  final int generation;

  final SnapshotTrust trust;

  PaymentActivityKey get activityKey => identity.activityKey;
}

enum FrozenEntryKind { inScope, foreignScope, unreadable }

/// One envelope entry, frozen at snapshot time.
@immutable
final class FrozenEntry {
  const FrozenEntry._({
    required this.index,
    required this.value,
    required this.lexeme,
    required this.attempt,
    required this.kind,
    required this.orderId,
    required this.violation,
  });

  static FrozenEntry inScope({
    required int index,
    required Object? value,
    required String lexeme,
    required PaymentAttempt attempt,
  }) => FrozenEntry._(
    index: index,
    value: value,
    lexeme: lexeme,
    attempt: attempt,
    kind: FrozenEntryKind.inScope,
    orderId: attempt.orderId,
    violation: null,
  );

  static FrozenEntry foreignScope({
    required int index,
    required Object? value,
    required String lexeme,
    required PaymentAttempt attempt,
  }) => FrozenEntry._(
    index: index,
    value: value,
    lexeme: lexeme,
    attempt: attempt,
    kind: FrozenEntryKind.foreignScope,
    orderId: attempt.orderId,
    violation: null,
  );

  static FrozenEntry unreadable({
    required int index,
    required Object? value,
    required String lexeme,
    required String? orderId,
    required String violation,
  }) => FrozenEntry._(
    index: index,
    value: value,
    lexeme: lexeme,
    attempt: null,
    kind: FrozenEntryKind.unreadable,
    orderId: orderId,
    violation: violation,
  );

  final int index;

  /// The DECODED entry, preserved by reference.
  final Object? value;

  /// The exact production encoding of [value] at snapshot time. An untouched
  /// entry must still encode to this after any mutation.
  final String lexeme;

  /// Non-null IFF [kind] is not [FrozenEntryKind.unreadable].
  final PaymentAttempt? attempt;

  final FrozenEntryKind kind;
  final String? orderId;
  final String? violation;
}

@immutable
sealed class SnapshotResult {
  const SnapshotResult();
  EnvelopeSnapshotContext get context;
  bool get isReadable => this is SnapshotReady;
}

@immutable
final class SnapshotReady extends SnapshotResult {
  const SnapshotReady({
    required this.context,
    required this.entries,
    required this.rawBytes,
  });

  @override
  final EnvelopeSnapshotContext context;

  final List<FrozenEntry> entries;

  /// The EXACT bytes this snapshot was classified from, retained so a failed
  /// write can be adjudicated as `verifiedOld` rather than `unknown`.
  final String rawBytes;
}

@immutable
final class SnapshotAbsent extends SnapshotResult {
  const SnapshotAbsent({required this.context});
  @override
  final EnvelopeSnapshotContext context;
}

@immutable
final class SnapshotPresentEmpty extends SnapshotResult {
  const SnapshotPresentEmpty({required this.context});
  @override
  final EnvelopeSnapshotContext context;
}

@immutable
final class SnapshotNotCanonical extends SnapshotResult {
  const SnapshotNotCanonical({required this.context, required this.violation});
  @override
  final EnvelopeSnapshotContext context;
  final String violation;
}

@immutable
final class SnapshotWrongCachedType extends SnapshotResult {
  const SnapshotWrongCachedType({
    required this.context,
    required this.observedTypeName,
  });
  @override
  final EnvelopeSnapshotContext context;
  final String observedTypeName;
}

@immutable
final class SnapshotUntrusted extends SnapshotResult {
  const SnapshotUntrusted({required this.context, required this.reason});
  @override
  final EnvelopeSnapshotContext context;
  final UntrustedReason reason;
}

@immutable
final class SnapshotReadFailed extends SnapshotResult {
  const SnapshotReadFailed({required this.context});
  @override
  final EnvelopeSnapshotContext context;
}

// ===========================================================================
// K3-B02 — the frozen subject
// ===========================================================================

@immutable
final class FrozenAttemptSubject {
  const FrozenAttemptSubject({
    required this.snapshot,
    required this.entryIndex,
    required this.entryValue,
    required this.parent,
    required this.binding,
    required this.activeBlock,
  });

  final SnapshotReady snapshot;
  final int entryIndex;
  final Object? entryValue;
  final PaymentAttempt parent;
  final ExactAttemptBinding binding;

  /// Non-null IFF a block decoded AND its status is active.
  final PaymentReplacementBlock? activeBlock;

  PaymentEnvelopeIdentity get identity => snapshot.context.identity;
  int get generation => snapshot.context.generation;
}

@immutable
sealed class SubjectSelection {
  const SubjectSelection();
}

@immutable
final class SubjectSelected extends SubjectSelection {
  const SubjectSelected(this.subject);
  final FrozenAttemptSubject subject;
}

@immutable
final class SubjectOrderMismatch extends SubjectSelection {
  const SubjectOrderMismatch(this.asked, this.snapshotHas);
  final CanonicalOrderId asked;
  final CanonicalOrderId snapshotHas;
}

@immutable
final class SubjectNotFound extends SubjectSelection {
  const SubjectNotFound(this.localOperationId);
  final String localOperationId;
}

@immutable
final class SubjectAmbiguous extends SubjectSelection {
  const SubjectAmbiguous(this.matches);
  final int matches;
}

@immutable
final class SubjectForeignSubject extends SubjectSelection {
  const SubjectForeignSubject(this.violation);
  final String violation;
}

@immutable
final class SubjectAliasedScope extends SubjectSelection {
  const SubjectAliasedScope(this.aliasIndex);
  final int aliasIndex;
}

@immutable
final class SubjectBlockingQuarantine extends SubjectSelection {
  const SubjectBlockingQuarantine(this.entryIndex, this.orderId);
  final int entryIndex;
  final String? orderId;
}

@immutable
final class SubjectBlockMalformed extends SubjectSelection {
  const SubjectBlockMalformed(this.rule, this.message);
  final String rule;
  final String message;
}

@immutable
final class SubjectBlockAbsent extends SubjectSelection {
  const SubjectBlockAbsent();
}

@immutable
final class SubjectBlockNotActive extends SubjectSelection {
  const SubjectBlockNotActive(this.observed);
  final BlockStatus observed;
}

@immutable
final class SubjectBlockPresent extends SubjectSelection {
  const SubjectBlockPresent(this.occurrence);
  final BlockOccurrence occurrence;
}

@immutable
final class SubjectIncidentDisagrees extends SubjectSelection {
  const SubjectIncidentDisagrees(this.rule, this.message);
  final String rule;
  final String message;
}

/// K3-B02 — the subject comes from the SNAPSHOT and nowhere else.
///
/// The load-bearing checks are NOT key-to-key comparisons: they compare the
/// authoritative identity against fields STORED ON DISK, which no caller
/// controls. The `key.orderId` guard is a cheap caller-pairing assertion and is
/// labelled as such.
SubjectSelection selectExactAttemptSubject({
  required SnapshotReady snapshot,
  required PaymentActivityKey key,
  required String localOperationId,
  required bool requireActiveReplacementBlock,
  PaymentFailClosedIncident? incident,
}) {
  final identity = snapshot.context.identity;

  // Caller-pairing guard (not the binding).
  if (key.orderId != identity.orderId) {
    return SubjectOrderMismatch(key.orderId, identity.orderId);
  }
  // The snapshot's own scope must be the money-safety scope. Two raw scopes
  // that sanitise to one storage key are NOT the same till.
  if (key.scope != identity.scope) {
    return const SubjectForeignSubject('activity key scope != snapshot scope');
  }

  // Exactly one in-scope entry for this operation. Source selects last-wins on
  // a duplicate operation id; the kernel refuses rather than inherit that.
  FrozenEntry? hit;
  var matches = 0;
  for (final e in snapshot.entries) {
    if (e.kind != FrozenEntryKind.inScope) continue;
    if (e.attempt!.localOperationId != localOperationId) continue;
    matches++;
    hit ??= e;
  }
  if (matches == 0) return SubjectNotFound(localOperationId);
  if (matches > 1) return SubjectAmbiguous(matches);
  final entry = hit!;
  final parent = entry.attempt!;

  // The DISK-DATA binding.
  if (parent.orderId != identity.orderId.value) {
    return const SubjectForeignSubject('order_id != authoritative order');
  }
  if (parent.identityKey != identity.orderId.identityKey) {
    return const SubjectForeignSubject('identity_key != derived identity');
  }
  if (parent.organizationId != identity.scope.organizationId ||
      parent.restaurantId != identity.scope.restaurantId ||
      parent.branchId != identity.scope.branchId ||
      parent.deviceId != identity.scope.deviceId) {
    return const SubjectForeignSubject('raw scope != authoritative raw scope');
  }

  // BLOCKING EVIDENCE — both halves of the shipped containment, not one:
  // a foreign-scope entry naming this order, AND an undecodable entry naming
  // this order or naming none at all.
  for (final e in snapshot.entries) {
    if (e.kind == FrozenEntryKind.foreignScope &&
        e.attempt!.orderId == identity.orderId.value) {
      return SubjectAliasedScope(e.index);
    }
    if (e.kind == FrozenEntryKind.unreadable &&
        (e.orderId == null || e.orderId == identity.orderId.value)) {
      return SubjectBlockingQuarantine(e.index, e.orderId);
    }
  }

  // The block, decoded from THIS SAME entry.
  final field = decodeReplacementBlockField(
    entry.value,
    PaymentAttemptParentFacts.of(parent),
    incidentOccurrence: incident?.occurrence,
    incidentTruth: incident?.serverTruth,
    incidentOperationId: incident?.operationId,
  );
  switch (field) {
    case BlockMalformed(:final rule, :final message):
      return SubjectBlockMalformed(rule, message);
    case BlockAbsent():
      if (requireActiveReplacementBlock) return const SubjectBlockAbsent();
      return SubjectSelected(
        FrozenAttemptSubject(
          snapshot: snapshot,
          entryIndex: entry.index,
          entryValue: entry.value,
          parent: parent,
          binding: ExactAttemptBinding.of(parent),
          activeBlock: null,
        ),
      );
    case BlockDecoded(:final block):
      if (!requireActiveReplacementBlock) {
        // A promotion CREATES the first block; one already stands.
        return SubjectBlockPresent(block.occurrence);
      }
      if (block.status != BlockStatus.active) {
        return SubjectBlockNotActive(block.status);
      }
      if (incident != null) {
        if (incident.occurrence != block.occurrence) {
          return const SubjectIncidentDisagrees(
            'X1',
            'incident occurrence != live block occurrence',
          );
        }
        if (incident.operationId != parent.localOperationId) {
          return const SubjectIncidentDisagrees(
            'X2',
            'incident operation != parent operation',
          );
        }
        if (incident.binding != ExactAttemptBinding.of(parent)) {
          return const SubjectIncidentDisagrees(
            'X3',
            'incident binding != parent binding',
          );
        }
        if (incident.serverTruth != block.serverTruth) {
          return const SubjectIncidentDisagrees(
            'X4',
            'incident truth != block truth',
          );
        }
        if (incident.state != IncidentState.active) {
          return const SubjectIncidentDisagrees('X5', 'incident is not active');
        }
      }
      return SubjectSelected(
        FrozenAttemptSubject(
          snapshot: snapshot,
          entryIndex: entry.index,
          entryValue: entry.value,
          parent: parent,
          binding: ExactAttemptBinding.of(parent),
          activeBlock: block,
        ),
      );
  }
}

// ===========================================================================
// K3-B05 — the explicit accepted candidate
// ===========================================================================

@immutable
sealed class AcceptedCandidateBuildResult {
  const AcceptedCandidateBuildResult();
}

@immutable
final class AcceptedCandidateBuilt extends AcceptedCandidateBuildResult {
  const AcceptedCandidateBuilt({
    required this.candidate,
    required this.entryValue,
    required this.block,
  });

  /// STRICT-DECODED: this object came back out of `PaymentAttempt.fromJson`.
  final PaymentAttempt candidate;

  /// The 27-key entry that will be written.
  final Map<String, Object?> entryValue;

  final PaymentReplacementBlock block;
}

@immutable
final class AcceptedCandidateInvalid extends AcceptedCandidateBuildResult {
  const AcceptedCandidateInvalid(this.rule, this.message);
  final String rule;
  final String message;
}

/// Builds the ACCEPTED successor of a CONTRADICTED terminal parent.
///
/// `PaymentAttempt.accepted()` may NOT be used here. It delegates to `_copy`,
/// whose null-coalescing retains the parent's `refusal` and `refusalMemoized`
/// (`payment_attempt.dart:538-539`), and the strict decoder rejects an accepted
/// record that carries either (`:972-974`, `:993-995`). The candidate is
/// therefore built explicitly, with those two facts written as an explicit
/// `null` and `false`, and then validated by the shipped decoder itself.
AcceptedCandidateBuildResult buildAcceptedCandidateFromContradictedParent({
  required PaymentAttempt parent,
  required AcceptedTruth freshTruth,
  required PaymentReplacementBlock resolvedBlock,
  required String at,
}) {
  if (parent.phase != PaymentAttemptPhase.refused &&
      parent.phase != PaymentAttemptPhase.settledElsewhere) {
    return const AcceptedCandidateInvalid(
      'B1',
      'parent is not a contradicted terminal',
    );
  }
  final sentAt = parent.sentAt;
  if (sentAt == null) {
    return const AcceptedCandidateInvalid(
      'B2',
      'parent carries no started-send marker',
    );
  }
  if (parent.autoEffectsReservedAt != null) {
    return const AcceptedCandidateInvalid(
      'B3',
      'contradicted parent carries an effect claim',
    );
  }
  if (!isCanonicalInstant(at)) {
    return const AcceptedCandidateInvalid(
      'B4a',
      'at is not a canonical instant',
    );
  }
  final atT = DateTime.parse(at);
  final createdT = DateTime.tryParse(parent.clientCreatedAt);
  final sentT = DateTime.tryParse(sentAt);
  if (createdT == null || sentT == null) {
    return const AcceptedCandidateInvalid(
      'B4b',
      'parent timestamps unparseable',
    );
  }
  if (atT.isBefore(createdT)) {
    return const AcceptedCandidateInvalid('B4c', 'at precedes creation');
  }
  if (atT.isBefore(sentT)) {
    return const AcceptedCandidateInvalid('B4d', 'at precedes sent_at');
  }
  if (freshTruth.resolution.method.wire != parent.tenderType) {
    return const AcceptedCandidateInvalid(
      'B5',
      'resolution tender != frozen tender',
    );
  }
  if (resolvedBlock.status != BlockStatus.resolved) {
    return const AcceptedCandidateInvalid('B6a', 'block is not resolved');
  }
  if (resolvedBlock.contradictedOperationId != parent.localOperationId) {
    return const AcceptedCandidateInvalid(
      'B6b',
      'block names another operation',
    );
  }
  if (resolvedBlock.contradictedPhase != parent.phase) {
    return const AcceptedCandidateInvalid('B6c', 'block phase != parent phase');
  }

  // The COMPLETE 26-key map, explicitly. Every frozen field is copied verbatim;
  // the refusal facts are written as an explicit `null` / `false` because the
  // record's `toJson` emits all 26 keys unconditionally and the decoder
  // requires `refusal_memoized` to be a non-null bool (`:873-876`).
  final candidateMap = <String, Object?>{
    'local_operation_id': parent.localOperationId,
    'target_id': parent.targetId,
    'client_created_at': parent.clientCreatedAt,
    'identity_key': parent.identityKey,
    'order_id': parent.orderId,
    'order_number': parent.orderNumber,
    'expected_revision': parent.expectedRevision,
    'tender_type': parent.tenderType,
    'amount_minor': parent.amountMinor,
    'amount_tendered_minor': parent.amountTenderedMinor,
    'currency_code': parent.currencyCode,
    'organization_id': parent.organizationId,
    'restaurant_id': parent.restaurantId,
    'branch_id': parent.branchId,
    'device_id': parent.deviceId,
    'employee_profile_id': parent.employeeProfileId,
    'phase': PaymentAttemptPhase.accepted.wire,
    'last_outcome': PaymentAttemptLastOutcome.none.wire,
    'sent_at': sentAt,
    'resolved_at': at,
    'resolution': freshTruth.resolution.toJson(),
    'refusal': null,
    'refusal_memoized': false,
    'auto_effects_reserved_at': at,
    'supersedes': parent.supersedes,
    'may_have_executed': true,
  };

  // VALIDATE THE WHOLE CANDIDATE through the shipped strict decoder.
  final PaymentAttempt candidate;
  try {
    candidate = PaymentAttempt.fromJson(candidateMap);
  } on FormatException catch (e) {
    return AcceptedCandidateInvalid('B8', 'candidate rejected: ${e.message}');
  }

  // Re-validate the block AGAINST THE FINISHED CANDIDATE, so the resolved-form
  // rules are evaluated with an accepted parent that has no refusal facts.
  final entry = <String, Object?>{
    ...candidateMap,
    kReplacementBlockKey: resolvedBlock.toJson(),
  };
  final field = decodeReplacementBlockField(
    entry,
    PaymentAttemptParentFacts.of(candidate),
  );
  if (field is BlockMalformed) {
    return AcceptedCandidateInvalid('B9', '${field.rule}: ${field.message}');
  }
  if (field is! BlockDecoded || field.block.status != BlockStatus.resolved) {
    return const AcceptedCandidateInvalid(
      'B9',
      'block did not survive re-decode',
    );
  }

  return AcceptedCandidateBuilt(
    candidate: candidate,
    entryValue: entry,
    block: field.block,
  );
}

// ===========================================================================
// Result families for the two incident callables
// ===========================================================================

@immutable
sealed class IncidentResolutionResult {
  const IncidentResolutionResult();
  PaymentSafetyRegistry get registry;
}

@immutable
final class IncidentResolvedApplied extends IncidentResolutionResult {
  const IncidentResolvedApplied({
    required this.registry,
    required this.acceptedParent,
    required this.resolvedOccurrence,
    required this.block,
    required this.effectsArmed,
  });
  @override
  final PaymentSafetyRegistry registry;
  final PaymentAttempt acceptedParent;
  final BlockOccurrence resolvedOccurrence;
  final PaymentReplacementBlock block;
  final bool effectsArmed;
}

@immutable
final class IncidentResolutionRefusedEvidence extends IncidentResolutionResult {
  const IncidentResolutionRefusedEvidence(this.registry, this.offered);
  @override
  final PaymentSafetyRegistry registry;
  final ServerTruth offered;
}

@immutable
final class IncidentResolutionRefusedOccurrence
    extends IncidentResolutionResult {
  const IncidentResolutionRefusedOccurrence(
    this.registry,
    this.expected,
    this.offered,
  );
  @override
  final PaymentSafetyRegistry registry;
  final BlockOccurrence expected;
  final BlockOccurrence? offered;
}

@immutable
final class IncidentResolutionRefusedContradictoryTruth
    extends IncidentResolutionResult {
  const IncidentResolutionRefusedContradictoryTruth(
    this.registry,
    this.recorded,
    this.offered,
  );
  @override
  final PaymentSafetyRegistry registry;
  final AcceptedTruth recorded;
  final AcceptedTruth offered;
}

@immutable
final class IncidentResolutionWriteFailed extends IncidentResolutionResult {
  const IncidentResolutionWriteFailed(this.registry, this.knowledge);
  @override
  final PaymentSafetyRegistry registry;
  final DurabilityKnowledge knowledge;
}

@immutable
final class IncidentResolutionAuthorityLapsed extends IncidentResolutionResult {
  const IncidentResolutionAuthorityLapsed(this.registry);
  @override
  final PaymentSafetyRegistry registry;
}

@immutable
final class IncidentResolutionSnapshotUnusable
    extends IncidentResolutionResult {
  const IncidentResolutionSnapshotUnusable(this.registry, this.result);
  @override
  final PaymentSafetyRegistry registry;
  final SnapshotResult result;
}

@immutable
final class IncidentResolutionSubjectUnusable extends IncidentResolutionResult {
  const IncidentResolutionSubjectUnusable(this.registry, this.selection);
  @override
  final PaymentSafetyRegistry registry;
  final SubjectSelection selection;
}

@immutable
final class IncidentResolutionOwnerAbsent extends IncidentResolutionResult {
  const IncidentResolutionOwnerAbsent(this.registry);
  @override
  final PaymentSafetyRegistry registry;
}

@immutable
final class IncidentResolutionOwnerMismatch extends IncidentResolutionResult {
  const IncidentResolutionOwnerMismatch(this.registry, this.reason);
  @override
  final PaymentSafetyRegistry registry;
  final RegistryRefusalReason reason;
}

@immutable
final class IncidentResolutionGenerationRaced extends IncidentResolutionResult {
  const IncidentResolutionGenerationRaced(
    this.registry,
    this.expected,
    this.observed,
  );
  @override
  final PaymentSafetyRegistry registry;
  final int expected;
  final int observed;
}

@immutable
final class IncidentResolutionCandidateInvalid
    extends IncidentResolutionResult {
  const IncidentResolutionCandidateInvalid(
    this.registry,
    this.rule,
    this.message,
  );
  @override
  final PaymentSafetyRegistry registry;
  final String rule;
  final String message;
}

@immutable
final class IncidentResolutionTenderMismatch extends IncidentResolutionResult {
  const IncidentResolutionTenderMismatch(
    this.registry,
    this.offered,
    this.frozen,
  );
  @override
  final PaymentSafetyRegistry registry;
  final String offered;
  final String frozen;
}

@immutable
sealed class IncidentPromotionResult {
  const IncidentPromotionResult();
  PaymentSafetyRegistry get registry;
}

@immutable
final class IncidentPromoted extends IncidentPromotionResult {
  const IncidentPromoted(this.registry, this.incident, this.parent, this.block);
  @override
  final PaymentSafetyRegistry registry;
  final PaymentFailClosedIncident incident;
  final PaymentAttempt parent;
  final PaymentReplacementBlock block;
}

@immutable
final class IncidentPromotionAuthorityLapsed extends IncidentPromotionResult {
  const IncidentPromotionAuthorityLapsed(this.registry);
  @override
  final PaymentSafetyRegistry registry;
}

@immutable
final class IncidentPromotionSnapshotUnusable extends IncidentPromotionResult {
  const IncidentPromotionSnapshotUnusable(this.registry, this.result);
  @override
  final PaymentSafetyRegistry registry;
  final SnapshotResult result;
}

@immutable
final class IncidentPromotionSubjectUnusable extends IncidentPromotionResult {
  const IncidentPromotionSubjectUnusable(this.registry, this.selection);
  @override
  final PaymentSafetyRegistry registry;
  final SubjectSelection selection;
}

@immutable
final class IncidentPromotionOwnerMismatch extends IncidentPromotionResult {
  const IncidentPromotionOwnerMismatch(this.registry, this.reason);
  @override
  final PaymentSafetyRegistry registry;
  final RegistryRefusalReason reason;
}

@immutable
final class IncidentPromotionGenerationRaced extends IncidentPromotionResult {
  const IncidentPromotionGenerationRaced(
    this.registry,
    this.expected,
    this.observed,
  );
  @override
  final PaymentSafetyRegistry registry;
  final int expected;
  final int observed;
}

@immutable
final class IncidentPromotionNotDurable extends IncidentPromotionResult {
  const IncidentPromotionNotDurable(this.registry, this.knowledge);
  @override
  final PaymentSafetyRegistry registry;
  final DurabilityKnowledge knowledge;
}

@immutable
final class IncidentPromotionCandidateInvalid extends IncidentPromotionResult {
  const IncidentPromotionCandidateInvalid(this.registry, this.violation);
  @override
  final PaymentSafetyRegistry registry;
  final String violation;
}

// ===========================================================================
// Hydration — one answer combining envelope, quarantine, block, incident, owner
// ===========================================================================

@immutable
sealed class HydratedSafetyState {
  const HydratedSafetyState();

  /// 1..6 — which precedence rung decided.
  int get rung;
}

@immutable
final class SafetyEnvelopeFailClosed extends HydratedSafetyState {
  const SafetyEnvelopeFailClosed(this.result);
  final SnapshotResult result;
  @override
  int get rung => 1;
}

@immutable
final class SafetyRecordQuarantined extends HydratedSafetyState {
  const SafetyRecordQuarantined(this.entryIndex, this.orderId);
  final int entryIndex;
  final String? orderId;
  @override
  int get rung => 2;
}

@immutable
final class SafetyDurableBlocked extends HydratedSafetyState {
  const SafetyDurableBlocked(this.occurrence, this.block, this.parent);
  final BlockOccurrence occurrence;
  final PaymentReplacementBlock block;

  /// The record the block sits on, carried so a caller that must REFUSE a mint
  /// can still publish the accepted-class money truth the block holds without
  /// a second store read. It is the CONTRADICTED terminal record, so its own
  /// `payment` is null and the payment must be built from the block's truth.
  final PaymentAttempt parent;

  @override
  int get rung => 3;
}

@immutable
final class SafetyIncident extends HydratedSafetyState {
  const SafetyIncident(this.incident);
  final PaymentFailClosedIncident incident;
  @override
  int get rung => 4;
}

@immutable
final class SafetyOwnerFailClosed extends HydratedSafetyState {
  const SafetyOwnerFailClosed(this.reason);
  final IncidentReason reason;
  @override
  int get rung => 5;
}

@immutable
final class SafetyClear extends HydratedSafetyState {
  const SafetyClear();
  @override
  int get rung => 6;
}

/// Accepts EVERY snapshot outcome, including the failures.
HydratedSafetyState hydratePaymentSafety({
  required SnapshotResult snapshotResult,
  required PaymentSafetyRegistry registry,
}) {
  final identity = snapshotResult.context.identity;
  final key = identity.activityKey;
  final orderId = identity.orderId;

  // Rung 1 — the envelope itself is not usable.
  switch (snapshotResult) {
    case SnapshotNotCanonical():
    case SnapshotWrongCachedType():
    case SnapshotUntrusted():
    case SnapshotReadFailed():
    case SnapshotPresentEmpty():
      return SafetyEnvelopeFailClosed(snapshotResult);
    case SnapshotAbsent():
    case SnapshotReady():
      break;
  }

  final ready = snapshotResult is SnapshotReady ? snapshotResult : null;

  // Rung 2 — a quarantine blocking THIS order. A quarantine whose order id is
  // null blocks every order: the shipped rule, not a new one.
  if (ready != null) {
    for (final e in ready.entries) {
      if (e.kind == FrozenEntryKind.inScope) continue;
      final blocks = e.orderId == null || e.orderId == orderId.value;
      if (blocks) return SafetyRecordQuarantined(e.index, e.orderId);
    }
  }

  // Rung 3 — a DURABLE active replacement block on this order.
  if (ready != null) {
    for (final e in ready.entries) {
      if (e.kind != FrozenEntryKind.inScope) continue;
      if (e.attempt!.orderId != orderId.value) continue;
      final f = decodeReplacementBlockField(
        e.value,
        PaymentAttemptParentFacts.of(e.attempt!),
      );
      if (f is BlockMalformed) {
        return SafetyRecordQuarantined(e.index, e.attempt!.orderId);
      }
      if (f is BlockDecoded && f.block.status == BlockStatus.active) {
        return SafetyDurableBlocked(f.block.occurrence, f.block, e.attempt!);
      }
    }
  }

  // Rung 4 — an isolate incident.
  final incident = registry.incidentOf(key);
  if (incident != null && incident.state == IncidentState.active) {
    return SafetyIncident(incident);
  }

  // Rung 5 — an owner whose handoff is fail-closed.
  final owner = registry.ownerOf(key);
  final handoff = owner?.handoff;
  if (handoff is OwnerHandoffFailClosed) {
    return SafetyOwnerFailClosed(handoff.reason);
  }

  // Rung 6 — clear. A `SnapshotAbsent` reaches here only because rung 1 already
  // caught every UNPROVEN absence.
  return const SafetyClear();
}

/// The safety posture, total over the six rungs.
SafetyPosture postureOf(HydratedSafetyState s) => switch (s) {
  SafetyClear() => const PostureClear(),
  SafetyEnvelopeFailClosed() => const PostureFailClosed(
    IncidentReason.storageUntrusted,
  ),
  SafetyRecordQuarantined() => const PostureFailClosed(
    IncidentReason.storageUntrusted,
  ),
  SafetyDurableBlocked(:final block) => PostureFailClosed(block.reason),
  SafetyIncident(:final incident) => PostureFailClosed(incident.reason),
  SafetyOwnerFailClosed(:final reason) => PostureFailClosed(reason),
};

/// Non-null IFF an ACTIVE incident OR an ACTIVE durable block stands whose
/// recorded truth is accepted-class. This is what OD-1 reads, so BOTH carriers
/// must be covered.
AcceptedTruth? acceptedIncidentTruthOf(HydratedSafetyState s) => switch (s) {
  SafetyIncident(:final incident) =>
    incident.state == IncidentState.active ? incident.acceptedTruth : null,
  SafetyDurableBlocked(:final block) =>
    block.status == BlockStatus.active
        ? (block.serverTruth is AcceptedTruth
              ? block.serverTruth as AcceptedTruth
              : null)
        : null,
  SafetyClear() => null,
  SafetyEnvelopeFailClosed() => null,
  SafetyRecordQuarantined() => null,
  SafetyOwnerFailClosed() => null,
};

/// OWNER OPTION B — what a caller may allocate, consulted BEFORE any
/// `local_operation_id` or provisional target is minted.
NewIdentityEligibility eligibilityOfSafety(HydratedSafetyState s) =>
    switch (s) {
      SafetyClear() => NewIdentityEligibility.freshMintAllowed,
      SafetyEnvelopeFailClosed() => NewIdentityEligibility.forbidden,
      SafetyRecordQuarantined() => NewIdentityEligibility.forbidden,
      SafetyDurableBlocked() => NewIdentityEligibility.forbidden,
      SafetyIncident() => NewIdentityEligibility.forbidden,
      SafetyOwnerFailClosed() => NewIdentityEligibility.forbidden,
    };
