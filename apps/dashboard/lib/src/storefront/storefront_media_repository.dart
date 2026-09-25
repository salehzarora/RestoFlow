import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'storefront_models.dart';
import 'storefront_rpc.dart';

/// STOREFRONT-PUBLISH-001 — the classified outcome of `list_storefront_media`.
enum StorefrontMediaListStatus {
  ok,

  /// `not_found`: below manager / another tenant / unknown restaurant (no
  /// leak about which).
  denied,

  /// A transport failure or a database refusal (e.g. `42501`).
  unavailable,

  /// An envelope this build cannot decode (typed, never a crash).
  malformed,
}

/// The restaurant's storefront media — the SERVER's current state, newest
/// first (at most 200 rows).
class StorefrontMediaList {
  const StorefrontMediaList.ok({
    required String this.mediaPrefix,
    required this.media,
  }) : status = StorefrontMediaListStatus.ok,
       decodeError = null,
       code = null;

  const StorefrontMediaList.denied()
    : status = StorefrontMediaListStatus.denied,
      mediaPrefix = null,
      media = const <StorefrontMediaRow>[],
      decodeError = null,
      code = null;

  const StorefrontMediaList.unavailable({this.code})
    : status = StorefrontMediaListStatus.unavailable,
      mediaPrefix = null,
      media = const <StorefrontMediaRow>[],
      decodeError = null;

  const StorefrontMediaList.malformed(
    StorefrontDecodeException this.decodeError,
  ) : status = StorefrontMediaListStatus.malformed,
      mediaPrefix = null,
      media = const <StorefrontMediaRow>[],
      code = null;

  final StorefrontMediaListStatus status;
  final String? mediaPrefix;
  final List<StorefrontMediaRow> media;
  final StorefrontDecodeException? decodeError;

  /// The SQLSTATE of an unavailable database refusal.
  final String? code;

  bool get isOk => status == StorefrontMediaListStatus.ok;

  /// The row with [id] (case-insensitive), or null.
  StorefrontMediaRow? byId(String id) {
    final wanted = id.toLowerCase();
    for (final row in media) {
      if (row.id.toLowerCase() == wanted) return row;
    }
    return null;
  }
}

/// The classified outcome of a retract / cancel.
enum StorefrontMediaActionStatus {
  /// Done (retract: LIVE -> RETRACTED, or already retracted; cancel: the
  /// STAGED row is gone). The storage object is always KEPT.
  ok,

  /// Retract refused: a profile slot still points at the row
  /// ([StorefrontMediaActionResult.slots]) — clear or replace the slot first.
  mediaInUse,

  /// Retract refused: the row is STAGED (use cancel instead).
  mediaNotPublished,

  /// Cancel refused: the row is LIVE or RETRACTED (only STAGED rows cancel).
  mediaPublished,

  /// No such row for this restaurant.
  notFound,

  /// `permission_denied`: the caller may not manage storefront media.
  denied,

  /// `stale_request`: a REPLAY of this request (the same id) found the row
  /// in a state the request no longer describes — e.g. a retract replayed
  /// after the row was re-published (RETRACTED -> LIVE), or a row that is
  /// gone. Nothing is claimed (never "retracted"): the caller re-reads the
  /// authoritative list and shows it.
  staleRequest,

  /// A database refusal (`42501`) or an unrecognised error: nothing changed.
  unavailable,

  /// The outcome is UNKNOWN (both attempts lost). The re-listed server state,
  /// when it could be read, is in [StorefrontMediaActionResult.recovered];
  /// "Try again" reuses [StorefrontMediaActionResult.requestId].
  uncertain,
}

/// A retract / cancel result.
class StorefrontMediaActionResult {
  const StorefrontMediaActionResult(
    this.status, {
    required this.mediaId,
    required this.requestId,
    this.slots = const <StorefrontSlot>[],
    this.alreadyRetracted = false,
    this.idempotentReplay = false,
    this.code,
    this.recovered,
  });

  final StorefrontMediaActionStatus status;
  final String mediaId;

  /// The idempotency key used — pass it back to retry THIS request.
  final String requestId;

  /// mediaInUse: the profile slots pointing at the row.
  final List<StorefrontSlot> slots;
  final bool alreadyRetracted;
  final bool idempotentReplay;

