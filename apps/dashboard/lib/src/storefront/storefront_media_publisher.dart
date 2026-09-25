import 'dart:async';
import 'dart:convert';

import 'package:supabase/supabase.dart';

import 'storefront_models.dart';

/// STOREFRONT-PUBLISH-001 — the client side of the `storefront-media-publish`
/// Edge Function (CONTRACT §2).
///
/// The Dashboard sends BOUNDED IDENTIFIERS ONLY: it never encodes an image,
/// never sends bytes and never uploads to the public `storefront-media` bucket
/// itself. The function (running as the CALLER — no service-role key, D-011)
/// downloads the private original, derives one rung of the pinned recipe
/// `storefront-media-c4` (focused codecs; the source must decode to at most
/// 8 MiP = 8,388,608 px, each side at most 8192 px, aspect at most 8:1, PNG /
/// JPEG / WebP only), stages, uploads and finalizes.

/// One HTTP exchange with the function, reduced to what the publisher needs.
class StorefrontFunctionReply {
  const StorefrontFunctionReply({
    this.httpStatus,
    this.json,
    this.transportFailed = false,
  });

  /// No HTTP answer at all (network error, timeout, SDK failure).
  const StorefrontFunctionReply.transportFailure()
    : httpStatus = null,
      json = null,
      transportFailed = true;

  /// Builds a reply from an HTTP [status] and the SDK's decoded body: a Map
  /// for `application/json`, otherwise text (parsed when it is a JSON object).
  factory StorefrontFunctionReply.fromHttp(int status, Object? data) {
    Object? decoded = data;
    if (data is String) {
      try {
        decoded = jsonDecode(data);
      } catch (_) {
        decoded = null;
      }
    }
    Map<String, Object?>? json;
    if (decoded is Map) {
      json = <String, Object?>{
        for (final e in decoded.entries)
          if (e.key is String) e.key as String: e.value,
      };
    }
    return StorefrontFunctionReply(httpStatus: status, json: json);
  }

  final int? httpStatus;
  final Map<String, Object?>? json;
  final bool transportFailed;
}

/// The Edge Function seam (faked in tests).
abstract interface class StorefrontFunctionInvoker {
  /// POSTs [body] to `storefront-media-publish` with the caller's session.
  /// Never throws: every failure is a [StorefrontFunctionReply].
  Future<StorefrontFunctionReply> invoke(Map<String, Object?> body);
}

/// The real [StorefrontFunctionInvoker] over the dashboard's single
/// authenticated anon-key [SupabaseClient] (D-011): the SDK attaches the
/// signed-in user's access token. Built ONCE per app lifetime in
/// `buildDashboardRealAuth`.
class SupabaseStorefrontFunctionInvoker implements StorefrontFunctionInvoker {
  SupabaseStorefrontFunctionInvoker(
    this._client, {
    Duration timeout = const Duration(seconds: 60),
  }) : _timeout = timeout;

  static const String functionName = 'storefront-media-publish';

  /// The PUBLIC bucket that holds ONLY transformed derivatives (CONTRACT §0).
  static const String publicBucket = 'storefront-media';

  final SupabaseClient _client;
  final Duration _timeout;

  /// The public URL of a published derivative's [objectKey]
  /// (`<SUPABASE_URL>/storage/v1/object/public/storefront-media/<key>`) — for
  /// the editor's preview only. Pure URL construction (no request, no
  /// signing); private originals never get a public URL.
  Uri publicMediaUrl(String objectKey) =>
      Uri.parse(_client.storage.from(publicBucket).getPublicUrl(objectKey));

  @override
  Future<StorefrontFunctionReply> invoke(Map<String, Object?> body) async {
    try {
      final response = await _client.functions
          .invoke(functionName, body: body)
          .timeout(_timeout);
      return StorefrontFunctionReply.fromHttp(response.status, response.data);
    } on FunctionException catch (e) {
      // A non-2xx answer: the status + the (decoded) error body.
      return StorefrontFunctionReply.fromHttp(e.status, e.details);
    } catch (_) {
      // Network failure / timeout / anything else: outcome UNKNOWN.
      return const StorefrontFunctionReply.transportFailure();
    }
  }
}

