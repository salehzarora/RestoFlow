/// POS-CASH-DRAWER-AUTO-OPEN — the DURABLE at-most-once cash-drawer claim
/// store.
///
/// A drawer kick is a cash-control HARDWARE side effect: opening the drawer
/// twice for one payment hands an attacker (or an honest race) an open cash
/// box, while opening it zero times merely makes the cashier press the manual
/// release. Memory-only dedupe is therefore NOT sufficient — a provider
/// rebuild, a hot restart, or a crash between payment and kick would forget
/// the claim and re-pulse on the next code path that sees the same payment.
/// This store persists the claim in `shared_preferences` BEFORE any byte is
/// handed to a transport (claim-before-send), the same at-most-once stance
/// RF-074's [CashDrawerKickDispatcher] takes for the spool path: a dispatch
/// failure is never retried, a crash after the claim is a MISSED open by
/// design, and no path ever removes or replays a claim.
///
/// The kitchen `round_print_claim_store` is deliberately NOT reused: it is
/// kitchen-domain-specific (round keys, print-worker ownership semantics).
/// This is the house `shared_preferences` JSON-envelope idiom instead (see
/// `operational_snapshot_store.dart` / the durable outbox).
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_printing/restoflow_printing.dart'
    show CashDrawerKickDispatcher;
import 'package:shared_preferences/shared_preferences.dart';

/// The storage key for one device's drawer-kick claims.
///
/// Keyed per DEVICE (the drawer is per-till hardware, and the payment id it
/// claims is globally unique anyway); the segment is sanitized here so the key
/// is provably preferences-safe on its own terms.
String posCashDrawerClaimsStorageKey(String deviceSegment) {
  final safe = deviceSegment.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return 'restoflow.pos.cash_drawer_claims.v1.$safe';
}

/// The envelope schema version. Bump ONLY on an incompatible shape change; an
/// unrecognised version REFUSES to kick rather than guessing (see
/// [PosCashDrawerClaimResult.persistFailed]).
const int kPosCashDrawerClaimsSchemaVersion = 1;

/// The maximum retained claims per device. Newest-first, pruned on write: a
/// VERY RECENT payment can never be evicted by pruning, because 200 NEWER
/// payments would have to be recorded on this till first — by which point the
/// evicted payment is far outside any window in which its kick could still be
/// re-attempted.
const int kPosCashDrawerClaimsLimit = 200;

/// The typed outcome of [PosCashDrawerClaimStore.claim].
enum PosCashDrawerClaimResult {
  /// The claim was newly and DURABLY persisted — the caller may kick.
  claimed,

  /// This payment was already claimed (here or in a previous process) — the
  /// caller must NOT kick again.
  duplicate,

  /// The claim could not be durably persisted (prefs unavailable, `setString`
  /// returned false or threw, or the stored envelope is unreadable). The
  /// caller must NOT kick: without a durable claim we cannot prove the pulse
  /// will happen at most once, and a MISSED open (cashier uses the manual
  /// drawer release) is strictly safer than a possible DOUBLE open.
  persistFailed,
}

/// Records "this payment has opened the drawer" durably, at most once.
class PosCashDrawerClaimStore {
  PosCashDrawerClaimStore({Future<SharedPreferences> Function()? prefs})
    : _resolvePrefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _resolvePrefs;

  /// PR #205 review F1: the tail of the claim-operation SERIAL CHAIN. Every
  /// [claim] runs strictly after the previous one has settled, so the
  /// read-check-prune-write transaction below can never interleave with a
  /// sibling — the at-most-once invariant is upheld by THIS primitive, not by
  /// the payment sheet's in-flight latch or any other distant UI discipline.
  /// (Two same-id racers would otherwise both observe "not claimed"; two
  /// different-id racers would lose one update to last-writer-wins.)
  ///
  /// Poison-proofing: the stored tail swallows both values and errors, so one
  /// failed operation can never wedge the chain — and the public [claim]
  /// wrapper maps any unexpected throw to [persistFailed] (fail-safe: no
  /// kick), preserving the "claim never throws" contract.
  Future<void> _serial = Future<void>.value();

  /// The claim id for [paymentId] — the SAME deterministic
  /// `drawer:<paymentId>` identity RF-074's spool dispatcher uses (D-022), so
  /// the two mechanisms could never claim one payment under two names.
  static String claimIdFor(String paymentId) =>
      CashDrawerKickDispatcher.localOperationIdFor(paymentId);

