/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F — the DURABLE journal of provider-card
/// attempts (execution packet §5).
///
/// A separately keyed sibling of the payment attempt envelope, in the house
/// `shared_preferences` JSON-envelope idiom: one schema-versioned envelope
/// `{version, attempts[]}` per operational scope (`org.restaurant.branch.device`)
/// under its OWN key prefix, so neither family can ever read or rewrite the
/// other's bytes (the precedent of `order_edit_slip_store.dart`). The base
/// `restoflow.pos.payment_attempts.v1.*` envelope is never touched.
///
/// DURABILITY: a write is durable only when `setString` reported success; any
/// other outcome throws [PosPersistenceException] and the caller sends NOTHING
/// (persist-before-send). Every operation runs in ONE isolate-wide serial
/// section per storage key and re-reads the stored bytes inside it, so two
/// stores or two provider graphs over the same key see each other's writes.
///
/// A record this build cannot read is not a record it may destroy: unreadable
/// and foreign-scope entries are kept and re-emitted (their decoded JSON value)
/// on every write, and an unreadable ENVELOPE refuses every write. Any
/// quarantine blocks NEW integrated starts until it is resolved (packet §5.3).
///
/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-JOURNAL-RECOVERY-CORRECTIONS-001: an
/// envelope holding two records of one attempt id, or two open records of one
/// order and mode, is unreadable as a whole (correction packet §6), and the
/// journal admits a NEW record only below [kProviderCardJournalCap] (§5).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'provider_card_attempt.dart';
import 'sync_cursor_store.dart' show PosPersistenceException, PosSyncScope;

/// The storage key for one scope's provider-card attempts.
String providerCardAttemptsStorageKey(String scopeKey) {
  final safe = scopeKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return 'restoflow.pos.provider_card_attempts.v1.$safe';
}

/// The envelope's schema version. An unknown version quarantines the family.
const int kProviderCardEnvelopeVersion = 1;

/// The COMPLETE set of envelope keys this build writes and understands.
const Set<String> kProviderCardEnvelopeKeys = <String>{'version', 'attempts'};

/// The retained entries per scope (packet §5.3) and the journal's ADMISSION
/// bound (correction packet §5): a new record is admitted only once fewer
/// remain, after the oldest safe and final entries (readable, in scope,
/// terminal or recorded) were dropped. No other entry is ever dropped.
const int kProviderCardJournalCap = 200;

/// Why something stored could not be used.
@immutable
class ProviderCardQuarantine {
  const ProviderCardQuarantine(this.reason, this.rule);

  /// `envelope` (the whole family: unreadable, or holding duplicate
  /// identities), `record` (one entry) or `scope` (an entry of another scope
  /// under this key).
  final String reason;

  /// The decoder's rule code, when one applies.
  final String? rule;

  @override
  String toString() =>
      'ProviderCardQuarantine($reason${rule == null ? '' : ', $rule'})';
}

/// One scope's journal as read.
@immutable
class ProviderCardLoad {
  const ProviderCardLoad({
    required this.attempts,
    required this.quarantined,
    required this.envelopeUnreadable,
  });

  static const ProviderCardLoad empty = ProviderCardLoad(
    attempts: <ProviderCardAttempt>[],
    quarantined: <ProviderCardQuarantine>[],
    envelopeUnreadable: false,
  );

  /// The readable in-scope attempts, in stored order (oldest first).
  final List<ProviderCardAttempt> attempts;
  final List<ProviderCardQuarantine> quarantined;
  final bool envelopeUnreadable;

  /// Any quarantine blocks NEW integrated starts on this till.
  bool get blocksNewStarts => quarantined.isNotEmpty;
}

/// The outcome of [ProviderCardStore.createIfAbsent].
@immutable
sealed class ProviderCardCreate {
  const ProviderCardCreate();
}

/// The new attempt was durably written.
@immutable
final class ProviderCardCreated extends ProviderCardCreate {
  const ProviderCardCreated(this.attempt);
  final ProviderCardAttempt attempt;
}

/// An open attempt of the same order and mode already exists: it is returned
/// and nothing is written.
@immutable
final class ProviderCardAdopted extends ProviderCardCreate {
  const ProviderCardAdopted(this.attempt);
  final ProviderCardAttempt attempt;
}

