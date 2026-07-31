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

/// Durable per-round automatic-print claims.
abstract class PosRoundPrintClaimStore {
  /// The claim for [key], or null when this round has never been claimed.
  /// Never throws — an unreadable value reads as "no claim", which fails toward
  /// printing rather than toward silently withholding a kitchen ticket.
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

  Map<String, Object?> _claims() {
    final raw = _prefs.getString(_storageKey(scopeKey));
    if (raw == null || raw.isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, Object?>{};
      if ((decoded['version'] as num?)?.toInt() != schemaVersion) {
        return const <String, Object?>{};
      }
      final claims = decoded['claims'];
      if (claims is! Map) return const <String, Object?>{};
      return claims.cast<String, Object?>();
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  @override
  PosRoundPrintClaimState? claimOf(String key) {
    final wire = _claims()[key];
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
    final raw = _prefs.getString(_storageKey(scopeKey));
    if (raw == null || raw.isEmpty) return 0;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map &&
          (decoded['version'] as num?)?.toInt() == schemaVersion &&
          decoded['claims'] is Map) {
        return 0;
      }
    } catch (_) {
      // falls through
    }
    // The whole envelope is unreadable: every claim it held is unknown, which is
    // exactly the state an operator needs to be told about — a duplicate ticket
    // is now possible for any round it covered.
    return 1;
  }

  @override
  Future<void> record(String key, PosRoundPrintClaimState state) async {
    final next = <String, Object?>{..._claims(), key: state.name};
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