/// The private original a derivative is made from.
class StorefrontMediaSource {
  const StorefrontMediaSource({required this.bucket, required this.key});

  /// The restaurant's CURRENT receipt logo (`restaurant-logos`).
  const StorefrontMediaSource.receiptLogo(this.key)
    : bucket = StorefrontSourceBucket.restaurantLogos;

  /// A menu item's original image (`menu-images`) — hero only.
  const StorefrontMediaSource.menuImage(this.key)
    : bucket = StorefrontSourceBucket.menuImages;

  final StorefrontSourceBucket bucket;

  /// The private original's storage key (never made public).
  final String key;
}

/// The published derivative described by a `200 published` answer.
class StorefrontPublishedMedia {
  const StorefrontPublishedMedia({
    required this.id,
    required this.objectKey,
    required this.contentHash,
    required this.width,
    required this.height,
    required this.byteLength,
    required this.variant,
    required this.sourceBucket,
    required this.sourceKey,
  });

  final String id;
  final String objectKey;
  final String contentHash;
  final int width;
  final int height;
  final int byteLength;
  final StorefrontVariant variant;
  final StorefrontSourceBucket sourceBucket;
  final String sourceKey;
}

/// The classified outcome of one logical publish.
enum StorefrontPublishStatus {
  /// `200 published`: assign the slot via the profile CAS writer next (re-read
  /// the profile first when [StorefrontPublishResult.profileVersion] != null).
  published,

  /// `422 refused`: a typed, deterministic refusal of THIS source
  /// ([StorefrontPublishResult.refusalCode]) — never retry the same source
  /// (the hero may pick another; the logo's only source is the receipt logo,
  /// which must be replaced in Branding).
  refused,

  /// `403`: not a manager+ of this restaurant.
  denied,

  /// `404`: the private original is gone or not readable.
  sourceMissing,

  /// `409 restart_required`: the request id was used with different input —
  /// start over with a NEW request id (rung 0).
  restartRequired,

  /// `401`: the session expired — sign in again.
  unauthenticated,

  /// `409 object_conflict`: different bytes already sit at the content
  /// address, or the stage step found the address registered for different
  /// content (the stage's `content_mismatch` — the function answers it here,
  /// never as a 422 refusal). Not expected for honest clients.
  objectConflict,

  /// `400/405/413/415`, a `422` whose code is not about the source image (see
  /// [kStorefrontPublishFaultCodes]), or refused locally before any call: a
  /// programming / server fault ([StorefrontPublishResult.invalidField] /
  /// `invalidReason`) — never "pick another source".
  invalidRequest,

  /// A `403/404/409/422` (or `400/405/413/415`) WITHOUT the contract's
  /// `status` for that code: the answer did not come from the function (e.g.
  /// the platform gateway's `404 NOT_FOUND` while the function is not
  /// deployed). Nothing is claimed about the source; the caller refreshes the
  /// authoritative state and says the publishing service is unavailable.
  serviceUnavailable,

  /// The outcome is UNKNOWN (5xx / transport / unexpected answer, retried
  /// once with the same request id and rung). Refresh the authoritative state
  /// (`list_storefront_media` + the profile) and show what it says.
  uncertain,
}

/// A publish result.
class StorefrontPublishResult {
  const StorefrontPublishResult(
    this.status, {
    required this.requestId,
    required this.slot,
    this.media,
    this.profileVersion,
    this.alreadyPublished = false,
    this.republished = false,
    this.replacedMediaId,
    this.refusalCode,
    this.invalidField,
    this.invalidReason,
    this.rung = 0,
    this.calls = 0,
    this.serverFlaggedUncertain = false,
    this.refusedLocally = false,
  });

  final StorefrontPublishStatus status;
  final String requestId;
  final StorefrontSlot slot;

  /// published: the LIVE derivative.
  final StorefrontPublishedMedia? media;

  /// published: the profile's version after a same-source re-point (the
  /// profile changed server-side — re-read it before assigning), else null.
  final int? profileVersion;
  final bool alreadyPublished;
  final bool republished;
  final String? replacedMediaId;

  /// refused: the typed code (see [kStorefrontRefusalCodes]); unknown future
  /// codes are kept verbatim.
  final String? refusalCode;