/// A stored record or envelope could not be read: no new attempt may start.
@immutable
final class ProviderCardCreateQuarantined extends ProviderCardCreate {
  const ProviderCardCreateQuarantined();
}

/// The journal still holds [kProviderCardJournalCap] records once every safe
/// and final one was dropped (correction packet §5): nothing was minted or
/// written, and no new attempt may start until existing attempts are
/// resolved. Not a quarantine: every stored record stays readable and usable.
@immutable
final class ProviderCardCreateFull extends ProviderCardCreate {
  const ProviderCardCreateFull();
}

/// The journal of provider-card attempts.
abstract class ProviderCardStore {
  /// Reads [scope]'s journal. Never writes and never throws: a storage failure
  /// reads as an unreadable envelope.
  Future<ProviderCardLoad> load(PosSyncScope scope);

  /// Atomically: adopts an OPEN attempt of [identityKey] and [mode], or —
  /// only when the journal admits one more record (correction packet §5) —
  /// calls [mint] for the new attempt and durably appends it. [mint] runs
  /// inside the serial section and only then, so an adopted or refused start
  /// mints no identity; it must return a record of [identityKey], [mode] and
  /// [scope]. Throws [PosPersistenceException] when the record does not match,
  /// would make the journal unreadable, or the write is not durable (nothing
  /// may then be sent); an exception of [mint] propagates and nothing is
  /// written.
  Future<ProviderCardCreate> createIfAbsent(
    PosSyncScope scope, {
    required String identityKey,
    required ProviderCardMode mode,
    required ProviderCardAttempt Function() mint,
  });

  /// Atomically applies [transform] to the FRESHEST stored record of
  /// [attemptId] (re-read inside the serial section, so a stale in-memory copy
  /// can never overwrite newer stored facts) and durably writes the result,
  /// which it returns. Throws [PosPersistenceException] when the record is
  /// absent or unreadable, the envelope is unreadable, the transform changes
  /// the attempt id, or the write is not durable.
  Future<ProviderCardAttempt> update(
    PosSyncScope scope,
    String attemptId,
    ProviderCardAttempt Function(ProviderCardAttempt current) transform,
  );
}

/// One isolate-wide serial chain per storage key (the store-instance chain of
/// `pos_cash_drawer_claim_store.dart`, keyed like the base store's
/// `_paymentKeyGuards` so two store instances still serialize).
final Map<String, Future<void>> _serialByKey = <String, Future<void>>{};

Future<T> _serialized<T>(String key, Future<T> Function() op) {
  final previous = _serialByKey[key] ?? Future<void>.value();
  final run = previous.then((_) => op());
  // The tail must survive any outcome: errors reach the caller through `run`.
  _serialByKey[key] = run.then((_) {}, onError: (_) {});
  return run;
}

/// Test seam: forgets the serial chains (each test starts a fresh isolate state).
@visibleForTesting
void resetProviderCardStoreChainsForTest() => _serialByKey.clear();

/// The `shared_preferences` implementation.
class SharedPrefsProviderCardStore implements ProviderCardStore {
  SharedPrefsProviderCardStore({Future<SharedPreferences> Function()? prefs})
    : _resolvePrefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _resolvePrefs;

  @override
  Future<ProviderCardLoad> load(PosSyncScope scope) async {
    try {
      final prefs = await _resolvePrefs();
      return _read(
        prefs.getString(providerCardAttemptsStorageKey(scope.key)),
        scope,
      ).load;
    } catch (_) {
      return const ProviderCardLoad(
        attempts: <ProviderCardAttempt>[],
        quarantined: <ProviderCardQuarantine>[
          ProviderCardQuarantine('envelope', 'storage'),
        ],
        envelopeUnreadable: true,
      );
    }
  }

