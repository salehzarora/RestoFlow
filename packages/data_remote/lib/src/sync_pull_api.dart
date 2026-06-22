import 'package:restoflow_core/restoflow_core.dart';

import 'sync_failure.dart';
import 'sync_pull_request.dart';
import 'sync_pull_response.dart';
import 'sync_rpc_transport.dart';
import 'sync_session.dart';

/// A thin, transport-agnostic wrapper over the `app.sync_pull` RPC (RF-063).
///
/// It builds the RPC params from a [SyncSession] + [SyncPullRequest], invokes
/// the injected [SyncRpcTransport], parses the envelope, and returns a
/// `Result<SyncPullResponse, SyncFailure>`. It never constructs a Supabase
/// client and never holds secrets (approved decisions A1/A2; DECISION D-011).
class SyncPullApi {
  const SyncPullApi(this._transport);

  static const String rpcName = 'sync_pull';

  final SyncRpcTransport _transport;

  /// Call `sync_pull` for [session] with [request].
  ///
  /// Failure mapping (approved decision A5): a `42501`/auth transport error ->
  /// [ReauthRequiredFailure]; transient -> [TransientFailure]; other server
  /// errors -> [ServerFailure]; an unparseable envelope -> [InvalidResponseFailure].
  Future<Result<SyncPullResponse, SyncFailure>> pull(
    SyncSession session,
    SyncPullRequest request,
  ) async {
    final Object? decoded;
    try {
      decoded = await _transport.invoke(
        rpcName,
        request.toRpcParams(
          pinSessionId: session.pinSessionId,
          deviceId: session.deviceId,
        ),
      );
    } on SyncTransportException catch (e) {
      return Failure(_mapTransportError(e));
    }

    try {
      return Success(SyncPullResponse.fromJson(decoded));
    } on FormatException catch (e) {
      return Failure(
        InvalidResponseFailure('invalid sync_pull response: ${e.message}'),
      );
    }
  }

  SyncFailure _mapTransportError(SyncTransportException e) {
    final detail = e.message ?? e.code ?? '';
    return switch (e.kind) {
      SyncTransportErrorKind.auth => ReauthRequiredFailure(
        detail.isEmpty
            ? 'reauth required (42501)'
            : 'reauth required (42501): $detail',
      ),
      SyncTransportErrorKind.transient => TransientFailure(
        detail.isEmpty ? 'transient sync failure' : detail,
      ),
      SyncTransportErrorKind.server => ServerFailure(
        detail.isEmpty ? 'server sync failure' : detail,
      ),
      SyncTransportErrorKind.unknown => ServerFailure(
        detail.isEmpty ? 'unknown sync failure' : detail,
      ),
    };
  }
}
