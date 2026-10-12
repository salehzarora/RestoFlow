import 'dart:convert';

import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'storefront_models.dart';
import 'storefront_rpc.dart';

/// STOREFRONT-PUBLISH-001 — the classified outcome of the manager read.
enum StorefrontReadStatus {
  /// The profile (or its absence: `exists == false`) + derived facts were read.
  ok,

  /// `not_found`: the caller cannot manage the storefront of this restaurant
  /// (below manager, another tenant, unknown restaurant — the server does not
  /// say which; no leak). The card shows an honest note and NO fields.
  denied,

  /// A transport failure or a database refusal (e.g. `42501`): nothing is
  /// known; offer a retry.
  unavailable,

  /// The server answered with an envelope this build cannot decode (a typed
  /// [StorefrontDecodeException] in [StorefrontProfileRead.decodeError]).
  /// Treated like [unavailable] by the UI — never a crash, never a guess.
  malformed,
}

/// The manager read (`get_restaurant_storefront_profile`).
class StorefrontProfileRead {
  const StorefrontProfileRead.ok({
    required this.exists,
    required this.version,
    required this.profile,
    required StorefrontDerived this.derived,
  }) : status = StorefrontReadStatus.ok,
       decodeError = null,
       code = null;

  const StorefrontProfileRead.denied()
    : status = StorefrontReadStatus.denied,
      exists = false,
      version = 0,
      profile = null,
      derived = null,
      decodeError = null,
      code = null;

  const StorefrontProfileRead.unavailable({this.code})
    : status = StorefrontReadStatus.unavailable,
      exists = false,
      version = 0,
      profile = null,
      derived = null,
      decodeError = null;

  const StorefrontProfileRead.malformed(
    StorefrontDecodeException this.decodeError,
  ) : status = StorefrontReadStatus.malformed,
      exists = false,
      version = 0,
      profile = null,
      derived = null,
      code = null;

  final StorefrontReadStatus status;

  /// Whether a profile row exists (false = the create form).
  final bool exists;

  /// The authoritative version: 0 when no profile exists yet — the value to
  /// send as `expectedVersion` on the next save.
  final int version;

  /// The profile row; null when [exists] is false (and for non-ok reads).
  final StorefrontProfile? profile;

  /// The derived facts; non-null exactly when [status] is ok.
  final StorefrontDerived? derived;

  final StorefrontDecodeException? decodeError;

  /// The SQLSTATE of an [StorefrontReadStatus.unavailable] database refusal.
  final String? code;

  bool get isOk => status == StorefrontReadStatus.ok;
}

/// The classified outcome of a profile save (never a bare `false`).
enum StorefrontWriteStatus {
  /// The write committed. The success envelope carries NO profile — callers
  /// re-read after every save.
  ok,

  /// Someone else changed the profile first (stale expected version);
  /// [StorefrontWriteResult.version] carries the CURRENT version. Reload the
  /// authoritative profile — never merge silently.
  conflict,

  /// `permission_denied`: the caller may not manage this storefront.
  denied,

  /// The patch was refused: [StorefrontWriteResult.reason] (see
  /// [kStorefrontInvalidReasons]) + optional `field` / `blockers`.
  invalid,

  /// A database refusal (`42501`) or an unrecognised error envelope: nothing
  /// committed.
  unavailable,

  /// Both attempts were lost, and a readback CONFIRMED the version never
  /// advanced: the write did not commit.
  notCommitted,

  /// The outcome is UNKNOWN: both attempts were lost and the readback failed
  /// too. Refresh, and let the user try again.
  uncertain,
}

/// A profile save result.
class StorefrontWriteResult {
  const StorefrontWriteResult(
    this.status, {
    this.requestId,
    this.expectedVersion,
    this.version,
    this.isPublished,
    this.slug,
    this.reason,
    this.field,
    this.blockers = const <String>[],
    this.idempotentReplay = false,
    this.refusedLocally = false,
    this.code,
    this.readback,
  });

  final StorefrontWriteStatus status;

  /// The idempotency key used (reuse it to retry THIS request); null for a
  /// local refusal that never reached the server.
  final String? requestId;

  /// The expected version the request was SENT with (null for a local
  /// refusal that never reached the server). Retrying THIS request after an
  /// unknown outcome replays [requestId] with exactly this version.
  final int? expectedVersion;

  /// ok: the new version. conflict / notCommitted: the current version.
  final int? version;
  final bool? isPublished;
  final String? slug;

  /// invalid: the writer's reason code.
  final String? reason;