  /// Claims [paymentId] for [deviceSegment]'s drawer.
  ///
  /// CLAIM-BEFORE-SEND: returns [PosCashDrawerClaimResult.claimed] only after
  /// the envelope containing the new claim has been written AND the write
  /// reported success. Every doubt — unreadable envelope, refused write,
  /// thrown write — answers [PosCashDrawerClaimResult.persistFailed], meaning
  /// DO NOT KICK. A claim is never removed and never retried: a crash after
  /// the claim but before the pulse is a missed open by design (RF-074: "a
  /// duplicate open is worse than a missed retry").
  ///
  /// Serialized per store instance (see [_serial]): concurrent calls for the
  /// SAME payment resolve as exactly one [PosCashDrawerClaimResult.claimed]
  /// and the rest [PosCashDrawerClaimResult.duplicate]; concurrent calls for
  /// DIFFERENT payments all persist (no lost update).
  Future<PosCashDrawerClaimResult> claim({
    required String deviceSegment,
    required String paymentId,
  }) {
    final run = _serial.then(
      (_) =>
          _claimSerialized(deviceSegment: deviceSegment, paymentId: paymentId),
    );
    // The chain tail must survive ANY outcome of `run` — a poisoned tail
    // would silently disable the drawer forever. Errors are re-surfaced to
    // the caller through `run` itself (then mapped below), never the tail.
    _serial = run.then((_) {}, onError: (_) {});
    return run.then(
      (result) => result,
      onError: (_) => PosCashDrawerClaimResult.persistFailed,
    );
  }

  Future<PosCashDrawerClaimResult> _claimSerialized({
    required String deviceSegment,
    required String paymentId,
  }) async {
    final SharedPreferences prefs;
    try {
      prefs = await _resolvePrefs();
    } catch (_) {
      return PosCashDrawerClaimResult.persistFailed;
    }
    final key = posCashDrawerClaimsStorageKey(deviceSegment);
    final claimId = claimIdFor(paymentId);

    List<Object?> claims;
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      claims = <Object?>[];
    } else {
      // An UNREADABLE envelope refuses the kick instead of being replaced:
      // rewriting it would destroy the very dedupe history that proves a
      // payment did not already open the drawer. The bytes stay verbatim
      // (evidence, and a build that understands them can still read them);
      // this till simply falls back to the manual drawer release.
      final Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return PosCashDrawerClaimResult.persistFailed;
      }
      if (decoded is! Map ||
          (decoded['v'] as num?)?.toInt() !=
              kPosCashDrawerClaimsSchemaVersion ||
          decoded['claims'] is! List) {
        return PosCashDrawerClaimResult.persistFailed;
      }
      claims = List<Object?>.of(decoded['claims'] as List);
      for (final c in claims) {
        if (c is Map && c['id'] == claimId) {
          return PosCashDrawerClaimResult.duplicate;
        }
      }
    }

    // Newest first, bounded: prune beyond the cap so the envelope can never
    // grow without bound (see [kPosCashDrawerClaimsLimit] for why pruning can
    // never evict a claim that still matters).
    claims.insert(0, <String, Object?>{
      'id': claimId,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    if (claims.length > kPosCashDrawerClaimsLimit) {
      claims = claims.sublist(0, kPosCashDrawerClaimsLimit);
    }

    // Serialize FIRST, then swap the whole value (`setString` either replaces
    // it or fails; a false/throwing write keeps the previous envelope and
    // refuses the kick).
    final payload = jsonEncode(<String, Object?>{
      'v': kPosCashDrawerClaimsSchemaVersion,
      'claims': claims,
    });
    try {
      final ok = await prefs.setString(key, payload);
      if (!ok) return PosCashDrawerClaimResult.persistFailed;
    } catch (_) {
      return PosCashDrawerClaimResult.persistFailed;
    }
    return PosCashDrawerClaimResult.claimed;
  }
}

/// The claim-store seam. Durable by default; tests inject a failing prefs
/// resolver to exercise the refused-write path.
final posCashDrawerClaimStoreProvider = Provider<PosCashDrawerClaimStore>(
  (ref) => PosCashDrawerClaimStore(),
);