  @override
  Future<ProviderCardCreate> createIfAbsent(
    PosSyncScope scope, {
    required String identityKey,
    required ProviderCardMode mode,
    required ProviderCardAttempt Function() mint,
  }) {
    final key = providerCardAttemptsStorageKey(scope.key);
    return _serialized(key, () async {
      final prefs = await _resolvePrefs();
      final read = _read(prefs.getString(key), scope);
      if (read.load.blocksNewStarts) {
        return const ProviderCardCreateQuarantined();
      }
      // A readable envelope holds at most one open record per order and mode
      // (correction packet §6): that one is adopted, at the bound too.
      for (final a in read.load.attempts) {
        if (a.identityKey == identityKey && a.mode == mode && a.isOpen) {
          return ProviderCardAdopted(a);
        }
      }
      // The admission bound (correction packet §5): only safe and final
      // records make room; with none left to drop, nothing is minted or
      // written.
      final entries = _retained(read.raws, scope, room: 1);
      if (entries.length >= kProviderCardJournalCap) {
        return const ProviderCardCreateFull();
      }
      final attempt = mint();
      if (attempt.identityKey != identityKey ||
          attempt.mode != mode ||
          !_inScope(attempt, scope)) {
        throw const PosPersistenceException(
          'provider card attempts: the new record does not match its request',
        );
      }
      await _write(prefs, key, <Object?>[...entries, _readable(attempt)]);
      return ProviderCardCreated(attempt);
    });
  }

  @override
  Future<ProviderCardAttempt> update(
    PosSyncScope scope,
    String attemptId,
    ProviderCardAttempt Function(ProviderCardAttempt current) transform,
  ) {
    final key = providerCardAttemptsStorageKey(scope.key);
    return _serialized(key, () async {
      final prefs = await _resolvePrefs();
      final read = _read(prefs.getString(key), scope);
      if (read.load.envelopeUnreadable) {
        throw const PosPersistenceException(
          'provider card attempts: the stored envelope is unreadable',
        );
      }
      final index = read.inScopeIdAt.indexOf(attemptId);
      if (index < 0) {
        throw const PosPersistenceException(
          'provider card attempts: no stored record for this attempt',
        );
      }
      final current = read.load.attempts.firstWhere(
        (a) => a.attemptId == attemptId,
      );
      final next = transform(current);
      if (next.attemptId != attemptId) {
        throw const PosPersistenceException(
          'provider card attempts: a transition may not change the identity',
        );
      }
      final entries = List<Object?>.of(read.raws);
      entries[index] = _readable(next);
      await _write(prefs, key, _retained(entries, scope, keep: attemptId));
      return next;
    });
  }

  /// The record's JSON, refused when this build could not read it back: a
  /// record that would quarantine the whole journal is never written.
  static Map<String, Object?> _readable(ProviderCardAttempt a) {
    final json = a.toJson();
    final decoded = decodeProviderCardAttempt(jsonDecode(jsonEncode(json)));
    if (decoded is ProviderCardMalformed) {
      throw PosPersistenceException(
        'provider card attempts: a record this build cannot read back '
        '(${decoded.rule})',
      );
    }
    return json;
  }

  Future<void> _write(
    SharedPreferences prefs,
    String key,
    List<Object?> entries,
  ) async {
    // Never an envelope this store would refuse to read (correction packet
    // §6): a duplicate found on read is outside corruption.
    final duplicate = _duplicates(entries, <ProviderCardAttempt>[
      for (final e in entries)
        if (decodeProviderCardAttempt(e) case ProviderCardDecoded(
          :final attempt,
        ))
          attempt,
    ]);
    if (duplicate != null) {
      throw PosPersistenceException(
        'provider card attempts: the journal would hold a $duplicate',
      );
    }
    // Build and serialize BEFORE touching storage.
    final encoded = jsonEncode(<String, Object?>{
      'version': kProviderCardEnvelopeVersion,
      'attempts': entries,
    });
    bool ok;
    try {
      ok = await prefs.setString(key, encoded);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      throw const PosPersistenceException(
        'provider card attempts: the journal could not be persisted',
      );
    }
  }

  /// Applies retention: drops the oldest prunable entries (readable, in scope,
  /// safe and final — terminal or recorded — never [keep]) while more than
  /// the cap less [room] remain. Nothing else is ever dropped, so the result
  /// may still be above that.
  List<Object?> _retained(
    List<Object?> entries,
    PosSyncScope scope, {
    int room = 0,
    String? keep,
  }) {
    final limit = kProviderCardJournalCap - room;
    if (entries.length <= limit) return entries;
    final out = List<Object?>.of(entries);
    var i = 0;
    while (out.length > limit && i < out.length) {
      final d = decodeProviderCardAttempt(out[i]);
      final prunable =
          d is ProviderCardDecoded &&
          _inScope(d.attempt, scope) &&
          d.attempt.attemptId != keep &&
          d.attempt.isRetentionPrunable;
      if (prunable) {
        out.removeAt(i);
      } else {
        i++;
      }
    }
    return out;
  }
}