  /// invalid: the offending key (`unknown_field`, local refusals).
  final String? field;

  /// invalid `publish_precondition`: the ordered blocker codes (`detail`).
  final List<String> blockers;

  /// ok: the server replayed an already-committed request.
  final bool idempotentReplay;

  /// invalid: refused by the repository BEFORE any server call.
  final bool refusedLocally;

  /// unavailable: the SQLSTATE of a database refusal.
  final String? code;

  /// The authoritative read taken while reconciling a lost response (ok /
  /// conflict / notCommitted after reconciliation; the failed read for
  /// uncertain).
  final StorefrontProfileRead? readback;

  bool get isOk => status == StorefrontWriteStatus.ok;
}

/// Reads + writes the restaurant's storefront profile through the READ-001
/// RPCs. The server derives the actor from `auth.uid()` and gates on the
/// actor's rank over the restaurant (manager+); this seam sends no identity
/// and no service-role key (D-011). Faked in widget tests.
abstract interface class StorefrontProfileRepository {
  /// The authoritative profile + derived facts (READ BEFORE EDIT).
  Future<StorefrontProfileRead> read();

  /// Compare-and-set [patch] (allowlisted keys only, changed keys only) on
  /// [expectedVersion] (0 creates). ONE stable request id per logical save —
  /// pass [requestId] to retry a specific earlier request, otherwise a fresh
  /// one is minted.
  Future<StorefrontWriteResult> save({
    required int expectedVersion,
    required Map<String, Object?> patch,
    String? requestId,
  });
}