  /// unavailable: the SQLSTATE of a database refusal.
  final String? code;

  /// The authoritative list read after an unknown outcome (null when the
  /// outcome was known, or when even the list could not be read).
  final StorefrontMediaList? recovered;

  bool get isOk => status == StorefrontMediaActionStatus.ok;
}

/// Lists, retracts and cancels the restaurant's storefront media through the
/// PUBLISH-001 RPCs (caller JWT only; no service-role key — D-011). Nothing
/// here ever deletes a storage object. Faked in widget tests.
abstract interface class StorefrontMediaRepository {
  Future<StorefrontMediaList> list();

  /// LIVE -> RETRACTED (the object is kept). Pass [requestId] to retry an
  /// earlier request; otherwise a fresh one is minted.
  Future<StorefrontMediaActionResult> retract(
    String mediaId, {
    String? requestId,
  });

  /// Deletes a STAGED row (never the object).
  Future<StorefrontMediaActionResult> cancel(
    String mediaId, {
    String? requestId,
  });
}

/// The real, Supabase-backed [StorefrontMediaRepository] over
/// `public.list_storefront_media` / `public.retract_storefront_media` /
/// `public.cancel_storefront_media`.
class SupabaseStorefrontMediaRepository implements StorefrontMediaRepository {
  SupabaseStorefrontMediaRepository({
    required SyncRpcTransport transport,
    required this.organizationId,
    required this.restaurantId,
    int Function()? nonce,
  }) : _t = transport,
       _nonce = nonce ?? _microNonce;

  static const String listFunction = 'list_storefront_media';
  static const String retractFunction = 'retract_storefront_media';
  static const String cancelFunction = 'cancel_storefront_media';

  /// The idempotency-key namespace of a media action.
  static const String requestIdPrefix = 'pbl:storefront-media:';

  final SyncRpcTransport _t;
  final String organizationId;
  final String restaurantId;
  final int Function() _nonce;

  static int _microNonce() => DateTime.now().microsecondsSinceEpoch;

  @override
  Future<StorefrontMediaList> list() async {
    final attempt = await invokeStorefrontRpc(_t, listFunction, {
      'p_organization_id': organizationId,
      'p_restaurant_id': restaurantId,
    });
    if (attempt.nonEnvelope) {
      return const StorefrontMediaList.malformed(
        StorefrontDecodeException('envelope', 'not an object'),
      );
    }
    if (!attempt.isResponded) {
      return StorefrontMediaList.unavailable(code: attempt.code);
    }
    final raw = attempt.response!;
    if (raw['ok'] != true) {
      return raw['error'] == 'not_found'
          ? const StorefrontMediaList.denied()
          : const StorefrontMediaList.unavailable();
    }
    // Defensive: a list stamped for ANOTHER restaurant is never shown.
    final scope = raw['restaurant_id'];
    if (scope != null &&
        (scope is! String ||
            scope.toLowerCase() != restaurantId.toLowerCase())) {
      return const StorefrontMediaList.malformed(
        StorefrontDecodeException('restaurant_id', 'another scope'),
      );
    }
    try {
      return StorefrontMediaList.ok(
        mediaPrefix: decodeStorefrontString(raw, 'media_prefix', ''),
        media: decodeStorefrontMediaRows(raw['media'], 'media'),
      );
    } on StorefrontDecodeException catch (e) {
      return StorefrontMediaList.malformed(e);
    }
  }

  @override
  Future<StorefrontMediaActionResult> retract(
    String mediaId, {
    String? requestId,
  }) => _act(_MediaOp.retract, mediaId, requestId);

  @override
  Future<StorefrontMediaActionResult> cancel(
    String mediaId, {
    String? requestId,
  }) => _act(_MediaOp.cancel, mediaId, requestId);

