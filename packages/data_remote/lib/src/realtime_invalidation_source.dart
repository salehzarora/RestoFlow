import 'dart:async';

import 'package:supabase/supabase.dart';

import 'invalidation_hint.dart';
import 'invalidation_source.dart';

/// A Supabase-realtime-backed [InvalidationSource] (RF-058): subscribes to the
/// PRIVATE per-branch broadcast topic `kds:branch:{branchId}` and surfaces the
/// minimal hints. It is the ONLY realtime file and uses the pure-Dart `supabase`
/// package (no `supabase_flutter`).
///
/// Hard rules honoured here: it uses BROADCAST only (never `postgres_changes`,
/// never a table subscription), applies no data, reads no money, and constructs
/// no URL/secret — the authenticated [SupabaseClient] and the [RealtimeScope]
/// are injected (approved decisions A2/A3). Channel authorization is enforced
/// server-side by the `realtime.messages` RLS policy; a hint merely triggers a
/// `sync_pull`, which remains the authoritative, revocation-aware gate.
class RealtimeInvalidationSource implements InvalidationSource {
  RealtimeInvalidationSource({
    required SupabaseClient client,
    required RealtimeScope scope,
    String event = 'kds.invalidate',
  }) : _client = client,
       _scope = scope,
       _event = event;

  /// The broadcast event name the server emits (see the RF-058 migration).
  static const String defaultEvent = 'kds.invalidate';

  final SupabaseClient _client;
  final RealtimeScope _scope;
  final String _event;

  final StreamController<InvalidationHint> _controller =
      StreamController<InvalidationHint>.broadcast();
  RealtimeChannel? _channel;
  bool _started = false;
  bool _disposed = false;

  @override
  Stream<InvalidationHint> get hints => _controller.stream;

  @override
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    final channel = _client.channel(
      _scope.branchTopic,
      opts: const RealtimeChannelConfig(
        private: true,
      ), // private => RLS-authorized
    );
    channel.onBroadcast(event: _event, callback: _onBroadcast);
    channel.subscribe(); // drops/errors are surfaced to the subscribe callback;
    // we intentionally do nothing on error — polling remains the source of truth.
    _channel = channel;
  }

  void _onBroadcast(Map<String, dynamic> message) {
    // DB broadcasts arrive as { type, event, payload: {<hint>} }. Be tolerant of
    // either the wrapped or already-unwrapped shape; parse ONLY allowed keys.
    final raw = message['payload'];
    final map = raw is Map ? Map<String, dynamic>.from(raw) : message;
    final hint = InvalidationHint.tryParse(map);
    if (hint != null && !_controller.isClosed) _controller.add(hint);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await _client.removeChannel(ch);
      } catch (_) {
        // best-effort teardown; never throw from dispose.
      }
    }
    if (!_controller.isClosed) await _controller.close();
  }
}
