import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'seo_consent_repository.dart';

/// Owned by the app ProviderScope, beyond tabs, shells and transport refreshes.
final seoConsentOperationsProvider = Provider<SeoConsentOperations>(
  (_) => SeoConsentOperations(SharedPreferencesSeoConsentJournal()),
);

/// Membership IDs belong to an actor. Role/status/transport are excluded:
/// losing authority must quarantine an unknown operation, never erase it.
class SeoConsentOperationScope {
  const SeoConsentOperationScope({
    required this.membershipId,
    required this.organizationId,
    required this.restaurantId,
  });
  final String membershipId;
  final String organizationId;
  final String restaurantId;
  String get key => jsonEncode([membershipId, organizationId, restaurantId]);
}

abstract interface class SeoConsentJournal {
  Future<Map<String, String>> read(String scope);
  Future<void> write(String scope, String requestId, String value);
  Future<void> remove(String scope, String requestId);
}

class SharedPreferencesSeoConsentJournal implements SeoConsentJournal {
  String _prefix(String scope) =>
      'restoflow.dashboard.seo-consent.pending.v1.${base64Url.encode(utf8.encode(scope))}.';

  @override
  Future<Map<String, String>> read(String scope) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final prefix = _prefix(scope);
    return {
      for (final key in preferences.getKeys().where(
        (key) => key.startsWith(prefix),
      ))
        key.substring(prefix.length):
            preferences.getString(key) ??
            (throw const FormatException('Invalid consent journal value')),
    };
  }

  @override
  Future<void> write(String scope, String requestId, String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final key = '${_prefix(scope)}$requestId';
    final existing = preferences.getString(key);
    if (existing != null && existing != value)
      throw StateError('Consent intent conflict');
    if (!await preferences.setString(key, value))
      throw StateError('Consent journal unavailable');
    await preferences.reload();
    if (preferences.getString(key) != value)
      throw StateError('Consent journal readback failed');
  }

  @override
  Future<void> remove(String scope, String requestId) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.remove('${_prefix(scope)}$requestId'))
      throw StateError('Consent journal unavailable');
  }
}

/// Only immutable UUID/CAS/decision is journaled, never credentials or drafts.
/// Each UUID has its own key: browser tabs cannot overwrite another operation.
/// Multiple unknown entries stay frozen and are explicitly reconciled in order.
class SeoConsentOperations {
  SeoConsentOperations(this._journal);
  final SeoConsentJournal _journal;
  final _pending = <String, Map<String, SeoConsentMutation>>{};
  final _loads = <String, Future<void>>{};
  final _flights = <String, (SeoConsentMutation, Future<SeoConsentResult>)>{};

  SeoConsentMutation? pending(SeoConsentOperationScope scope) {
    final entries = _pending[scope.key];
    if (entries == null || entries.isEmpty) return null;
    final keys = entries.keys.toList()..sort();
    return entries[keys.first];
  }

  int pendingCount(SeoConsentOperationScope scope) =>
      _pending[scope.key]?.length ?? 0;

  Future<void> restore(SeoConsentOperationScope scope) async {
    final loading = _loads[scope.key];
    if (loading != null) return loading;
    final future = _readAndMerge(scope.key);
    _loads[scope.key] = future;
    try {
      await future;
    } finally {
      _loads.remove(scope.key);
    }
  }

  Future<void> _readAndMerge(String key) async {
    final records = await _journal.read(key);
    final entries = _pending.putIfAbsent(key, () => {});
    for (final entry in records.entries) {
      final raw = jsonDecode(entry.value);
      if (raw is! Map ||
          raw['version'] != 1 ||
          raw['id'] != entry.key ||
          !_uuid.hasMatch(entry.key) ||
          raw['expected_revision'] is! String ||
          !isSeoConsentRevision(raw['expected_revision'] as String) ||
          raw['consent_enabled'] is! bool) {
        throw const FormatException('Invalid consent operation journal');
      }
      final intent = SeoConsentMutation(
        id: entry.key,
        expectedRevision: raw['expected_revision'] as String,
        consentEnabled: raw['consent_enabled'] as bool,
      );
      final existing = entries[entry.key];
      if (existing != null && !_same(existing, intent))
        throw StateError('Consent intent conflict');
      entries[entry.key] = existing ?? intent;
    }
    // A missing preference is never proof that an in-flight write was cancelled.
    // Only a conclusive exact receipt removes an in-memory unknown operation.
  }

