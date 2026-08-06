import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_storage_health.dart';
import 'sync_cursor_store.dart' show PosPersistenceException;

/// MONEY-DURABLE-ADDITIONS-003C: the durable "this device has already sent the
/// automatic kitchen ticket for that round" claim.
///
/// WHY IT EXISTS. `PosAutoKitchenPrintGuard` keys on the right identity —
/// `orderId|round:roundId`, a server-assigned round, not a guess — but holds it
/// in two plain in-memory collections on a Provider. Its own docstring says
/// "Session-scoped and best-effort — NOT crash-proof". So when a process dies
/// after an amendment was applied and the client replays the operation on
/// restart, `app.add_order_items` correctly returns the SAME round, the
/// automatic print fires again, and the kitchen gets a second ticket for food it
/// is already making. The claim has to be as durable as the round it names.
///
/// SCOPE. This claim governs AUTOMATIC printing only. A deliberate operator
/// reprint never consults it — a cashier who asks for another copy must get one,
/// and conflating "we already auto-printed" with "you may not reprint" would
/// break a workflow people rely on when paper jams.
enum PosRoundPrintClaimState {
  /// This device has committed to printing the round but has not yet been told
  /// the bytes were accepted. Treated as ALREADY CLAIMED: after a crash in this
  /// window the honest answer is "a ticket may already be at the printer", and
  /// printing again to be sure is exactly the duplicate this store prevents.
  claimed,

  /// The transport accepted the bytes. Note the deliberate limit of that claim:
  /// the platform confirms bytes SENT, never paper produced (PRINT-STABILITY-001),
  /// and this store does not pretend otherwise.
  sent,

  /// The send failed. The round is RELEASED so a later legitimate automatic
  /// retry can run — a failed print must not permanently suppress the ticket.
  failed,
}

/// [POS-OFFLINE-OPERATIONS-002] C9 — the LOCAL kitchen dispatch identity of ONE
/// offline direct-print order: the durable claim key the POS commits BEFORE the
/// cart clears, so a crash/restart can never re-print (or silently lose) the
/// ticket for an order the server has not acknowledged yet.
///
/// Collision-safe by construction: `deviceId` + `localOperationId` are the
/// globally-unique client operation identity (DECISION D-022 — the same pair
/// the server's idempotency ledger keys on), and the `local:v1:` prefix can
/// never collide with a server dispatch UUID, an `orderId` guard key, an
/// `orderId|round:<roundId>` addition key, or an `orderId|initial` key — no
/// UUID and no order-code contains a `:` in these positions.
String posLocalKitchenDispatchClaimKey({
  required String deviceId,
  required String localOperationId,
}) => 'local:v1:$deviceId:$localOperationId:kitchen';

/// [POS-OFFLINE-OPERATIONS-002] C9 — the ORDER-scoped claim for the INITIAL
/// kitchen ticket, recorded IN ADDITION to the local dispatch claim once the
/// offline direct-print ticket is confirmed sent. Mirrors the round-claim
/// naming (`orderId|round:<roundId>`, see `posAdditionKitchenPrintGuardKey`)
/// and the server dispatch ledger's own `initial:<orderId>` idempotency key,
/// so any FUTURE surface keyed by the server order (the client-minted order id
/// is stable across sync — the server stores it verbatim) can see the ticket
/// already exists and never re-print it. Today no production server-driven
/// reprint path exists for `direct_print` (the spool dispatch drain is a
/// dormant seam); this claim is the defence in depth for when one does.
String posInitialKitchenPrintClaimKey(String orderId) => '$orderId|initial';

