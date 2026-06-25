import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// A fake [SyncRpcTransport] for unit tests: returns a canned value, throws a
/// canned [SyncTransportException], or delegates to a handler - and records the
/// last invocation so tests can assert the params (e.g. that no user id is sent).
class FakeRpcTransport implements SyncRpcTransport {
  FakeRpcTransport({
    Object? value,
    SyncTransportException? error,
    Future<Object?> Function(String function, Map<String, dynamic> params)?
    handler,
  }) : _value = value,
       _error = error,
       _handler = handler;

  final Object? _value;
  final SyncTransportException? _error;
  final Future<Object?> Function(String, Map<String, dynamic>)? _handler;

  String? lastFunction;
  Map<String, dynamic>? lastParams;
  int invocations = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    invocations++;
    lastFunction = function;
    lastParams = params;
    if (_handler != null) return _handler(function, params);
    if (_error != null) throw _error;
    return _value;
  }
}