  /// invalidRequest: the server's (or the local guard's) field + reason.
  final String? invalidField;
  final String? invalidReason;

  /// The last rung sent.
  final int rung;

  /// How many times the function was invoked for this publish.
  final int calls;

  /// uncertain: the server itself said the outcome may be partial
  /// (`uncertain: true` on a 5xx) — refresh before anything else.
  final bool serverFlaggedUncertain;

  /// invalidRequest: refused by the publisher before any call.
  final bool refusedLocally;

  bool get isPublished => status == StorefrontPublishStatus.published;
}

/// Drives ONE logical publish through the function's rung ladder (CONTRACT §2):
/// rung 0..4 on `202 ladder_next` (same request id), a typed terminal answer,
/// or — on 5xx / transport / an unexpected answer — ONE retry with the same
/// request id and rung, then `uncertain`. It never loops forever: the ladder
/// strictly climbs to at most [maxRung] and each rung is tried at most twice
/// (hard cap: 5 rungs x 2 = 10 invocations).
class StorefrontMediaPublisher {
  StorefrontMediaPublisher({
    required StorefrontFunctionInvoker invoker,
    required this.organizationId,
    required this.restaurantId,
    this.retryDelay = const Duration(milliseconds: 500),
  }) : _invoker = invoker;

  /// The highest rung of the pinned recipe's ladder (rungs 0..4).
  static const int maxRung = 4;

  /// The exact request keys of the function's validator.
  static const List<String> requestKeys = [
    'request_id',
    'organization_id',
    'restaurant_id',
    'slot',
    'variant',
    'source_bucket',
    'source_key',
    'rung',
  ];

  static const int _maxSourceKeyLength = 512;

  final StorefrontFunctionInvoker _invoker;
  final String organizationId;
  final String restaurantId;

  /// Pause before the single retry of an ambiguous answer.
  final Duration retryDelay;

  /// Publishes [source] for [slot]. [requestId] is ONE canonical lower-case
  /// UUID per logical publish (reused across rungs and the retry; a
  /// `restartRequired` answer needs a NEW one).
  Future<StorefrontPublishResult> publish({
    required StorefrontSlot slot,
    required StorefrontMediaSource source,
    required String requestId,
  }) async {
    StorefrontPublishResult local(String field, String reason) =>
        StorefrontPublishResult(
          StorefrontPublishStatus.invalidRequest,
          requestId: requestId,
          slot: slot,
          invalidField: field,
          invalidReason: reason,
          refusedLocally: true,
        );
    if (!isCanonicalUuid(requestId)) return local('request_id', 'value');
    if (!slot.allowedBuckets.contains(source.bucket)) {
      return local('source_bucket', 'mismatch');
    }
    if (source.key.isEmpty || source.key.length > _maxSourceKeyLength) {
      return local('source_key', 'value');
    }

    var rung = 0;
    var calls = 0;
    var serverUncertain = false;
    // At most maxRung + 1 rungs: the ladder only ever climbs (see _classify).
    for (var visited = 0; visited <= maxRung; visited++) {
      var step = const _Step.ambiguous();
      for (var attempt = 0; attempt < 2; attempt++) {
        if (attempt > 0 && retryDelay > Duration.zero) {
          await Future<void>.delayed(retryDelay);
        }
        final reply = await _safeInvoke(
          _body(slot: slot, source: source, requestId: requestId, rung: rung),
        );
        calls++;
        step = _classify(reply, rung);
        if (step.serverUncertain) serverUncertain = true;
        if (!step.isAmbiguous) break;
      }
      if (step.isAmbiguous) {
        return StorefrontPublishResult(
          StorefrontPublishStatus.uncertain,
          requestId: requestId,
          slot: slot,
          rung: rung,
          calls: calls,
          serverFlaggedUncertain: serverUncertain,
        );
      }
      final next = step.nextRung;
      if (next != null) {
        rung = next;
        continue;
      }
      return step.toResult(
        requestId: requestId,
        slot: slot,
        rung: rung,
        calls: calls,
        serverUncertain: serverUncertain,
      );
    }
    // Unreachable while the ladder strictly climbs within 0..maxRung; kept as
    // the explicit hard stop.
    return StorefrontPublishResult(
      StorefrontPublishStatus.uncertain,
      requestId: requestId,
      slot: slot,
      rung: rung,
      calls: calls,
      serverFlaggedUncertain: serverUncertain,
    );
  }