/// The real, Supabase-backed [StorefrontProfileRepository] over
/// `public.get_restaurant_storefront_profile` /
/// `public.set_restaurant_storefront_profile`.
class SupabaseStorefrontProfileRepository
    implements StorefrontProfileRepository {
  SupabaseStorefrontProfileRepository({
    required SyncRpcTransport transport,
    required this.organizationId,
    required this.restaurantId,
    int Function()? nonce,
  }) : _t = transport,
       _nonce = nonce ?? _microNonce;

  static const String readFunction = 'get_restaurant_storefront_profile';
  static const String writeFunction = 'set_restaurant_storefront_profile';

  /// The idempotency-key namespace of a profile save.
  static const String requestIdPrefix = 'pbl:storefront:';

  final SyncRpcTransport _t;
  final String organizationId;
  final String restaurantId;
  final int Function() _nonce;

  static int _microNonce() => DateTime.now().microsecondsSinceEpoch;

  @override
  Future<StorefrontProfileRead> read() async {
    final attempt = await invokeStorefrontRpc(_t, readFunction, {
      'p_organization_id': organizationId,
      'p_restaurant_id': restaurantId,
    });
    if (attempt.nonEnvelope) {
      return const StorefrontProfileRead.malformed(
        StorefrontDecodeException('envelope', 'not an object'),
      );
    }
    if (!attempt.isResponded) {
      return StorefrontProfileRead.unavailable(code: attempt.code);
    }
    final raw = attempt.response!;
    if (raw['ok'] != true) {
      return raw['error'] == 'not_found'
          ? const StorefrontProfileRead.denied()
          : const StorefrontProfileRead.unavailable();
    }
    try {
      return _decodeRead(raw);
    } on StorefrontDecodeException catch (e) {
      return StorefrontProfileRead.malformed(e);
    }
  }

  StorefrontProfileRead _decodeRead(Map<dynamic, dynamic> raw) {
    final exists = raw['exists'];
    if (exists is! bool) {
      throw const StorefrontDecodeException('exists', 'expected a bool');
    }
    final version = decodeStorefrontInt(raw, 'version', '', min: 0);
    final envelopeRestaurant = decodeStorefrontString(raw, 'restaurant_id', '');
    if (envelopeRestaurant.toLowerCase() != restaurantId.toLowerCase()) {
      throw const StorefrontDecodeException('restaurant_id', 'another scope');
    }
    StorefrontProfile? profile;
    if (exists) {
      profile = StorefrontProfile.fromJson(raw['profile']);
      if (profile.version != version) {
        throw const StorefrontDecodeException('profile.version', 'mismatch');
      }
      if (profile.restaurantId.toLowerCase() != restaurantId.toLowerCase()) {
        throw const StorefrontDecodeException(
          'profile.restaurant_id',
          'another scope',
        );
      }
    } else {
      if (raw['profile'] != null) {
        throw const StorefrontDecodeException('profile', 'expected null');
      }
      if (version != 0) {
        throw const StorefrontDecodeException('version', 'expected 0');
      }
    }
    return StorefrontProfileRead.ok(
      exists: exists,
      version: version,
      profile: profile,
      derived: StorefrontDerived.fromJson(raw['derived']),
    );
  }

  @override
  Future<StorefrontWriteResult> save({
    required int expectedVersion,
    required Map<String, Object?> patch,
    String? requestId,
  }) async {
    if (expectedVersion < 0) {
      throw ArgumentError.value(expectedVersion, 'expectedVersion');
    }
    if (requestId != null && !isCanonicalUuid(requestId)) {
      throw ArgumentError.value(requestId, 'requestId', 'not a canonical uuid');
    }
    // Local guards: only allowlisted keys ever leave the Dashboard (so no
    // ordering/delivery flag can be sent), and the slug is immutable once the
    // profile exists — refused here, without a server call.
    for (final key in patch.keys) {
      if (!StorefrontProfile.patchableKeys.contains(key)) {
        return StorefrontWriteResult(
          StorefrontWriteStatus.invalid,
          reason: 'unknown_field',
          field: key,
          refusedLocally: true,
        );
      }
    }
    if (expectedVersion > 0 && patch.containsKey('slug')) {
      return const StorefrontWriteResult(
        StorefrontWriteStatus.invalid,
        reason: 'slug_immutable',
        field: 'slug',
        refusedLocally: true,
      );
    }

    // ONE STABLE idempotency id for this logical save: an ambiguous-outcome
    // retry replays the SAME request (a committed write returns its stored
    // result from the server ledger — never a second version bump).
    final id =
        requestId ??
        storefrontRequestId(requestIdPrefix, [
          organizationId,
          restaurantId,
          expectedVersion.toString(),
          jsonEncode(patch, toEncodable: (o) => o.toString()),
        ], _nonce());

    final attempt = await invokeStorefrontMutation(_t, writeFunction, {
      'p_client_request_id': id,
      'p_organization_id': organizationId,
      'p_restaurant_id': restaurantId,
      'p_expected_version': expectedVersion,
      'p_patch': patch,
    });
    switch (attempt.kind) {
      case StorefrontRpcAttemptKind.responded:
        return _classify(attempt.response!, id, expectedVersion);
      case StorefrontRpcAttemptKind.refused:
        return StorefrontWriteResult(
          StorefrontWriteStatus.unavailable,
          requestId: id,
          expectedVersion: expectedVersion,
          code: attempt.code,
        );
      case StorefrontRpcAttemptKind.ambiguous:
        return _reconcile(id, expectedVersion, patch);
    }
  }

  StorefrontWriteResult _classify(
    Map<dynamic, dynamic> raw,
    String id,
    int expectedVersion,
  ) {
    final version = raw['version'] is int ? raw['version'] as int : null;
    final isPublished = raw['is_published'] is bool
        ? raw['is_published'] as bool
        : null;
    final slug = raw['slug'] is String ? raw['slug'] as String : null;
    if (raw['ok'] == true) {
      return StorefrontWriteResult(
        StorefrontWriteStatus.ok,
        requestId: id,
        expectedVersion: expectedVersion,
        version: version,
        isPublished: isPublished,
        slug: slug,
        idempotentReplay: raw['idempotent_replay'] == true,
      );
    }
    switch (raw['error']) {
      case 'version_conflict':
        return StorefrontWriteResult(
          StorefrontWriteStatus.conflict,
          requestId: id,
          expectedVersion: expectedVersion,
          version: version,
          isPublished: isPublished,
          slug: slug,
        );
      case 'permission_denied':
        return StorefrontWriteResult(
          StorefrontWriteStatus.denied,
          requestId: id,
          expectedVersion: expectedVersion,
        );
      case 'invalid':
        final detail = raw['detail'];
        return StorefrontWriteResult(
          StorefrontWriteStatus.invalid,
          requestId: id,
          expectedVersion: expectedVersion,
          reason: raw['reason'] is String ? raw['reason'] as String : null,
          field: raw['field'] is String ? raw['field'] as String : null,
          blockers: detail is List
              ? List.unmodifiable(detail.whereType<String>())
              : const <String>[],
        );
      default:
        // A RESPONDED-but-unrecognised error means no commit happened.
        return StorefrontWriteResult(
          StorefrontWriteStatus.unavailable,
          requestId: id,
          expectedVersion: expectedVersion,
        );
    }
  }

  /// Both attempts were lost: decide from the authoritative state whether the
  /// write committed. Never guesses — an unreadable state is `uncertain`.
  Future<StorefrontWriteResult> _reconcile(
    String id,
    int expectedVersion,
    Map<String, Object?> patch,
  ) async {
    final current = await read();
    if (!current.isOk) {
      return StorefrontWriteResult(
        StorefrontWriteStatus.uncertain,
        requestId: id,
        expectedVersion: expectedVersion,
        readback: current,
      );
    }
    if (current.version == expectedVersion) {
      return StorefrontWriteResult(
        StorefrontWriteStatus.notCommitted,
        requestId: id,
        expectedVersion: expectedVersion,
        version: current.version,
        readback: current,
      );
    }
    final profile = current.profile;
    if (current.version == expectedVersion + 1 &&
        profile != null &&
        storefrontProfileReflectsPatch(profile, patch)) {
      // The version advanced exactly once TO our intended state => WE did it.
      return StorefrontWriteResult(
        StorefrontWriteStatus.ok,
        requestId: id,
        expectedVersion: expectedVersion,
        version: current.version,
        isPublished: profile.isPublished,
        slug: profile.slug,
        readback: current,
      );
    }
    // The version advanced, but not (only) by us => someone else won.
    return StorefrontWriteResult(
      StorefrontWriteStatus.conflict,
      requestId: id,
      expectedVersion: expectedVersion,
      version: current.version,
      isPublished: profile?.isPublished,
      slug: profile?.slug,
      readback: current,
    );
  }
}

