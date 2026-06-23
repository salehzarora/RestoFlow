import 'dart:async';

import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_sync/restoflow_sync.dart';
import 'package:test/test.dart';

/// A controllable fake hint source — no live Supabase (A1/A5).
class _FakeSource implements InvalidationSource {
  final StreamController<InvalidationHint> _c =
      StreamController<InvalidationHint>.broadcast();
  int startCalls = 0;
  bool disposed = false;

  // Tolerant of a closed controller: after the bridge disposes the source on
  // reauth, a stray emit is a no-op (proving no hint can reach a stopped bridge).
  void emit(InvalidationHint h) {
    if (!_c.isClosed) _c.add(h);
  }

  void emitError(Object e) {
    if (!_c.isClosed) _c.addError(e);
  }

  @override
  Stream<InvalidationHint> get hints => _c.stream;
  @override
  Future<void> start() async => startCalls++;
  @override
  Future<void> dispose() async {
    disposed = true;
    if (!_c.isClosed) await _c.close();
  }
}

/// A fake coordinator (KdsSyncSource) counting refreshes and driving state.
class _FakeCoordinator implements KdsSyncSource {
  final StreamController<KdsSyncState> _c =
      StreamController<KdsSyncState>.broadcast();
  KdsSyncState _state = KdsSyncState.initial;
  int refreshCalls = 0;

  void emit(KdsSyncState s) {
    _state = s;
    _c.add(s);
  }

  @override
  KdsSyncState get state => _state;
  @override
  Stream<KdsSyncState> get states => _c.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> refresh() async => refreshCalls++;
  @override
  Future<void> dispose() async => _c.close();
}

InvalidationHint _hint(String entityId) => InvalidationHint(
  organizationId: 'org-1',
  branchId: 'b-1',
  entity: 'orders',
  entityId: entityId,
);

Future<void> _settle({int turns = 20}) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a hint triggers a coordinator refresh', () async {
    final source = _FakeSource();
    final coord = _FakeCoordinator();
    final bridge = KdsRealtimeBridge(
      source: source,
      coordinator: coord,
      delay: (_) async {}, // immediate debounce
    );
    addTearDown(bridge.dispose);

    await bridge.start();
    expect(source.startCalls, 1);

    source.emit(_hint('o1'));
    await _settle();
    expect(coord.refreshCalls, 1);
  });

  test('a hint storm coalesces into a single refresh (debounce)', () async {
    final source = _FakeSource();
    final coord = _FakeCoordinator();
    final gate = Completer<void>();
    final bridge = KdsRealtimeBridge(
      source: source,
      coordinator: coord,
      delay: (_) => gate.future, // hold the debounce window open
    );
    addTearDown(bridge.dispose);
    await bridge.start();

    // Five hints arrive while the debounce window is open.
    for (var i = 0; i < 5; i++) {
      source.emit(_hint('o$i'));
    }
    await _settle();
    expect(
      coord.refreshCalls,
      0,
      reason: 'nothing fires until the window closes',
    );

    gate.complete(); // close the debounce window
    await _settle();
    expect(
      coord.refreshCalls,
      1,
      reason: 'the storm coalesced into one refresh',
    );
  });

  test('reauthRequired stops the bridge and disposes the source', () async {
    final source = _FakeSource();
    final coord = _FakeCoordinator();
    final bridge = KdsRealtimeBridge(
      source: source,
      coordinator: coord,
      delay: (_) async {},
    );
    addTearDown(bridge.dispose);
    await bridge.start();

    coord.emit(const KdsSyncState(status: KdsSyncStatus.reauthRequired));
    await _settle();
    expect(bridge.isStopped, isTrue);
    expect(source.disposed, isTrue);

    // Any further hint must NOT trigger a refresh.
    final before = coord.refreshCalls;
    source.emit(_hint('late'));
    await _settle();
    expect(coord.refreshCalls, before);
  });

  test('does not start listening if already reauthRequired', () async {
    final source = _FakeSource();
    final coord = _FakeCoordinator()
      ..emit(const KdsSyncState(status: KdsSyncStatus.reauthRequired));
    final bridge = KdsRealtimeBridge(
      source: source,
      coordinator: coord,
      delay: (_) async {},
    );
    addTearDown(bridge.dispose);

    await bridge.start();
    expect(bridge.isStopped, isTrue);
    source.emit(_hint('x'));
    await _settle();
    expect(coord.refreshCalls, 0);
  });

  test(
    'a source error does not crash the bridge; later hints still refresh',
    () async {
      final source = _FakeSource();
      final coord = _FakeCoordinator();
      final bridge = KdsRealtimeBridge(
        source: source,
        coordinator: coord,
        delay: (_) async {},
      );
      addTearDown(bridge.dispose);
      await bridge.start();

      source.emitError(StateError('realtime dropped'));
      await _settle();
      expect(
        bridge.isStopped,
        isFalse,
        reason: 'an error must not stop polling/the bridge',
      );

      source.emit(_hint('o1'));
      await _settle();
      expect(coord.refreshCalls, 1);
    },
  );
}