  Future<StorefrontMediaActionResult> _act(
    _MediaOp op,
    String mediaId,
    String? requestId,
  ) async {
    if (requestId != null && !isCanonicalUuid(requestId)) {
      throw ArgumentError.value(requestId, 'requestId', 'not a canonical uuid');
    }
    // ONE stable id per logical action; the one retry reuses it.
    final id =
        requestId ??
        storefrontRequestId(requestIdPrefix, [
          op.name,
          organizationId,
          restaurantId,
          mediaId,
        ], _nonce());
    final attempt = await invokeStorefrontMutation(_t, op.function, {
      'p_client_request_id': id,
      'p_organization_id': organizationId,
      'p_restaurant_id': restaurantId,
      'p_media_id': mediaId,
    });
    switch (attempt.kind) {
      case StorefrontRpcAttemptKind.responded:
        return _classify(attempt.response!, mediaId, id);
      case StorefrontRpcAttemptKind.refused:
        return StorefrontMediaActionResult(
          StorefrontMediaActionStatus.unavailable,
          mediaId: mediaId,
          requestId: id,
          code: attempt.code,
        );
      case StorefrontRpcAttemptKind.ambiguous:
        return _reconcile(op, mediaId, id);
    }
  }

  StorefrontMediaActionResult _classify(
    Map<dynamic, dynamic> raw,
    String mediaId,
    String id,
  ) {
    StorefrontMediaActionResult result(
      StorefrontMediaActionStatus status, {
      List<StorefrontSlot> slots = const <StorefrontSlot>[],
    }) => StorefrontMediaActionResult(
      status,
      mediaId: mediaId,
      requestId: id,
      slots: slots,
      alreadyRetracted: raw['already_retracted'] == true,
      idempotentReplay: raw['idempotent_replay'] == true,
    );
    if (raw['ok'] == true) return result(StorefrontMediaActionStatus.ok);
    switch (raw['error']) {
      case 'media_in_use':
        final slots = raw['slots'];
        return result(
          StorefrontMediaActionStatus.mediaInUse,
          slots: slots is List
              ? List.unmodifiable(
                  slots
                      .map(StorefrontSlot.fromWire)
                      .whereType<StorefrontSlot>(),
                )
              : const <StorefrontSlot>[],
        );
      case 'media_not_published':
        return result(StorefrontMediaActionStatus.mediaNotPublished);
      case 'media_published':
        return result(StorefrontMediaActionStatus.mediaPublished);
      case 'not_found':
        return result(StorefrontMediaActionStatus.notFound);
      case 'permission_denied':
        return result(StorefrontMediaActionStatus.denied);
      case 'stale_request':
        return result(StorefrontMediaActionStatus.staleRequest);
      default:
        // A RESPONDED-but-unrecognised error means no commit happened.
        return result(StorefrontMediaActionStatus.unavailable);
    }
  }

  /// Both attempts were lost: re-list and classify from the server's CURRENT
  /// state. A state that already shows the intended end (retracted / gone) is
  /// ok; a state the action cannot apply to is typed; an unchanged state stays
  /// `uncertain` (the request may still land) with the list attached.
  Future<StorefrontMediaActionResult> _reconcile(
    _MediaOp op,
    String mediaId,
    String id,
  ) async {
    final current = await list();
    StorefrontMediaActionResult result(StorefrontMediaActionStatus status) =>
        StorefrontMediaActionResult(
          status,
          mediaId: mediaId,
          requestId: id,
          recovered: current,
        );
    if (!current.isOk) {
      // Not even the list could be read: truly unknown, nothing to show.
      return StorefrontMediaActionResult(
        StorefrontMediaActionStatus.uncertain,
        mediaId: mediaId,
        requestId: id,
      );
    }
    final row = current.byId(mediaId);
    switch (op) {
      case _MediaOp.retract:
        if (row == null) return result(StorefrontMediaActionStatus.notFound);
        return switch (row.state) {
          StorefrontMediaState.retracted => result(
            StorefrontMediaActionStatus.ok,
          ),
          StorefrontMediaState.staged => result(
            StorefrontMediaActionStatus.mediaNotPublished,
          ),
          StorefrontMediaState.published => result(
            StorefrontMediaActionStatus.uncertain,
          ),
        };
      case _MediaOp.cancel:
        if (row == null) return result(StorefrontMediaActionStatus.ok);
        return switch (row.state) {
          StorefrontMediaState.staged => result(
            StorefrontMediaActionStatus.uncertain,
          ),
          StorefrontMediaState.published || StorefrontMediaState.retracted =>
            result(StorefrontMediaActionStatus.mediaPublished),
        };
    }
  }
}

enum _MediaOp {
  retract(SupabaseStorefrontMediaRepository.retractFunction),
  cancel(SupabaseStorefrontMediaRepository.cancelFunction);

  const _MediaOp(this.function);

  final String function;
}