  Map<String, Object?> _body({
    required StorefrontSlot slot,
    required StorefrontMediaSource source,
    required String requestId,
    required int rung,
  }) => {
    'request_id': requestId,
    'organization_id': organizationId,
    'restaurant_id': restaurantId,
    'slot': slot.wire,
    'variant': slot.variant.name,
    'source_bucket': source.bucket.wire,
    'source_key': source.key,
    'rung': rung,
  };

  Future<StorefrontFunctionReply> _safeInvoke(Map<String, Object?> body) async {
    try {
      return await _invoker.invoke(body);
    } catch (_) {
      return const StorefrontFunctionReply.transportFailure();
    }
  }

  _Step _classify(StorefrontFunctionReply reply, int rung) {
    final status = reply.httpStatus;
    final json = reply.json ?? const <String, Object?>{};
    if (reply.transportFailed || status == null) return const _Step.ambiguous();
    // A typed 4xx counts only with the contract's `status` for that code: the
    // platform gateway answers with its own bodies (e.g. `404 NOT_FOUND` for
    // a function that is not deployed) and must never read as a verdict on
    // the source image.
    final said = json['status'];
    const notFromFunction = _Step.terminal(
      StorefrontPublishStatus.serviceUnavailable,
    );
    switch (status) {
      case 200:
        final published = _decodePublished(json);
        return published ?? const _Step.ambiguous();
      case 202:
        final next = json['next_rung'];
        if (said == 'ladder_next' &&
            next is int &&
            next > rung &&
            next <= maxRung) {
          return _Step.next(next);
        }
        // A 202 that does not climb the ladder is a protocol violation: stop
        // (never loop) and let the caller refresh the authoritative state.
        return const _Step.terminal(StorefrontPublishStatus.uncertain);
      case 400:
      case 405:
      case 413:
      case 415:
        final expected = switch (status) {
          400 => 'invalid_request',
          405 => 'method_not_allowed',
          413 => 'request_too_large',
          _ => 'unsupported_media_type',
        };
        if (said != expected) return notFromFunction;
        return _Step.terminal(
          StorefrontPublishStatus.invalidRequest,
          invalidField: json['field'] is String
              ? json['field'] as String
              : null,
          invalidReason: json['reason'] is String
              ? json['reason'] as String
              : expected,
        );
      case 401:
        // The function's own `unauthenticated` (a missing / expired / revoked
        // token, or — SEC-1 — an anonymous device/kiosk session or a token
        // whose role/aud is not `authenticated`, refused before any RPC or
        // download), or the platform gateway refusing the caller's JWT
        // (`verify_jwt`) with its own body: either way the session was not
        // accepted — sign in again.
        return const _Step.terminal(StorefrontPublishStatus.unauthenticated);
      case 403:
        return said == 'permission_denied'
            ? const _Step.terminal(StorefrontPublishStatus.denied)
            : notFromFunction;
      case 404:
        return said == 'source_not_found'
            ? const _Step.terminal(StorefrontPublishStatus.sourceMissing)
            : notFromFunction;
      case 409:
        return switch (said) {
          'restart_required' => const _Step.terminal(
            StorefrontPublishStatus.restartRequired,
          ),
          'object_conflict' => const _Step.terminal(
            StorefrontPublishStatus.objectConflict,
          ),
          _ => notFromFunction,
        };
      case 422:
        if (said != 'refused') return notFromFunction;
        final raw = json['code'];
        final code = raw is String && raw.isNotEmpty ? raw : 'unknown';
        if (kStorefrontPublishFaultCodes.contains(code)) {
          // A stage validation reason / recipe argument check: a fault of
          // the request or the server, not of the image.
          return _Step.terminal(
            StorefrontPublishStatus.invalidRequest,
            invalidField: 'refused',
            invalidReason: code,
          );
        }
        return _Step.terminal(
          StorefrontPublishStatus.refused,
          refusalCode: code,
        );
      default:
        // 5xx (engine_unavailable / upstream_unavailable / internal_error) and
        // any other status: the outcome is unknown -> retry once, same rung.
        return _Step.ambiguous(serverUncertain: json['uncertain'] == true);
    }
  }

