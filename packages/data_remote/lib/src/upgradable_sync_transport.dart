/// [POS-OFFLINE-OPERATIONS-002] Pass A — the HOLD-then-UPGRADE transport for a
/// degraded offline boot.
///
/// When a device cold-boots with the network fully down, the app tree may
/// still mount over durable pairing evidence — but that DEGRADED tree has no
/// authenticated principal yet, so it must NEVER reach the server: an
/// unauthenticated PostgREST call would answer `42501` and poison callers with
/// a false auth verdict (e.g. an outbox AUTH_HOLD for work that was merely
/// offline). And when connectivity returns, the tree must NOT be rebuilt (that
/// would destroy an in-progress cart mid-order).
///
/// This transport solves both: it starts in HOLD mode, where every [invoke]
/// throws a `transient` [SyncTransportException] SYNCHRONOUSLY with zero
/// network IO — indistinguishable from an ordinary offline failure, so every
/// existing repository takes its normal offline path. A single, permanent
/// [upgrade] switches it to delegate to the real authenticated transport in
/// place; the object identity (and therefore every repository built over it)
/// never changes.
library;

import 'sync_rpc_transport.dart';

/// A [SyncRpcTransport] that holds all calls offline until [upgrade]d with the
/// real authenticated transport, then delegates permanently.
class UpgradableSyncTransport implements SyncRpcTransport {
  SyncRpcTransport? _real;
  final List<void Function()> _onUpgrade = <void Function()>[];
  int _heldCallCount = 0;

  /// True once [upgrade] installed the real transport.
  bool get isUpgraded => _real != null;

  /// How many calls were refused in hold mode (diagnostics/tests only —
  /// each one threw synchronously; none reached any wire).
  int get heldCallCount => _heldCallCount;

  /// Registers [listener] to run when (and only when) the single upgrade
  /// happens. Registering after the upgrade never fires it.
  void addOnUpgrade(void Function() listener) => _onUpgrade.add(listener);

  /// Unregisters a previously added upgrade listener (idempotent).
  void removeOnUpgrade(void Function() listener) => _onUpgrade.remove(listener);

  /// Installs the [real] authenticated transport, permanently. The FIRST
  /// upgrade wins and fires the listeners exactly once; any later call is a
  /// no-op (the boot retry loop may race a manual retry — neither may swap a
  /// live delegate out from under in-flight work).
  void upgrade(SyncRpcTransport real) {
    if (_real != null) return;
    _real = real;
    for (final listener in List<void Function()>.of(_onUpgrade)) {
      listener();
    }
  }

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) {
    final real = _real;
    if (real == null) {
      _heldCallCount++;
      // SYNCHRONOUS throw, zero IO: the degraded tree sees an ordinary
      // transient (offline) transport failure — never a server answer.
      throw const SyncTransportException(
        SyncTransportErrorKind.transient,
        message: 'device principal not yet established — boot retry pending',
      );
    }
    return real.invoke(function, params);
  }
}