/// Postgres `btrim(text)` trims SPACES only (not every whitespace).
String _pgBtrim(String s) {
  var start = 0;
  var end = s.length;
  while (start < end && s.codeUnitAt(start) == 0x20) {
    start++;
  }
  while (end > start && s.codeUnitAt(end - 1) == 0x20) {
    end--;
  }
  return s.substring(start, end);
}

String? _pgNullIfBlank(Object? v) {
  if (v is! String) return null;
  final t = _pgBtrim(v);
  return t.isEmpty ? null : t;
}

bool _sameId(String? a, Object? b) {
  if (a == null || b == null) return a == null && b == null;
  return b is String && a.toLowerCase() == b.toLowerCase();
}

/// Whether [profile] shows every value of [patch] exactly as the writer would
/// have stored it (mirroring its normalisation: `btrim` + `nullif(..., '')`
/// for free text, lower-case colours, ids compared case-insensitively, the
/// hours by model equality, `paused_until` by instant). Used only to decide
/// whether a lost-response write was OURS — a mismatch reads as a conflict
/// (the safe direction: reload, never claim a write that is not ours).
bool storefrontProfileReflectsPatch(
  StorefrontProfile profile,
  Map<String, Object?> patch,
) {
  for (final entry in patch.entries) {
    final v = entry.value;
    final same = switch (entry.key) {
      'slug' => v is String && profile.slug == v,
      'storefront_branch_id' => _sameId(profile.storefrontBranchId, v),
      'display_name' => v is String && profile.displayName == _pgBtrim(v),
      'tagline' => profile.tagline == _pgNullIfBlank(v),
      'public_city' => profile.publicCity == _pgNullIfBlank(v),
      'public_address' => profile.publicAddress == _pgNullIfBlank(v),
      'public_phone' => profile.publicPhone == _pgNullIfBlank(v),
      'pause_reason' => profile.pauseReason == _pgNullIfBlank(v),
      'primary_color' =>
        v is String && profile.primaryColor.toLowerCase() == v.toLowerCase(),
      'accent_color' =>
        v is String && profile.accentColor.toLowerCase() == v.toLowerCase(),
      'visual_preset' => profile.visualPreset.name == v,
      'locale_default' => profile.localeDefault.name == v,
      'card_mode' => profile.cardMode.name == v,
      'motion' => profile.motion.name == v,
      'pickup_enabled' => profile.pickupEnabled == v,
      'is_published' => profile.isPublished == v,
      'logo_media_id' => _sameId(profile.logoMediaId, v),
      'hero_media_id' => _sameId(profile.heroMediaId, v),
      'paused_until' => _sameInstant(profile.pausedUntil, v),
      'opening_hours' =>
        OpeningHours.isValidJson(v) &&
            OpeningHours.fromJson(v) == profile.openingHours,
      _ => false,
    };
    if (!same) return false;
  }
  return true;
}

bool _sameInstant(DateTime? stored, Object? wire) {
  if (wire == null) return stored == null;
  if (wire is! String || stored == null) return false;
  final parsed = DateTime.tryParse(wire);
  return parsed != null && parsed.isAtSameMomentAs(stored);
}