  /// A well-formed `200 published` answer, or null (treated as ambiguous).
  _Step? _decodePublished(Map<String, Object?> json) {
    if (json['ok'] != true || json['status'] != 'published') return null;
    final m = json['media'];
    if (m is! Map || m['state'] != 'published') return null;
    String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
    int? positive(Object? v) => v is int && v > 0 ? v : null;
    final id = str(m['id']);
    final objectKey = str(m['object_key']);
    final contentHash = str(m['content_hash']);
    final width = positive(m['width']);
    final height = positive(m['height']);
    final bytes = positive(m['bytes']);
    StorefrontVariant? variant;
    for (final v in StorefrontVariant.values) {
      if (v.name == m['variant']) variant = v;
    }
    final bucket = StorefrontSourceBucket.fromWire(m['source_bucket']);
    final sourceKey = str(m['source_key']);
    if (id == null ||
        objectKey == null ||
        contentHash == null ||
        width == null ||
        height == null ||
        bytes == null ||
        variant == null ||
        bucket == null ||
        sourceKey == null) {
      return null;
    }
    final profileVersion = json['profile_version'];
    if (profileVersion != null && profileVersion is! int) return null;
    return _Step.published(
      StorefrontPublishedMedia(
        id: id,
        objectKey: objectKey,
        contentHash: contentHash,
        width: width,
        height: height,
        byteLength: bytes,
        variant: variant,
        sourceBucket: bucket,
        sourceKey: sourceKey,
      ),
      profileVersion: profileVersion as int?,
      alreadyPublished: json['already_published'] == true,
      republished: json['republished'] == true,
      replacedMediaId: str(json['replaced_media_id']),
    );
  }
}

/// One classified answer inside the ladder loop.
class _Step {
  const _Step.ambiguous({this.serverUncertain = false})
    : isAmbiguous = true,
      nextRung = null,
      status = null,
      media = null,
      profileVersion = null,
      alreadyPublished = false,
      republished = false,
      replacedMediaId = null,
      refusalCode = null,
      invalidField = null,
      invalidReason = null;

  const _Step.next(int this.nextRung)
    : isAmbiguous = false,
      serverUncertain = false,
      status = null,
      media = null,
      profileVersion = null,
      alreadyPublished = false,
      republished = false,
      replacedMediaId = null,
      refusalCode = null,
      invalidField = null,
      invalidReason = null;

  const _Step.terminal(
    StorefrontPublishStatus this.status, {
    this.refusalCode,
    this.invalidField,
    this.invalidReason,
  }) : isAmbiguous = false,
       serverUncertain = false,
       nextRung = null,
       media = null,
       profileVersion = null,
       alreadyPublished = false,
       republished = false,
       replacedMediaId = null;

  const _Step.published(
    StorefrontPublishedMedia this.media, {
    this.profileVersion,
    this.alreadyPublished = false,
    this.republished = false,
    this.replacedMediaId,
  }) : isAmbiguous = false,
       serverUncertain = false,
       nextRung = null,
       status = StorefrontPublishStatus.published,
       refusalCode = null,
       invalidField = null,
       invalidReason = null;

  final bool isAmbiguous;
  final bool serverUncertain;
  final int? nextRung;
  final StorefrontPublishStatus? status;
  final StorefrontPublishedMedia? media;
  final int? profileVersion;
  final bool alreadyPublished;
  final bool republished;
  final String? replacedMediaId;
  final String? refusalCode;
  final String? invalidField;
  final String? invalidReason;

  StorefrontPublishResult toResult({
    required String requestId,
    required StorefrontSlot slot,
    required int rung,
    required int calls,
    required bool serverUncertain,
  }) => StorefrontPublishResult(
    status ?? StorefrontPublishStatus.uncertain,
    requestId: requestId,
    slot: slot,
    media: media,
    profileVersion: profileVersion,
    alreadyPublished: alreadyPublished,
    republished: republished,
    replacedMediaId: replacedMediaId,
    refusalCode: refusalCode,
    invalidField: invalidField,
    invalidReason: invalidReason,
    rung: rung,
    calls: calls,
    serverFlaggedUncertain: serverUncertain,
  );
}