/// Durable per-round automatic-print claims.
abstract class PosRoundPrintClaimStore {
  /// The claim for [key], or null when this round has never been claimed.
  ///
  /// Never throws. MONEY-CODEX-FINAL-CORRECTIONS-004 (F8): "unreadable" is NOT
  /// "never claimed". This used to read an undecodable envelope as an empty
  /// one, so every claim it held silently reverted to unclaimed and the
  /// automatic send ran again — the duplicate kitchen ticket this store exists
  /// to prevent. An envelope we cannot interpret now reads as
  /// [PosRoundPrintClaimState.claimed] for every key, which withholds the
  /// AUTOMATIC ticket only; a deliberate operator reprint never consults this.
  PosRoundPrintClaimState? claimOf(String key);

  /// Records [state] for [key].
  ///
  /// THROWS [PosPersistenceException] when the write does not stick (003B): a
  /// claim that was not stored cannot prevent tomorrow's duplicate, and the
  /// caller must be able to tell the difference before it commits to printing.
  Future<void> record(String key, PosRoundPrintClaimState state);
}

/// A `shared_preferences`-backed [PosRoundPrintClaimStore]: one schema-versioned
/// JSON envelope `{version, claims:{key: state}}` per device scope.
class SharedPrefsRoundPrintClaimStore
    implements PosRoundPrintClaimStore, PosDurableStoreHealth {
  SharedPrefsRoundPrintClaimStore(this._prefs, {String keyPrefix = _prefix})
    : _keyPrefix = keyPrefix;

  final SharedPreferences _prefs;
  final String _keyPrefix;

  static const String _prefix = 'restoflow.pos.round_print_claims.v1';

  /// Bump ONLY on an incompatible envelope shape change.
  static const int schemaVersion = 1;

  bool _degraded = false;

  @override
  bool get isDegraded => _degraded;

  String _storageKey(String scopeKey) {
    final safe = scopeKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? _keyPrefix : '$_keyPrefix.$safe';
  }

  /// The scope this store reads and writes under. Set once by the owning
  /// provider from the live session's device id, so one device never reads
  /// another's claims (the same RF-114 scope binding the outbox uses).
  String scopeKey = '';

  /// The claims of the CURRENT envelope, or null when this build cannot
  /// interpret it at all.
  ///
  /// F8: null and `{}` are different answers and the caller must not conflate
  /// them. `{}` means "this device has never claimed a round" — the ordinary
  /// state of a fresh till, which must keep printing. null means "there are
  /// claims here and we cannot read them", which must not.
  Map<String, Object?>? _claimsOrUnreadable() {
    final raw = _prefs.getString(_storageKey(scopeKey));
    if (raw == null || raw.isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if ((decoded['version'] as num?)?.toInt() != schemaVersion) return null;
      final claims = decoded['claims'];
      if (claims is! Map) return null;
      return claims.cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }

  @override
  PosRoundPrintClaimState? claimOf(String key) {
    final claims = _claimsOrUnreadable();
    if (claims == null) {
      // F8: THE ENVELOPE IS UNREADABLE. Damaged JSON, the wrong shape, or a
      // schema version from a newer build — in every case rounds may have been
      // claimed here and we cannot see which. Reading that as "never claimed"
      // released every one of them and printed the kitchen a second ticket for
      // food it was already making.
      //
      // The safe reading is the one already applied to an unrecognised state
      // below: assume some build committed to printing it. Not printing is
      // recoverable — the operator reprints on demand, and that path never
      // consults this guard. A duplicate ticket is not; the food is made twice.
      return PosRoundPrintClaimState.claimed;
    }
    final wire = claims[key];
    if (wire is! String) return null;
    for (final s in PosRoundPrintClaimState.values) {
      if (s.name == wire) return s;
    }
    // A state written by a NEWER build. Treat it as claimed rather than as
    // absent: an unrecognised claim still says "some build already committed to
    // printing this round", and the safe reading of that is not to print again.
    return PosRoundPrintClaimState.claimed;
  }

  @override
  int unreadableRecordCount(String scopeKey) {
    var count = 0;
    final raw = _prefs.getString(_storageKey(scopeKey));
    if (raw != null && raw.isNotEmpty) {
      var readable = false;
      try {
        final decoded = jsonDecode(raw);
        readable =
            decoded is Map &&
            (decoded['version'] as num?)?.toInt() == schemaVersion &&
            decoded['claims'] is Map;
      } catch (_) {
        readable = false;
      }
      // The whole envelope is unreadable: every claim it held is unknown, which
      // is exactly the state an operator needs to be told about — automatic
      // kitchen printing is now suppressed for every round it covered.
      if (!readable) count++;
    }
    // F8: and the ones already SET ASIDE still count. Preserving the bytes is
    // not resolving them; a till holding claims it cannot read must not look
    // healthy again just because a later round wrote a fresh envelope over the
    // top of the damaged one.
    for (var slot = 0; slot < _maxPreservedEnvelopes; slot++) {
      if ((_prefs.getString(_preservedKey(scopeKey, slot)) ?? '').isNotEmpty) {
        count++;
      }
    }
    return count;
  }

  /// Sidecar keys holding envelopes this build could not interpret at all.
  /// Same convention as the 003B draft-recovery store.
  static const int _maxPreservedEnvelopes = 5;

  String _preservedKey(String scopeKey, int slot) {
    final base = '${_storageKey(scopeKey)}.unreadable';
    return slot == 0 ? base : '$base.${slot + 1}';
  }

  /// F8: copies an envelope this build cannot interpret to a sidecar key BEFORE
  /// the primary key is overwritten.
  ///
  /// [record] rebuilds the envelope from `_claimsOrUnreadable()`, so writing a
  /// new claim over an unreadable one would DESTROY the only record of what an
  /// earlier or newer build already printed. Fails CLOSED, like the outbox and
  /// the recovery store: when the copy cannot be made, [record] throws rather
  /// than overwriting the original.
  Future<void> _preserveUnreadableEnvelope() async {
    final raw = _prefs.getString(_storageKey(scopeKey));
    if (raw == null || raw.isEmpty) return;
    // Interpretable — there is nothing to set aside.
    if (_claimsOrUnreadable() != null) return;
    for (var slot = 0; slot < _maxPreservedEnvelopes; slot++) {
      final key = _preservedKey(scopeKey, slot);
      final existing = _prefs.getString(key);
      if (existing == raw) return; // already preserved (idempotent)
      if (existing != null && existing.isNotEmpty) continue;
      if (await _prefs.setString(key, raw)) return;
      _degraded = true;
      throw const PosPersistenceException(
        'an unreadable kitchen print-claim envelope could not be set aside, so '
        'it was not overwritten',
      );
    }
    _degraded = true;
    throw const PosPersistenceException(
      'too many unreadable kitchen print-claim envelopes are already being '
      'held; refusing to overwrite another',
    );
  }

  @override
  Future<void> record(String key, PosRoundPrintClaimState state) async {
    // F8: set the damaged bytes aside BEFORE replacing them, and start from an
    // empty map rather than carrying nothing forward silently.
    await _preserveUnreadableEnvelope();
    final existing = _claimsOrUnreadable() ?? const <String, Object?>{};
    final next = <String, Object?>{...existing, key: state.name};
    final encoded = jsonEncode(<String, Object?>{
      'version': schemaVersion,
      'claims': next,
    });
    final ok = await _prefs.setString(_storageKey(scopeKey), encoded);
    if (!ok) {
      _degraded = true;
      throw const PosPersistenceException(
        'the kitchen round print claim could not be persisted',
      );
    }
  }
}

/// An in-memory [PosRoundPrintClaimStore] (demo mode / tests). Session-only, and
/// honest about it: it restores exactly the pre-003C behaviour.
class InMemoryRoundPrintClaimStore implements PosRoundPrintClaimStore {
  final Map<String, PosRoundPrintClaimState> _claims = {};

  @override
  PosRoundPrintClaimState? claimOf(String key) => _claims[key];

  @override
  Future<void> record(String key, PosRoundPrintClaimState state) async {
    _claims[key] = state;
  }
}
