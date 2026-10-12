import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// STOREFRONT-PUBLISH-001 — how ONE storefront RPC invoke ended, classified
/// for the one-retry + reconciliation rule the storefront repositories share
/// (the house pattern of `SupabaseRestaurantLogoRepository`).
enum StorefrontRpcAttemptKind {
  /// The server answered with a JSON envelope ([StorefrontRpcAttempt.response]).
  responded,

  /// The DATABASE answered with an error (a PostgREST error carrying a
  /// SQLSTATE, e.g. `42501`): the statement ran and rolled back, so nothing
  /// committed. Definitive — never retried.
  refused,

  /// The outcome is UNKNOWN: a network failure / timeout / gateway error, or
  /// an answer that is not an envelope. The request may or may not have
  /// committed.
  ambiguous,
}

/// The classified result of one invoke.
class StorefrontRpcAttempt {
  const StorefrontRpcAttempt.responded(Map<dynamic, dynamic> this.response)
    : kind = StorefrontRpcAttemptKind.responded,
      failure = null,
      nonEnvelope = false;

  const StorefrontRpcAttempt.refused(SyncTransportException this.failure)
    : kind = StorefrontRpcAttemptKind.refused,
      response = null,
      nonEnvelope = false;

  const StorefrontRpcAttempt.ambiguous({this.nonEnvelope = false})
    : kind = StorefrontRpcAttemptKind.ambiguous,
      response = null,
      failure = null;

  final StorefrontRpcAttemptKind kind;
  final Map<dynamic, dynamic>? response;
  final SyncTransportException? failure;

  /// True when the server DID answer, but with something that is not a JSON
  /// object (a read treats this as malformed; a write as ambiguous).
  final bool nonEnvelope;

  bool get isResponded => kind == StorefrontRpcAttemptKind.responded;
  bool get isRefused => kind == StorefrontRpcAttemptKind.refused;
  bool get isAmbiguous => kind == StorefrontRpcAttemptKind.ambiguous;

  /// The SQLSTATE of a [StorefrontRpcAttemptKind.refused] attempt.
  String? get code => failure?.code;
}

/// A Postgres SQLSTATE (5 upper-case alphanumerics, e.g. `42501`, `22P02`) or a
/// PostgREST error code (`PGRST202`, `PGRST301`, ...). NOT a bare HTTP status:
/// when an error body is not JSON (a gateway page), the PostgREST client puts
/// the HTTP status itself (`'502'`, `'520'`, even `'200'`) into `code`, and
/// such an answer says nothing about whether the statement ran.
final RegExp _databaseCode = RegExp(r'^([0-9A-Z]{5}|PGRST[0-9]+)$');

/// Whether [code] proves the DATABASE (or PostgREST in front of it) answered.
bool isStorefrontDatabaseErrorCode(String? code) =>
    code != null && _databaseCode.hasMatch(code);

/// Invokes [function] once and classifies the outcome. Never throws.
///
/// A [SyncTransportException] carrying a SQLSTATE / PostgREST code (see
/// [isStorefrontDatabaseErrorCode]) is a database answer -> refused.
/// Everything else — a transient/unknown failure, a code-less error, a bare
/// HTTP status from a gateway, any other exception — is ambiguous.
Future<StorefrontRpcAttempt> invokeStorefrontRpc(
  SyncRpcTransport transport,
  String function,
  Map<String, dynamic> params,
) async {
  try {
    final raw = await transport.invoke(function, params);
    if (raw is Map) return StorefrontRpcAttempt.responded(raw);
    return const StorefrontRpcAttempt.ambiguous(nonEnvelope: true);
  } on SyncTransportException catch (e) {
    if (isStorefrontDatabaseErrorCode(e.code)) {
      return StorefrontRpcAttempt.refused(e);
    }
    return const StorefrontRpcAttempt.ambiguous();
  } catch (_) {
    return const StorefrontRpcAttempt.ambiguous();
  }
}

/// ONE logical mutation: invoke, and on an AMBIGUOUS outcome retry EXACTLY
/// once with the SAME params — the same `p_client_request_id`, so a request
/// that did commit is replayed by the server ledger instead of applied twice.
///
/// A refusal of the RETRY does not prove the first attempt never committed
/// (e.g. the session expired in between), so it stays ambiguous and the caller
/// reconciles against a readback.
Future<StorefrontRpcAttempt> invokeStorefrontMutation(
  SyncRpcTransport transport,
  String function,
  Map<String, dynamic> params,
) async {
  final first = await invokeStorefrontRpc(transport, function, params);
  if (!first.isAmbiguous) return first;
  final second = await invokeStorefrontRpc(transport, function, params);
  if (second.isRefused) return const StorefrontRpcAttempt.ambiguous();
  return second;
}