  Future<SeoConsentResult> save(
    SeoConsentOperationScope scope,
    SeoConsentRepository repository,
    SeoConsentMutation intent,
  ) {
    final flight = _flights[scope.key];
    if (flight != null)
      return _same(flight.$1, intent)
          ? flight.$2
          : Future.value(const SeoConsentResult(SeoConsentOutcome.unavailable));
    final future = _save(scope, repository, intent);
    _flights[scope.key] = (intent, future);
    return future.whenComplete(() => _flights.remove(scope.key));
  }

  Future<SeoConsentResult> _save(
    SeoConsentOperationScope scope,
    SeoConsentRepository repository,
    SeoConsentMutation intent,
  ) async {
    try {
      await restore(scope);
      final previous = pending(scope);
      if (previous != null && !_same(previous, intent))
        return const SeoConsentResult(SeoConsentOutcome.unavailable);
      final replay = previous != null;
      _pending.putIfAbsent(scope.key, () => {})[intent.id] = previous ?? intent;
      final encoded = jsonEncode({
        'version': 1,
        'id': intent.id,
        'expected_revision': intent.expectedRevision,
        'consent_enabled': intent.consentEnabled,
      });
      await _journal.write(scope.key, intent.id, encoded);
      if ((await _journal.read(scope.key))[intent.id] != encoded) {
        throw StateError('Consent journal readback failed');
      }
      // Readback precedes POST. This is not an atomic cross-tab CAS; separate
      // immutable keys retain every racing request, and all remain quarantined.
      await restore(scope);
      if (!replay && pendingCount(scope) > 1)
        return const SeoConsentResult(SeoConsentOutcome.unavailable);
      final result = await repository.save(intent);
      // Denied/not_found on a resend cannot disprove an earlier late commit.
      // Only exact success or an exact terminal receipt may release the intent.
      if (result.outcome == SeoConsentOutcome.ok && result.state != null)
        await _release(scope, intent);
      return result;
    } catch (_) {
      return const SeoConsentResult(SeoConsentOutcome.unavailable);
    }
  }

  Future<SeoConsentReconciliation> reconcile(
    SeoConsentOperationScope scope,
    SeoConsentRepository repository,
    SeoConsentMutation intent,
  ) async {
    try {
      await restore(scope);
      final saved = _pending[scope.key]?[intent.id];
      if (saved != null && !_same(saved, intent))
        return const SeoConsentReconciliation(SeoConsentOutcome.unavailable);
      final result = await repository.reconcile(intent);
      if (result.outcome == SeoConsentOutcome.requestConflict) {
        // A UUID collision is not proof that this exact decision was refused.
        return SeoConsentReconciliation(
          result.outcome,
          current: result.current,
        );
      }
      if (result.mutationState == SeoConsentMutationState.committed ||
          result.mutationState == SeoConsentMutationState.refused)
        await _release(scope, intent);
      return result;
    } catch (_) {
      return const SeoConsentReconciliation(SeoConsentOutcome.unavailable);
    }
  }

  Future<void> _release(
    SeoConsentOperationScope scope,
    SeoConsentMutation intent,
  ) async {
    await _journal.remove(scope.key, intent.id);
    _pending[scope.key]?.remove(intent.id);
    // Discover the next durable entry before enabling any new draft.
    await restore(scope);
  }

  static bool _same(SeoConsentMutation a, SeoConsentMutation b) =>
      a.id == b.id &&
      a.expectedRevision == b.expectedRevision &&
      a.consentEnabled == b.consentEnabled;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
}