bool _inScope(ProviderCardAttempt a, PosSyncScope scope) =>
    a.organizationId == scope.organizationId &&
    a.restaurantId == scope.restaurantId &&
    a.branchId == scope.branchId &&
    a.deviceId == scope.deviceId;

/// Why [entries] cannot be one journal envelope (correction packet §6), or
/// null: two entries carrying the same `attempt_id` (every object entry,
/// readable or not, of any scope), or two of the readable [records] open (the
/// predicate `createIfAbsent` adopts by) for one order and mode. Terminal rows
/// may share an order or an amount.
String? _duplicates(
  List<Object?> entries,
  Iterable<ProviderCardAttempt> records,
) {
  final ids = <String>{};
  for (final e in entries) {
    if (e is Map) {
      final id = e['attempt_id'];
      if (id is String && !ids.add(id)) return 'duplicate attempt_id';
    }
  }
  final open = <String>{};
  for (final a in records) {
    if (a.isOpen && !open.add('${a.mode.wire} ${a.identityKey}')) {
      return 'duplicate open attempt';
    }
  }
  return null;
}

class _Read {
  const _Read(this.load, this.raws, this.inScopeIdAt);
  final ProviderCardLoad load;

  /// Every stored entry as decoded JSON, in order — re-emitted on writes.
  final List<Object?> raws;

  /// For each entry, its attempt id when it is a readable in-scope record.
  final List<String?> inScopeIdAt;
}

_Read _read(String? raw, PosSyncScope scope) {
  if (raw == null || raw.isEmpty) {
    return const _Read(ProviderCardLoad.empty, <Object?>[], <String?>[]);
  }
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return _unreadableEnvelope('json');
  }
  if (decoded is! Map) return _unreadableEnvelope('not an object');
  for (final k in decoded.keys) {
    if (k is! String || !kProviderCardEnvelopeKeys.contains(k)) {
      return _unreadableEnvelope('envelope key');
    }
  }
  final version = decoded['version'];
  if (version is! int || version != kProviderCardEnvelopeVersion) {
    return _unreadableEnvelope('version');
  }
  final list = decoded['attempts'];
  if (list is! List) return _unreadableEnvelope('attempts');
  final attempts = <ProviderCardAttempt>[];
  final quarantined = <ProviderCardQuarantine>[];
  final ids = <String?>[];
  final readable = <ProviderCardAttempt>[];
  for (final entry in list) {
    final d = decodeProviderCardAttempt(entry);
    switch (d) {
      case ProviderCardDecoded(:final attempt):
        readable.add(attempt);
        if (_inScope(attempt, scope)) {
          attempts.add(attempt);
          ids.add(attempt.attemptId);
        } else {
          quarantined.add(const ProviderCardQuarantine('scope', null));
          ids.add(null);
        }
      case ProviderCardMalformed(:final rule):
        quarantined.add(ProviderCardQuarantine('record', rule));
        ids.add(null);
    }
  }
  // The whole envelope is checked before any record of it is used: with a
  // duplicate identity none is (correction packet §6). No first copy is
  // chosen, no copy is updated, and the stored bytes are never rewritten.
  final duplicate = _duplicates(list, readable);
  if (duplicate != null) return _unreadableEnvelope(duplicate);
  return _Read(
    ProviderCardLoad(
      attempts: List<ProviderCardAttempt>.unmodifiable(attempts),
      quarantined: List<ProviderCardQuarantine>.unmodifiable(quarantined),
      envelopeUnreadable: false,
    ),
    List<Object?>.of(list),
    ids,
  );
}

_Read _unreadableEnvelope(String rule) => _Read(
  ProviderCardLoad(
    attempts: const <ProviderCardAttempt>[],
    quarantined: <ProviderCardQuarantine>[
      ProviderCardQuarantine('envelope', rule),
    ],
    envelopeUnreadable: true,
  ),
  const <Object?>[],
  const <String?>[],
);

/// The journal store. Production uses the process `SharedPreferences`
/// singleton; tests override it.
final providerCardStoreProvider = Provider<ProviderCardStore>(
  (ref) => SharedPrefsProviderCardStore(),
);
